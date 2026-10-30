/**
 * Fudan University repository - handles UIS login, academic data, campus services.
 * Ported from lib/repository/fdu/* and lib/repository/danke/*
 */

import { AcademicAccount } from '../common/AcademicAccount'
import { Constant } from '../common/Constant'
import { GraduateRepository } from './GraduateRepository'
import { CardRepository } from './CardRepository'
import { BaseRepository } from './BaseRepository'
import { HttpError, HttpUtil, CampusSsoReadOptions } from '../util/HttpUtil'
import { DormHistoryQuery } from '../model/DormHistoryDiagnostics'
import { DormRequestPolicy } from '../model/DormRequestPolicy'
import { Person, PersonInfo } from '../model/Person'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { FduLogin, FduLoginError, FduLoginFailure, FduSession } from './FduLogin'
import { CampusService } from '../common/CampusService'
import { FduWebAuth, FduAuthCancelledError } from '../common/FduWebAuth'
import { FduAuthPolicy, FduAuthChallenge } from '../model/FduAuth'
import { CampusCookies } from '../common/CampusCookies'
import { CampusCredentialStore } from '../common/CampusCredentialStore'
import {
  Course, CourseGrade, ExamSchedule, GpaListItem, ElectricityInfo,
  EmptyClassroom, BusSchedule, Announcement, TimeTableEntry, SemesterInfo
} from '../model/Academic'
import { ZlappRepository, ZlappDataFormatError } from './ZlappRepository'
import { JwglRepository } from './JwglRepository'
import { ClassroomRepository } from './ClassroomRepository'
import { DataCenterRepository } from './DataCenterRepository'
import { PreferencesUtil } from '../util/PreferencesUtil'

interface SavedCampusSession { service: string; cookies: string }
export class AaoNoticePage {
  rows: Announcement[] = []
  hasMore: boolean = false
}
interface SavedCampusSessions { owner: string; sessions: SavedCampusSession[] }
class RejectedCampusSession {
  cookies: string
  constructor(cookies: string) { this.cookies = cookies }
}

export interface LoginResult {
  success: boolean
  person: Person | null
  error: string
}

export class FduRepository extends BaseRepository {
  private static instance: FduRepository | null = null

  /**
   * The service the default login is run against.
   *
   * Upstream's primary login reads the ehall student profile. Dining is opened
   * lazily so a dining-server outage cannot block a valid campus login.
   */
  private static readonly UIS_SERVICE: string = CampusService.EHALL

  /**
   * Cookies of the live campus session; empty while logged out.
   *
   * Named `campusCookies` rather than `sessionCookies` because ArkTS rejects a
   * field and a method sharing one identifier, and the accessor below is part
   * of the public surface.
   */
  private campusCookies: string = ''

  /** Service-origin snapshots for restart; the Web cookie jar retains real path and expiry rules. */
  private serviceSessions: Map<string, string> = new Map<string, string>()
  private authQueue: Promise<void> = Promise.resolve()
  private authFlights: Map<string, Promise<string>> = new Map<string, Promise<string>>()
  private rejectedSessions: Map<string, RejectedCampusSession> = new Map<string, RejectedCampusSession>()
  private silentFlights: Map<string, Promise<string>> = new Map<string, Promise<string>>()
  private silentRetryAfter: Map<string, number> = new Map<string, number>()
  private silentErrors: Map<string, Error> = new Map<string, Error>()
  private recoveryDiagnostics: Map<string, string> = new Map<string, string>()
  private credentialRetryAfter: number = 0
  private credentialBlocked: boolean = false
  private credentialFailure: Error | null = null
  private graduateVerificationService: string = GraduateRepository.TIMETABLE_HOSTS[0] + GraduateRepository.TIMETABLE_PATH
  private sessionEpoch: number = 0
  /** Cancelling a verification batch must not invalidate unrelated successful
   * data reads, cache keys or the already logged-in campus account. */
  private authenticationEpoch: number = 0
  private storageQueue: Promise<void> = Promise.resolve()
  /** Brief route hint avoids repeating a 3-second LAN timeout for every building off campus. */
  private classroomDirectRetryAfter: number = 0

  async restoreSession(person: Person): Promise<void> {
    if (!person.isLoggedIn()) return
    if (this.credentialId !== person.getStudentId() || this.campusCookies !== person.getToken()) {
      this.sessionEpoch++
      this.authenticationEpoch++
      this.credentialPw = ''
      this.serviceSessions.clear()
      this.rejectedSessions.clear()
      this.silentRetryAfter.clear()
      this.silentErrors.clear()
      this.recoveryDiagnostics.clear()
      this.credentialRetryAfter = 0
      this.credentialBlocked = false
      this.credentialFailure = null
      this.classroomDirectRetryAfter = 0
      ClassroomRepository.invalidate()
      JwglRepository.getInstance().forgetSession()
      CardRepository.getInstance().setSession('')
      ZlappRepository.getInstance().forgetSession()
    }
    const epoch: number = this.sessionEpoch
    this.credentialId = person.getStudentId()
    CampusCredentialStore.bind(this.credentialId)
    this.campusCookies = person.getToken()
    this.httpUtil.setPerson(person)
    CampusCookies.resume()
    await CampusCookies.restore(this.credentialId)
    if (epoch !== this.sessionEpoch) return
    // Old releases stored the dining service's token in Person. Do not label
    // it as ehall after changing the main entry: persisted per-origin sessions
    // and the browser jar supply their actual owners below.
    try {
      const raw = await PreferencesUtil.getInstance().getString('campus_service_sessions', '')
      if (!raw || epoch !== this.sessionEpoch) return
      const saved = JSON.parse(raw) as SavedCampusSessions
      if (saved.owner !== this.credentialId || !Array.isArray(saved.sessions)) return
      for (const session of saved.sessions) {
        if (typeof session.service === 'string' && typeof session.cookies === 'string' &&
          FduAuthPolicy.isCampusUrl(session.service) && !FduAuthPolicy.isIdUrl(session.service)) {
          this.serviceSessions.set(CampusService.sessionKey(session.service), session.cookies)
        }
      }
    } catch (e) {
      // An old/malformed cache can be rebuilt through official browser SSO.
    }
  }

  private saveSessions(): Promise<void> {
    const sessions: SavedCampusSession[] = []
    this.serviceSessions.forEach((cookies: string, service: string) => sessions.push({ service: service, cookies: cookies }))
    const saved: SavedCampusSessions = { owner: this.credentialId, sessions: sessions }
    const json: string = JSON.stringify(saved)
    this.storageQueue = this.storageQueue.catch(() => {}).then(() =>
      PreferencesUtil.getInstance().putString('campus_service_sessions', json))
    return this.storageQueue
  }


  /**
   * Credentials retained in memory after a successful login, so later services
   * can be opened without asking the user again.
   *
   * Why this is necessary: a CAS ticket opens exactly one service, so the
   * session that gets 食堂拥挤度 open does NOT get the card, the timetable or
   * the bus open. Upstream solves this the same way and for the same reason
   * (`FudanSession` keeps the `PersonInfo` — credentials included — and logs in
   * lazily when a service is first touched), rather than logging in to every
   * known service up front.
   *
   * The current login may retain memory credentials. Successful login also
   * saves an account-bound OS AssetStore item for restart recovery; no password
   * enters Preferences, route parameters, diagnostics or the cookie snapshot.
   */
  private credentialId: string = ''
  private credentialPw: string = ''

  private constructor() {
    super()
  }

  static getInstance(): FduRepository {
    if (!FduRepository.instance) {
      FduRepository.instance = new FduRepository()
    }
    return FduRepository.instance
  }

  /** Validate the native password form first; only CAPTCHA/MFA continues in Web. */
  async login(studentId: string, password: string): Promise<LoginResult> {
    if (studentId.length === 0 || password.length === 0) {
      const failResult: LoginResult = { success: false, person: null, error: '学号和密码不能为空' }
      return failResult
    }

    this.forgetCredentials()
    CampusCookies.bind(studentId)
    CampusCredentialStore.bind(studentId)
    const epoch = this.sessionEpoch
    try {
      const cookies: string = await this.loginForService(
        FduRepository.UIS_SERVICE, studentId, password)
      if (epoch !== this.sessionEpoch) throw new FduAuthCancelledError('登录已取消，请重新登录')
      this.campusCookies = cookies
      // Retained so ensureSession() can open the other CAS services later
      // without a second prompt. See the field comment for why.
      this.credentialId = studentId
      this.credentialPw = password
      try { await CampusCredentialStore.save(studentId, password) } catch (e) {}
      if (epoch !== this.sessionEpoch) throw new FduAuthCancelledError('登录已取消，请重新登录')
      await this.saveSessions()
      if (epoch !== this.sessionEpoch) throw new FduAuthCancelledError('登录已取消，请重新登录')

      const info: PersonInfo = {
        id: studentId,
        // Not invented: the server authenticated this id, so it is real. The
        // rest is left blank rather than filled with a placeholder name.
        name: '',
        studentId: studentId,
        department: '',
        grade: '',
        email: '',
        gender: '',
        avatarUrl: '',
      }
      // The campus session IS a cookie, not a bearer token; it is stored in
      // the token slot so `isLoggedIn()` reflects reality. Campus requests
      // must send it as a Cookie header (see sessionCookies()).
      const person = new Person(info, cookies)
      this.httpUtil.setPerson(person)

      const ok: LoginResult = { success: true, person: person, error: '' }
      return ok
    } catch (e) {
      const error: string = ErrorDiagnostics.message(e as Object,
        e instanceof FduLoginError ? e.message : '登录失败，请检查网络后重试。')
      const failed: LoginResult = { success: false, person: null, error: error }
      return failed
    }
  }

  /** Called by initial login or an explicit verification button only. Passive
   * reads must use ensureSession/withService, which never navigate. */
  loginForService(service: string, studentId: string, password: string, force: boolean = false): Promise<string> {
    const flightKey = String(this.sessionEpoch) + ':' + String(this.authenticationEpoch) + '\n' + studentId + '\n' +
      (service === CampusService.LIFE_CODE ? service : CampusService.sessionKey(service))
    const flight = this.authFlights.get(flightKey)
    if (flight !== undefined) return flight
    const task = this.loginForServiceOnce(service, studentId, password, force)
    this.authFlights.set(flightKey, task)
    task.then(() => { if (this.authFlights.get(flightKey) === task) this.authFlights.delete(flightKey) },
      () => { if (this.authFlights.get(flightKey) === task) this.authFlights.delete(flightKey) })
    return task
  }

  private loginForServiceOnce(service: string, studentId: string, password: string, force: boolean): Promise<string> {
    const epoch: number = this.sessionEpoch
    const authenticationEpoch: number = this.authenticationEpoch
    // Dashboard starts several CAS services together. Serialize handshakes and
    // browser continuations so only one verification page is ever presented.
    const task: Promise<string> = this.authQueue.then(async (): Promise<string> => {
      if (epoch !== this.sessionEpoch || authenticationEpoch !== this.authenticationEpoch) throw new Error('登录已取消，请重新登录')
      const existing: string = this.cookiesFor(service)
      if (!force && existing.length > 0 && !this.needsVerification(service)) return existing
      let cookies: string = ''
      try {
        cookies = await this.openService(service, studentId, password, epoch, authenticationEpoch)
      } catch (e) {
        // Cancel the waiting batch too, so the dashboard does not open a new
        // verification page immediately after the user closed the previous one.
        if (e instanceof FduAuthCancelledError && epoch === this.sessionEpoch &&
          authenticationEpoch === this.authenticationEpoch) this.authenticationEpoch++
        throw e as Error
      }
      if (epoch !== this.sessionEpoch || authenticationEpoch !== this.authenticationEpoch) throw new Error('登录已取消，请重新登录')
      this.serviceSessions.set(CampusService.sessionKey(service), cookies)
      this.clearRejectedOrigin(service)
      // An explicit completed authentication may renew shared ID SSO. Let
      // sibling services redeem it once instead of retaining their old MFA
      // cooldown; rejected business cookies remain marked until validated.
      this.silentRetryAfter.clear()
      this.silentErrors.clear()
      this.recoveryDiagnostics.clear()
      this.credentialRetryAfter = 0
      this.credentialBlocked = false
      this.credentialFailure = null
      await this.saveSessions()
      this.requireAuthentication(epoch, authenticationEpoch)
      await CampusCookies.persist()
      this.requireAuthentication(epoch, authenticationEpoch)
      return cookies
    })
    this.authQueue = task.then(() => {}, () => {})
    return task
  }

  /** Only a user action may present an official authentication page. */
  verifyService(service: string): Promise<string> {
    if (!this.credentialId || !FduAuthPolicy.isCampusUrl(service)) {
      return Promise.reject(new HttpError(-2, 0, '请先登录复旦账号，再继续身份验证。', ''))
    }
    return this.loginForService(service, this.credentialId, this.credentialPw, true)
  }

  needsVerification(service: string): boolean {
    const cookies = this.cookiesFor(service)
    return !cookies || this.rejectionFor(service, cookies) !== undefined
  }

  private rejectionFor(service: string, cookies: string): RejectedCampusSession | undefined {
    const exact = this.rejectedSessions.get(service)
    if (exact !== undefined && exact.cookies === cookies) return exact
    if (service === CampusService.LIFE_CODE) return undefined
    let found: RejectedCampusSession | undefined = undefined
    const origin = CampusService.sessionKey(service)
    this.rejectedSessions.forEach((value: RejectedCampusSession, key: string) => {
      // Standard callback endpoints share their host's rejected session.
      // The QR-only cookie path must never poison the ordinary epay service.
      if (key !== CampusService.LIFE_CODE && CampusService.sessionKey(key) === origin && value.cookies === cookies) found = value
    })
    return found
  }

  /** Undergraduate callbacks share their host. Graduate timetable verification
   * targets the last protected endpoint that actually rejected the session. */
  academicService(feature: string): string {
    if (AcademicAccount.isGraduate()) return feature === 'timetable' ?
      this.graduateVerificationService : GraduateRepository.SCORE_ENTRY
    return feature === 'timetable' ? CampusService.TIMETABLE : CampusService.GPA
  }

  private clearRejectedOrigin(service: string): void {
    const origin = CampusService.sessionKey(service)
    const keys: string[] = []
    this.rejectedSessions.forEach((_value: RejectedCampusSession, key: string) => {
      if (CampusService.sessionKey(key) === origin) keys.push(key)
    })
    for (const key of keys) this.rejectedSessions.delete(key)
    this.silentRetryAfter.delete(this.verificationKey(service))
    this.silentErrors.delete(this.verificationKey(service))
  }

  private requireAuthentication(epoch: number, authenticationEpoch: number): void {
    if (epoch !== this.sessionEpoch || authenticationEpoch !== this.authenticationEpoch) {
      throw new FduAuthCancelledError('登录已取消，请重新登录')
    }
  }

  private async openService(service: string, studentId: string, password: string,
    epoch: number, authenticationEpoch: number): Promise<string> {
    await FduWebAuth.prepareSession()
    this.requireAuthentication(epoch, authenticationEpoch)
    const login = new FduLogin(this.httpUtil)
    // A completed main login is reused by the other services before asking for
    // any further interaction. No fresh password exchange replaces its SSO.
    const sharedId = this.credentialId === studentId ? await CampusCookies.hasIdSession() : false
    let existingChallenge: FduAuthChallenge | null = null
    this.requireAuthentication(epoch, authenticationEpoch)
    if (sharedId) {
      try {
        const resumed = await login.resume(service, this.authenticationEntry(service))
        this.requireAuthentication(epoch, authenticationEpoch)
        return resumed.serviceCookies ?? ''
      } catch (e) {
        this.requireAuthentication(epoch, authenticationEpoch)
        if (!(e instanceof FduLoginError) || e.failure !== FduLoginFailure.ENHANCED_AUTH_REQUIRED) throw e as Error
        existingChallenge = e.challenge
      }
    }
    const availablePassword = password || await CampusCredentialStore.load(studentId)
    this.requireAuthentication(epoch, authenticationEpoch)
    if (!availablePassword) {
      let challenge = existingChallenge ?? new FduAuthChallenge(this.authenticationEntry(service), service, [])
      // ArkWeb can stall before its first document when it starts at WebVPN.
      // Obtain ID's real context through one native GET instead; never invent
      // its fragment or restart a complete/MFA challenge already in progress.
      if (FduAuthPolicy.isServiceUrl(challenge.loginUrl, service) ||
        FduAuthPolicy.isIncompleteIdLoginUrl(challenge.loginUrl)) {
        challenge = await login.browserChallenge(service)
        this.requireAuthentication(epoch, authenticationEpoch)
      }
      return this.authenticateService(login, challenge, studentId, '')
    }
    try {
      const result = await login.login(service, studentId, availablePassword)
      this.requireAuthentication(epoch, authenticationEpoch)
      if (result.serviceCookies) return result.serviceCookies
      const redeemed = await login.resume(service, result.targetUrl)
      this.requireAuthentication(epoch, authenticationEpoch)
      return redeemed.serviceCookies ?? ''
    } catch (e) {
      this.requireAuthentication(epoch, authenticationEpoch)
      if (!(e instanceof FduLoginError) || e.challenge === null ||
        (e.failure !== FduLoginFailure.ENHANCED_AUTH_REQUIRED && e.failure !== FduLoginFailure.CAPTCHA_REQUIRED)) throw e as Error
      return this.authenticateService(login, e.challenge, studentId, availablePassword)
    }
  }

  private authenticationEntry(service: string): string {
    // Unlike ordinary service entries, ehall's home is public. Its upstream
    // manualLoginUrl must perform the CAS exchange before reading the profile.
    return service === CampusService.EHALL ? service : CampusService.entryUrl(service)
  }

  /** Browser return means ID interaction finished, not that native WebVPN
   * requests are authenticated. Confirm the portal once with the same shared
   * jar before resolving; never show a second page or replay the user action. */
  private async authenticateService(login: FduLogin, challenge: FduAuthChallenge,
    studentId: string, password: string): Promise<string> {
    const epoch = this.sessionEpoch
    const authEpoch = this.authenticationEpoch
    const cookies = await FduWebAuth.authenticate(challenge, studentId, password)
    this.requireAuthentication(epoch, authEpoch)
    if (!FduAuthPolicy.isWebVpnLoginUrl(challenge.serviceUrl)) return cookies
    const result = await login.resume(challenge.serviceUrl, CampusService.entryUrl(challenge.serviceUrl))
    this.requireAuthentication(epoch, authEpoch)
    return result.serviceCookies ?? ''
  }

  private verificationKey(service: string): string {
    return service === CampusService.LIFE_CODE ? service : CampusService.sessionKey(service)
  }

  /** A missing service session may silently redeem shared SSO once. Identity
   * and protocol backoff remains five minutes; transient read transport errors
   * receive a short cooldown instead of freezing a recovered network.
   * The same queue prevents competing CAS contexts and the same-origin flight
   * coalesces dashboard cards. Safe reads may renew a rejected ID session with
   * OS-protected credentials once; this path never presents UI. */
  private async resumeService(service: string, refreshExisting: boolean = false,
    readOptions?: CampusSsoReadOptions, recoverCredentials: boolean = true): Promise<string> {
    const key = this.verificationKey(service)
    const active = this.silentFlights.get(key)
    if (active !== undefined) return active
    const epoch = this.sessionEpoch
    const authEpoch = this.authenticationEpoch
    if (!this.credentialId) return ''
    if (Date.now() < (this.silentRetryAfter.get(key) ?? 0)) {
      const failure = this.silentErrors.get(key)
      if (failure !== undefined) throw failure
      return ''
    }
    // A valid portal session can outlive the ID session. The history recovery
    // must check its protected page before deciding whether SSO is needed.
    if (readOptions === undefined && !await CampusCookies.hasIdSession()) {
      const available = recoverCredentials ? this.credentialPw || await CampusCredentialStore.load(this.credentialId) : ''
      if (!available) {
        this.recoveryDiagnostics.set(key, 'sso=unavailable; idCandidate=false; credentialCandidate=false\n' +
          (typeof CampusCookies.diagnostics === 'function' ? CampusCookies.diagnostics() : 'cookieRestore=unavailable') + '\n' +
          CampusCredentialStore.diagnostics())
        return ''
      }
    }
    if (epoch !== this.sessionEpoch || authEpoch !== this.authenticationEpoch) return ''
    const joined = this.silentFlights.get(key)
    if (joined !== undefined) return joined
    const task = this.authQueue.then(async (): Promise<string> => {
      if (epoch !== this.sessionEpoch || authEpoch !== this.authenticationEpoch) return ''
      const existing = this.cookiesFor(service)
      if (!refreshExisting && existing && !this.needsVerification(service)) return existing
      this.silentRetryAfter.set(key, Date.now() + 300000)
      this.silentErrors.delete(key)
      this.recoveryDiagnostics.delete(key)
      try {
        const login = new FduLogin(this.httpUtil)
        let result: FduSession
        try { result = await login.resume(service, this.authenticationEntry(service), readOptions) }
        catch (e) {
          if (!(e instanceof FduLoginError) || e.failure !== FduLoginFailure.ENHANCED_AUTH_REQUIRED) throw e as Error
          this.recoveryDiagnostics.set(key, e.diagnostics)
          const renewed = recoverCredentials ? await this.recoverWithCredential(login, service, epoch, authEpoch) : null
          if (renewed === null) throw e
          result = renewed
        }
        if (epoch !== this.sessionEpoch || authEpoch !== this.authenticationEpoch) return ''
        const cookies = result.serviceCookies ?? ''
        if (cookies) {
          if (service === CampusService.DORM && result.dormResponse !== undefined) {
            ZlappRepository.getInstance().acceptDormSso(cookies, result.dormResponse)
          }
          this.serviceSessions.set(CampusService.sessionKey(service), cookies)
          this.clearRejectedOrigin(service)
          await this.saveSessions()
          if (epoch !== this.sessionEpoch || authEpoch !== this.authenticationEpoch) return ''
          await CampusCookies.persist()
          if (epoch !== this.sessionEpoch || authEpoch !== this.authenticationEpoch) return ''
        }
        return cookies
      } catch (e) {
        if (epoch !== this.sessionEpoch || authEpoch !== this.authenticationEpoch) return ''
        if (e instanceof FduLoginError && e.failure === FduLoginFailure.ENHANCED_AUTH_REQUIRED) {
          if (readOptions?.historyQuery !== undefined) {
            // Only an actual official login landing rejects the session. A
            // transport timeout alone must never create a verification storm.
            const previous: string = this.cookiesFor(service)
            if (previous) this.rejectedSessions.set(service, new RejectedCampusSession(previous))
            throw this.verificationFailure(service, true, e as Error)
          }
          return ''
        }
        if (e instanceof HttpError && e.isNetworkFailure() && !e.authenticationRecovery &&
          this.credentialFailure !== e && [0, 2300005, 2300006, 2300007, 2300028, 2300052, 2300055, 2300056, 2300999].includes(e.code)) {
          this.silentRetryAfter.set(key, Date.now() + 5000)
        }
        this.silentErrors.set(key, e as Error)
        throw e as Error
      }
    })
    this.silentFlights.set(key, task)
    this.authQueue = task.then(() => {}, () => {})
    try { return await task } finally { if (this.silentFlights.get(key) === task) this.silentFlights.delete(key) }
  }

  /** Called only after the protected SSO read reached an official login page.
   * The shared auth queue and account-wide cooldown bound password submissions
   * across sibling services. This path never presents Web UI or replays writes. */
  private async recoverWithCredential(login: FduLogin, service: string,
    epoch: number, authEpoch: number): Promise<FduSession | null> {
    const key = this.verificationKey(service)
    const previous = this.recoveryDiagnostics.get(key) ?? ''
    if (this.credentialBlocked || Date.now() < this.credentialRetryAfter) {
      this.recoveryDiagnostics.set(key, previous + '\ncredentialRecovery=account-backoff')
      // A sibling's password-renewal transport/protocol failure is still that
      // exact failure, not proof that this service now requires user MFA.
      if (this.credentialFailure !== null) throw this.credentialFailure
      return null
    }
    const owner = this.credentialId
    const password = this.credentialPw || await CampusCredentialStore.load(owner)
    this.requireAuthentication(epoch, authEpoch)
    if (!password) {
      this.recoveryDiagnostics.set(key, previous + '\ncredentialRecovery=unavailable; ' + CampusCredentialStore.diagnostics())
      return null
    }
    this.credentialRetryAfter = Date.now() + 300000
    this.credentialFailure = null
    this.recoveryDiagnostics.set(key, previous + '\ncredentialRecovery=attempt; candidate=true')
    try {
      const result = await login.login(service, owner, password)
      this.requireAuthentication(epoch, authEpoch)
      const renewed = result.serviceCookies ? result : await login.resume(service, result.targetUrl)
      this.requireAuthentication(epoch, authEpoch)
      this.recoveryDiagnostics.set(key, previous + '\ncredentialRecovery=completed')
      return renewed
    } catch (e) {
      this.requireAuthentication(epoch, authEpoch)
      if (e instanceof FduLoginError) {
        e.diagnostics = previous + '\ncredentialRecovery=failed; failure=' + String(e.failure) +
          (e.diagnostics ? '\n' + e.diagnostics : '')
        this.recoveryDiagnostics.set(key, e.diagnostics)
        if (e.failure === FduLoginFailure.CREDENTIALS_INVALID || e.failure === FduLoginFailure.ACCOUNT_ACTION_REQUIRED) {
          this.credentialBlocked = true
          this.credentialPw = ''
          // Captcha, rate limits and temporary account actions do not prove
          // that the saved password is invalid. Stop automatic submissions,
          // but retain its OS item for a later explicit verification.
          if (e.failure === FduLoginFailure.CREDENTIALS_INVALID) CampusCredentialStore.clear().catch(() => {})
        }
        if (e.failure === FduLoginFailure.ENHANCED_AUTH_REQUIRED || e.failure === FduLoginFailure.CAPTCHA_REQUIRED) return null
      }
      this.credentialFailure = e as Error
      throw e as Error
    }
  }

  private verificationFailure(service: string, expired: boolean, source?: Error): HttpError {
    const error = new HttpError(-2, 0, this.verificationMessage(service, expired), '')
    const sourceDetails = source instanceof FduLoginError || source instanceof HttpError ? source.diagnostics : ''
    const recoveryDetails = this.recoveryDiagnostics.get(this.verificationKey(service)) ?? ''
    error.diagnostics = recoveryDetails + (sourceDetails && sourceDetails !== recoveryDetails ? '\n' + sourceDetails : '')
    return error
  }

  /** Called only after a completed history upload stalled before response
   * headers. Reuse a newer local cookie first; otherwise check/redeem shared
   * portal SSO once, without password submission, navigation or cookie reset. */
  async recoverDormHistorySession(failedCookies: string, query: DormHistoryQuery): Promise<string> {
    const epoch: number = this.sessionEpoch
    const current: string = await CampusCookies.read(CampusService.cookieUrl(CampusService.MY_FUDAN))
    if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
    if (current && current !== failedCookies) return current
    const options: CampusSsoReadOptions = {
      timeoutMs: 5000, freshConnection: true, fallbackCookies: failedCookies,
      historyQuery: { id: query.id, attempt: query.attempt, stage: 'portal-session' }
    }
    const recovered: string = await this.resumeService(CampusService.MY_FUDAN, true, options, false)
    if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
    return recovered || current || failedCookies
  }

  async withService<T>(service: string, action: (cookies: string) => Promise<T>,
    renewOnUnauthorized: boolean = true, deadline?: number, renewOnVerification: boolean = false): Promise<T> {
    const epoch = this.sessionEpoch
    let cookies = await this.ensureSession(service, deadline, renewOnUnauthorized || renewOnVerification)
    if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
    try {
      const result = await action(cookies)
      if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
      return result
    } catch (e) {
      // Only renew an actually rejected session, never turn a genuine HTTP 500
      // or a parser failure into an endless sequence of verification windows.
      if (epoch !== this.sessionEpoch || !(e instanceof HttpError) || e.authenticationRecovery ||
        (e.statusCode !== -2 && (e.statusCode !== 401 || !renewOnUnauthorized))) throw e as Error
      let rejection: HttpError = e as HttpError
      // A concurrent browser completion may have rotated this path's cookies.
      // Retry only a read with a genuinely different local session, never open
      // verification or replay mutations from a response handler.
      const current = await CampusCookies.read(CampusService.cookieUrl(service))
      if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
      // Forum HTTP 401 belongs to JWT refresh, while -2 is a VPN login
      // redirect. Allow safe reads to recover the latter independently.
      const recoverRead: boolean = renewOnUnauthorized || (renewOnVerification && e.statusCode === -2)
      if (current && current !== cookies && recoverRead) {
        cookies = current
        this.serviceSessions.set(CampusService.sessionKey(service), current)
        try {
          const result = await action(current)
          if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
          this.rejectedSessions.delete(service)
          return result
        } catch (retryError) {
          if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
          if (!(retryError instanceof HttpError) || retryError.authenticationRecovery || (retryError.statusCode !== -2 && retryError.statusCode !== 401) ||
            (retryError.statusCode === 401 && !renewOnUnauthorized)) throw retryError as Error
          rejection = retryError as HttpError
          if (this.cookiesFor(service) === current) this.rejectedSessions.set(service, new RejectedCampusSession(current))
          // A rotated auxiliary/session Cookie can still be unauthenticated.
          // Continue this safe read through the one existing SSO repair below.
        }
      }
      // Keep sibling sessions and newer completions intact. Repeated lifecycle
      // reads now return locally during backoff instead of making login storms.
      if (this.cookiesFor(service) === cookies) this.rejectedSessions.set(service, new RejectedCampusSession(cookies))
      // A read may redeem existing ID/CAS SSO, then use a protected credential
      // once if ID explicitly requires login. No navigation occurs. Success permits one read retry;
      // mutations pass false and never enter this path.
      if (recoverRead) {
        const resumed = await this.resumeBefore(service, deadline)
        if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
        if (resumed) {
          try {
            const result = await action(resumed)
            if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
            return result
          }
          catch (retryError) {
            if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
            if (!(retryError instanceof HttpError) || retryError.authenticationRecovery || (retryError.statusCode !== -2 && retryError.statusCode !== 401) ||
            (retryError.statusCode === 401 && !renewOnUnauthorized)) throw retryError as Error
            rejection = retryError as HttpError
            if (this.cookiesFor(service) === resumed) this.rejectedSessions.set(service, new RejectedCampusSession(resumed))
            this.silentRetryAfter.set(this.verificationKey(service), Date.now() + 300000)
          }
        }
      }
      const failure = this.verificationFailure(service, true, rejection as Error)
      if (rejection !== e) {
        failure.diagnostics = 'Latest request rejection (status=' + String(rejection.statusCode) + '; code=' + String(rejection.code) + ')\n' +
          failure.diagnostics + '\nInitial request rejection (status=' + String(e.statusCode) + '; code=' + String(e.code) + ')\n' + e.diagnostics
      }
      throw failure
    }
  }

  /**
   * Cookies for a service previously logged in against, or '' if none.
   *
   * Empty is the honest answer for "not logged in to this service", and callers
   * must treat it as an error rather than sending a request that will be
   * answered with a login page.
   */
  cookiesFor(service: string): string {
    const found: string | undefined = this.serviceSessions.get(CampusService.sessionKey(service))
    return found === undefined ? '' : found
  }

  /** Local-only lookup. Refresh, theme changes and navigation never open login. */
  private async resumeBefore(service: string, deadline?: number, recoverCredentials: boolean = true): Promise<string> {
    if (deadline === undefined) return this.resumeService(service, false, undefined, recoverCredentials)
    const timeoutMs: number = DormRequestPolicy.remaining(deadline)
    if (timeoutMs <= 0) throw new HttpError(-1, 2300028,
      '寝室电费读取超时，请稍后重新加载。 Operation timeout (phase=dorm-budget; totalBudgetMs=60000)', '', 'dorm-budget')
    return this.resumeService(service, false, { timeoutMs, freshConnection: false, fallbackCookies: '' }, recoverCredentials)
  }

  async ensureSession(service: string, deadline?: number, recoverCredentials: boolean = true): Promise<string> {
    if (this.credentialId.length === 0 && !this.cookiesFor(service)) {
      throw new HttpError(-2, 0,
        '请先登录复旦账号，再查询校园服务。茶楼账号与校园账号分别登录。', '')
    }
    const epoch = this.sessionEpoch
    const browser = await CampusCookies.read(CampusService.cookieUrl(service))
    if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
    const snapshot = this.cookiesFor(service)
    const profileService = CampusService.sessionKey(service) === CampusService.sessionKey(CampusService.EHALL)
    // Ehall issues SESS_ID even for its public home shell. Only an existing
    // profile-verified snapshot can be reused locally; a changed browser cookie
    // must pass the protected callback and real profile check before adoption.
    if (browser && !profileService) this.serviceSessions.set(CampusService.sessionKey(service), browser)
    if (profileService && snapshot && browser && browser !== snapshot) {
      this.rejectedSessions.set(service, new RejectedCampusSession(snapshot))
    }
    const existing = profileService ? snapshot : browser || snapshot
    const rejected = this.rejectionFor(service, existing)
    if (rejected !== undefined) {
      // Do not resend a known rejected cookie when the short lifecycle backoff
      // expires. Shared SSO can repair it once; unsuccessful SSO has its own
      // five-minute cooldown and explicit verification always bypasses it.
      const repaired = await this.resumeBefore(service, deadline, recoverCredentials)
      if (repaired) return repaired
      throw this.verificationFailure(service, true)
    }
    if (existing) return existing
    const resumed = await this.resumeBefore(service, deadline, recoverCredentials)
    if (resumed) return resumed
    throw this.verificationFailure(service, false)
  }

  private verificationMessage(service: string, expired: boolean): string {
    if (CampusService.sessionKey(service) === 'https://webvpn.fudan.edu.cn') {
      return expired ? '校园 WebVPN 会话已失效，请点击继续验证，验证后继续原来的操作。' :
        '需要先完成校园 WebVPN 身份验证，请点击继续验证，验证后继续原来的操作。'
    }
    return expired ? '该校园服务会话已失效，请点击继续验证。已登录的其它服务会保留。' :
      '校园账号已登录，该服务仍需在官方页面确认身份，请点击继续验证。'
  }

  /**
   * Drop every session and the retained credentials.
   *
   * Call on logout. Invalidate in-flight secure reads/writes synchronously,
   * then remove the account's OS-protected credential without touching siblings.
   */
  forgetCredentials(): void {
    this.sessionEpoch++
    this.authenticationEpoch++
    this.classroomDirectRetryAfter = 0
    ClassroomRepository.invalidate()
    FduWebAuth.reset()
    JwglRepository.getInstance().forgetSession()
    CardRepository.getInstance().setSession('')
    ZlappRepository.getInstance().forgetSession()
    this.credentialId = ''
    this.credentialPw = ''
    CampusCredentialStore.clear().catch(() => {})
    this.campusCookies = ''
    this.serviceSessions.clear()
    this.authFlights.clear()
    this.silentFlights.clear()
    this.silentRetryAfter.clear()
    this.silentErrors.clear()
    this.recoveryDiagnostics.clear()
    this.credentialRetryAfter = 0
    this.credentialBlocked = false
    this.credentialFailure = null
    this.rejectedSessions.clear()
    this.graduateVerificationService = GraduateRepository.TIMETABLE_HOSTS[0] + GraduateRepository.TIMETABLE_PATH
    this.saveSessions().catch(() => {})
  }

  /** A known campus account can use memory credentials or continue browser SSO. */
  canLoginOnDemand(): boolean {
    return this.credentialId.length > 0
  }

  /** Cookies for the current campus session, or '' when logged out. */
  sessionCookies(): string {
    return this.campusCookies
  }

  // ───────────────────────── 教务处通知（真实数据） ─────────────────────────
  //
  // jwc.fudan.edu.cn is the ONE campus data source that needs no login: its
  // notice lists are plain public HTML. Every other Fudan host we probed
  // either redirects to id.fudan.edu.cn (zlapp bus / dorm, my.fudan, ehall)
  // or is unreachable, and the whole fduhole.com family is DNS-sinkholed on
  // some campus networks. So this is the only campus feature that can be
  // verified end to end, and it is wired to the live site rather than mocked.
  //
  // Ported from lib/repository/fdu/aao_repository.dart, which walks
  // `.wp_article_list_table > tbody > tr > td > table > tbody` with
  // BeautifulSoup. The markup is shallow enough that a regex over the raw
  // HTML replaces the whole HTML-parser dependency: every notice is exactly
  // one `<td align="left"><a href title>` cell followed by one
  // `<td class="ti">` date cell.
  //
  // Verified against the live site on 2026-09-29 (14 rows from 9397, 5 from
  // 9385, 14 from 9396, 7 from 9388).

  /** Notice-list columns, as site column ids. All verified live. */
  static readonly AAO_COLUMN_WORK_NEWS: string = '9397'   // 工作动态
  static readonly AAO_COLUMN_TEACHING: string = '9385'    // 教学运行
  static readonly AAO_COLUMN_GUIDE: string = '9396'       // 办事指南
  static readonly AAO_COLUMN_REGULATION: string = '9388'  // 规章制度

  private static readonly AAO_HOST: string = 'https://jwc.fudan.edu.cn'

  /**
   * One notice row: anchor cell (href + title) then date cell.
   *
   * `.` is spelled `[\s\S]` on purpose — ArkTS RegExp has no dotAll flag, so
   * the upstream `(?s)` form would not compile here.
   */
  private static readonly AAO_ITEM_PATTERN: string =
    '<td[^>]*align="left"[^>]*>\\s*<a\\s+href=\'([^\']+)\'[^>]*title=\'([^\']*)\'[^>]*>' +
    '[\\s\\S]*?</td>\\s*<td[^>]*class="ti"[^>]*>\\s*([0-9]{4}-[0-9]{2}-[0-9]{2})'

  private static readonly AAO_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

  /** Page 1 is `list.htm`; later pages are `list2.htm`, `list3.htm`, ... */
  static aaoListUrl(column: string, page: number): string {
    const suffix: string = page <= 1 ? '' : String(page)
    return FduRepository.AAO_HOST + '/' + column + '/list' + suffix + '.htm'
  }

  private static aaoCategoryName(column: string): string {
    if (column === FduRepository.AAO_COLUMN_TEACHING) return '教学运行'
    if (column === FduRepository.AAO_COLUMN_GUIDE) return '办事指南'
    if (column === FduRepository.AAO_COLUMN_REGULATION) return '规章制度'
    return '工作动态'
  }

  /** The site writes a few entities into titles; unescape the common ones. */
  private static unescapeHtml(text: string): string {
    return text
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, '\'')
      .replace(/&nbsp;/g, ' ')
  }

  private static parseAaoNotices(html: string, category: string): Announcement[] {
    const notices: Announcement[] = []
    const pattern = new RegExp(FduRepository.AAO_ITEM_PATTERN, 'g')
    let match: RegExpExecArray | null = pattern.exec(html)
    while (match !== null) {
      const href: string = match[1]
      const title: string = FduRepository.unescapeHtml(match[2]).trim()
      const date: string = match[3]
      // Skip the header/placeholder row that has an anchor but no title.
      if (title.length > 0 && href.length > 0) {
        // Article URLs look like `/17/6d/c25325a792429/page.htm`; the
        // `c<col>a<id>` token is the stable identity across the site.
        let id: string = href
        const idMatch = /c[0-9]+a[0-9]+/.exec(href)
        if (idMatch !== null) {
          id = idMatch[0]
        }
        const item: Announcement = {
          id: id,
          title: title,
          source: '复旦大学教务处',
          // The list page carries no body text; the detail view is the
          // article URL. Left empty rather than invented.
          content: '',
          publishTime: date,
          url: href.indexOf('http') === 0 ? href : FduRepository.AAO_HOST + href,
          category: category,
        }
        notices.push(item)
      }
      match = pattern.exec(html)
    }
    return notices
  }

  /**
   * Fetch real AAO notices for a column.
   *
   * Throws HttpError on transport failure so the caller can distinguish "the
   * campus network is down" from "no notices today" — the previous version
   * always returned three hardcoded fake notices, so a dead network was
   * indistinguishable from success.
   */
  async getAnnouncements(
    column: string = FduRepository.AAO_COLUMN_WORK_NEWS,
    page: number = 1
  ): Promise<Announcement[]> {
    return (await this.getAnnouncementPage(column, page)).rows
  }

  static aaoHasMore(html: string, column: string, page: number): boolean {
    let last: number = 0
    const total: RegExpMatchArray | null = html.match(/class=["'][^"']*all_pages[^"']*["'][^>]*>\s*(\d+)/i)
    if (total !== null) last = Number(total[1])
    const links: RegExp = new RegExp('/' + column + '/list(\\d*)\\.htm', 'g')
    let match: RegExpExecArray | null = links.exec(html)
    while (match !== null) {
      last = Math.max(last, match[1].length > 0 ? Number(match[1]) : 1)
      match = links.exec(html)
    }
    // Some list templates omit the pager. Let deduplication stop a repeated
    // page, rather than declaring the first successful page to be the end.
    return last === 0 || page < last
  }

  async getAnnouncementPage(column: string = FduRepository.AAO_COLUMN_WORK_NEWS, page: number = 1): Promise<AaoNoticePage> {
    const url: string = FduRepository.aaoListUrl(column, page)
    const headers: Record<string, string> = {
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      // The school site does not care for the app's Danta UA; present a browser.
      'User-Agent': FduRepository.AAO_UA,
    }
    const response = await this.httpUtil.get(url, undefined, headers)
    if (response.data.indexOf('Under Maintenance') >= 0) {
      throw new HttpError(200, 0, '教务处网站正在维护，请稍后重试', response.data)
    }
    const category: string = FduRepository.aaoCategoryName(column)
    const notices: Announcement[] = FduRepository.parseAaoNotices(response.data, category)
    if (notices.length === 0) {
      // A 200 with nothing parsed means the site changed its markup, which we
      // must not silently render as "no announcements".
      throw new HttpError(200, 0, '教务处页面结构已变化，暂时无法解析通知列表', response.data)
    }
    const result: AaoNoticePage = new AaoNoticePage()
    result.rows = notices
    result.hasMore = FduRepository.aaoHasMore(response.data, column, page)
    return result
  }

  // ─────────────────── 需登录的校园服务（已接入实测服务串，绝不伪造） ───────────────────
  //
  // These used to return invented data: a fake 3.72 GPA, fake exam seats and
  // dates, fake bus departure times with fake remaining-seat counts. Rendered
  // in the app they were indistinguishable from the real thing, so a student
  // could read a fabricated GPA or turn up for a bus that never runs. Failing
  // loudly was the only correct behaviour until the data was really wired.
  //
  // It is wired now. The reason it could not be wired before was that a CAS
  // ticket is bound to exactly one service: holding a session for
  // my.fudan.edu.cn does not open fdjwgl.fudan.edu.cn, and the service string is
  // not guessable — it is the `service` parameter the target host writes into its
  // own redirect. Every string below is now MEASURED, not inferred: each was read
  // hop by hop off the live redirect chain (redirects disabled) and is recorded
  // with its evidence in common/CampusService.ets. This block previously listed
  // bus/dorm and timetable/exam as "service string still unmeasured"; that was
  // true when written and had been stale ever since CampusService was created.
  //
  //   - my.fudan.edu.cn  https://my.fudan.edu.cn/simple_list/stqk   (UIS_SERVICE)
  //   - ecard            https://ecard.fudan.edu.cn/epay/j_spring_cas_security_check
  //                      (see CardRepository.SERVICE, which is wired)
  //   - bus / dorm       zlapp.fudan.edu.cn  (CampusService.BUS / .DORM; the real
  //                      target rides in the wrapper's `redirect=` and a direct
  //                      CAS request for /fudanbus/wap/default/lists is refused)
  //   - timetable        fdjwgl.fudan.edu.cn/student/sso/login?refer=…course-table
  //                      (CampusService.TIMETABLE)
  //   - exam             fdjwgl.fudan.edu.cn/student/sso/login?refer=…exam-arrange
  //                      (CampusService.EXAM — a different ticket from timetable,
  //                      because the target rides in `refer=` and CAS signs the
  //                      whole URL)
  //   - GPA / grades     fdjwgl.fudan.edu.cn/student/sso/login?refer=…grade/my-gpa
  //                      (CampusService.GPA)
  //
  // Empty classrooms use the campus LAN first, then the upstream WebVPN route.
  // The following sources remain unavailable in the port:
  //   - library seats    mlibrary.fudan.edu.cn -> HTTP 500
  //   - data centre      my.fudan.edu.cn/data_tables/*.json -> answers 404; the
  //                      upstream integration is dead and nothing may be built on it
  //
  // A previous revision of this block also claimed that id.fudan.edu.cn "stops
  // at /idp/authn/queryAuthMethods, which answers {"code":"500"} to every request
  // shape". That was wrong, and login() says so at length: the endpoint needs
  // `lck`, which only arrives on a redirect hop. The claim is called out here
  // because it sat directly above code that cited it as the reason those
  // features could never work.
  //
  // What is verified where: the PARSERS are faithful ports of the upstream Dart
  // and are unit-tested against fixtures taken from upstream's own documented
  // payloads. The LIVE responses have not been observed, because that needs a
  // real Fudan ID session. So nothing below may be described as "verified against
  // the live service" until someone runs it with an account — and a shape change
  // upstream surfaces as a thrown error, not as an empty card.

  /**
   * Refusal for a feature that has no reachable data source at all.
   *
   * Distinct from the session errors: those mean "log in and it will work",
   * this means "no login will ever help".
   */
  private static unreachableError(feature: string, why: string): HttpError {
    return new HttpError(0, 0, feature + '无法获取：' + why, '')
  }

  /**
   * Get bus schedules.
   *
   * Upstream lib/repository/fdu/bus_repository.dart: POST multipart to
   * zlapp.fudan.edu.cn/fudanbus/wap/default/lists, one field `holiday`, JSON
   * back. The timetable contains no remaining-seat figure (the old signature
   * took a `line` filter that upstream has no counterpart for, and the old card
   * rendered seat counts the endpoint never returned).
   *
   * `holiday` selects the weekend/holiday timetable. Upstream derives it from
   * the weekday (lib/feature/bus_feature.dart:57-60) and the dashboard offers
   * both variants; the caller passes it so this stays testable.
   */
  async getBusSchedules(holiday: boolean = false): Promise<BusSchedule[]> {
    return this.withService(CampusService.BUS, async (cookies: string) => {
      const repository = ZlappRepository.getInstance()
      repository.setSession(cookies)
      return repository.getBusSchedules(holiday)
    })
  }

  /**
   * Get dorm electricity for the logged-in account.
   *
   * Upstream lib/repository/fdu/dorm_repository.dart: GET
   * zlapp.fudan.edu.cn/fudanelec/wap/default/info with no parameters — the
   * server picks the room from the session.
   */
  private dormReadFlight: Promise<ElectricityInfo> | null = null
  private dormReadEpoch: number = -1
  private dormRepairEpoch: number = -1
  private dormRepairRetryAfter: number = 0

  async getDormElectricity(force: boolean = false): Promise<ElectricityInfo> {
    const epoch: number = this.sessionEpoch
    if (this.dormReadFlight !== null && this.dormReadEpoch === epoch) return this.dormReadFlight
    const task: Promise<ElectricityInfo> = this.readDormElectricity(force, epoch)
    this.dormReadFlight = task; this.dormReadEpoch = epoch
    try { return await task } finally { if (this.dormReadFlight === task) this.dormReadFlight = null }
  }

  private async readDormElectricity(force: boolean, epoch: number): Promise<ElectricityInfo> {
    const deadline: number = Date.now() + DormRequestPolicy.WAIT_MS
    const repository = ZlappRepository.getInstance()
    const serial: number = repository.dormSsoSerial()
    // An explicit retry can bypass a transport failure's local cooldown; it
    // must not bypass a real authentication challenge or launch a browser.
    const key: string = this.verificationKey(CampusService.DORM)
    const previous = this.silentErrors.get(key)
    if (force && previous instanceof HttpError && previous.code === 2300028 &&
      previous.statusCode === -1 && !this.silentFlights.has(key)) {
      this.silentErrors.delete(key); this.silentRetryAfter.delete(key)
    }
    try {
      return await this.withService(CampusService.DORM, async (cookies: string) => {
        repository.setSession(cookies)
        return repository.getDormElectricity(force, DormRequestPolicy.remaining(deadline), serial)
      }, true, deadline)
    } catch (error) {
      // Match upstream's failed-read continuation without its broad re-login:
      // only timeout GETs or unexpected HTML from the JSON endpoint may try
      // existing ID SSO once. Plain format errors/HTTP 500 never renew login.
      // A renewed service must prove actual JSON data before being accepted.
      const recoverable: boolean = error instanceof HttpError && error.code === 2300028 && error.statusCode === -1 &&
        error.transportPhase !== 'dorm-sso' ||
        error instanceof ZlappDataFormatError && error.isHtml
      if (epoch !== this.sessionEpoch || !recoverable ||
        !await CampusCookies.hasIdSession() || epoch !== this.sessionEpoch) throw error as Error
      const remaining: number = DormRequestPolicy.remaining(deadline)
      if (remaining <= 0) throw error as Error
      if (this.dormRepairEpoch === epoch && Date.now() < this.dormRepairRetryAfter) throw error as Error
      this.dormRepairEpoch = epoch; this.dormRepairRetryAfter = Date.now() + 300000
      let cookies: string
      try {
        cookies = await this.resumeService(CampusService.DORM, true, {
          timeoutMs: remaining, freshConnection: true, fallbackCookies: ''
        })
      } catch (recoveryError) {
        // Unexpected HTML at a JSON endpoint is not evidence of expired ID.
        // Keep the original concrete read failure and attach the failed proof.
        if (error instanceof ZlappDataFormatError && recoveryError instanceof FduLoginError &&
          recoveryError.failure === FduLoginFailure.PROTOCOL_ERROR) {
          error.diagnostics = recoveryError.diagnostics
          throw error
        }
        throw recoveryError as Error
      }
      if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
      if (!cookies) throw error as Error
      repository.setSession(cookies)
      const result: ElectricityInfo = await repository.getDormElectricity(true, DormRequestPolicy.remaining(deadline), serial)
      if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
      return result
    }
  }

  /**
   * Get empty classrooms.
   *
   * Follow upstream's direct-campus route, falling back to authenticated WebVPN.
   */
  async getEmptyClassrooms(building: string = 'HGD', campus: string = '邯郸',
    forceRefresh: boolean = false, selectedDay: string = ''): Promise<EmptyClassroom[]> {
    const epoch: number = this.sessionEpoch
    const day: string = ClassroomRepository.dayString(selectedDay)
    const useWebVpn: boolean = AppStorage.get<boolean>(Constant.KEY_USE_WEBVPN) !== false
    const context: string = this.credentialId + '\n' + String(epoch) + '\n' + this.campusCookies + '\n' +
      String(CampusCookies.generation()) + '\n' + String(useWebVpn)
    return ClassroomRepository.cached(building, day, context, forceRefresh, async (): Promise<EmptyClassroom[]> => {
      if (!useWebVpn || Date.now() >= this.classroomDirectRetryAfter) {
        try {
          const direct: EmptyClassroom[] = await ClassroomRepository.load(building, '', day)
          if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
          this.classroomDirectRetryAfter = 0
          return direct
        } catch (e) {
          if (epoch !== this.sessionEpoch || !useWebVpn) throw e as Error
          // Parser errors must not label a reachable LAN as unavailable.
          if (e instanceof HttpError && e.isNetworkFailure()) this.classroomDirectRetryAfter = Date.now() + 30000
        }
      }
      if (epoch !== this.sessionEpoch) throw new Error('校园账号已切换，请重新加载')
      return this.withService(ClassroomRepository.LOGIN_URL,
        async (cookies: string): Promise<EmptyClassroom[]> => ClassroomRepository.load(building, cookies, day))
    })
  }

  /**
   * Get exam schedules.
   *
   * Upstream lib/repository/fdu/edu_service_repository.dart: the internal
   * student id comes from print-data, then the exam-arrange page is parsed.
   */
  async getExamSchedules(): Promise<ExamSchedule[]> {
    AcademicAccount.requireSelection()
    if (AcademicAccount.isGraduate()) throw new Error('研究生请查看课程成绩；原版研究生系统不提供本科生考试安排')
    return this.withService(CampusService.EXAM, async (cookies: string) => {
      const repository = JwglRepository.getInstance()
      repository.setSession(cookies)
      return repository.getExamSchedules()
    })
  }

  /**
   * Get the department GPA / rank table.
   *
   * This replaced a `getGPASummary()` that returned a `GPASummary` interface
   * with a total credit count and a per-semester GPA map. The endpoint has never
   * returned any of that: it returns a ranking table, one row per major, and
   * upstream DanXi displays the server's own `gpa` string without recomputing
   * anything. Keep this ranking response unchanged. LocalGpa separately
   * calculates the supplied course list and clearly labels its limited scope.
   */
  async getGpaList(): Promise<GpaListItem[]> {
    AcademicAccount.requireSelection()
    if (AcademicAccount.isGraduate()) throw new Error('研究生请查看课程成绩与单科绩点；原版不提供本科生 GPA 排名')
    return this.withService(CampusService.GPA, async (cookies: string) => {
      const repository = JwglRepository.getInstance()
      repository.setSession(cookies)
      return repository.getGpaList()
    })
  }

  /**
   * Get course grades for the current semester.
   *
   * Same GPA service ticket: the grade sheet lives under the same `refer=` path.
   * (Still no caller — kept so the ported surface stays intact.)
   */
  async getCourseGrades(semesterId: string = ''): Promise<CourseGrade[]> {
    AcademicAccount.requireSelection()
    if (AcademicAccount.isGraduate()) return this.withService(GraduateRepository.SCORE_ENTRY,
      async (cookies: string) => GraduateRepository.scores(cookies))
    return this.withService(CampusService.GPA, async (cookies: string) => {
      const repository = JwglRepository.getInstance()
      repository.setSession(cookies)
      return repository.getCourseGrades(semesterId)
    })
  }

  /**
   * Get the timetable for a week.
   *
   * `week <= 0` means the current teaching week, derived from the semester's
   * start date. Upstream expands each activity into one entry per period; this
   * renderer draws a start–end range, so one entry per activity carries the same
   * information.
   */
  async getTimetable(week: number = 0): Promise<TimeTableEntry[]> {
    AcademicAccount.requireSelection()
    if (AcademicAccount.isGraduate()) return GraduateRepository.entries(await this.getGraduateCourses(), week)
    return this.withService(CampusService.TIMETABLE, async (cookies: string) => {
      const repository = JwglRepository.getInstance()
      repository.setSession(cookies)
      return repository.getTimetable(week)
    })
  }

  /**
   * Get the course activities of the current semester.
   *
   * Same timetable service ticket and the same print-data payload as
   * getTimetable(), unexpanded and unfiltered by week. (Still no caller — kept
   * so the ported surface stays intact.)
   */
  async getCourses(semesterId: string = ''): Promise<Course[]> {
    AcademicAccount.requireSelection()
    if (AcademicAccount.isGraduate()) return this.getGraduateCourses()
    return this.withService(CampusService.TIMETABLE, async (cookies: string) => {
      const repository = JwglRepository.getInstance()
      repository.setSession(cookies)
      return repository.getCourses(semesterId)
    })
  }
  /** The archived iOS date-based diary is used only for historical semesters;
   * it must not displace the current course-selection feed. */
  async getGraduateHistory(monday: string): Promise<Course[]> {
    AcademicAccount.requireSelection()
    if (!AcademicAccount.isGraduate()) throw new Error('GraduateHistoryAccountRequired')
    this.graduateVerificationService = GraduateRepository.HISTORY_ENTRY
    return this.withService(GraduateRepository.HISTORY_ENTRY,
      async (cookies: string) => GraduateRepository.history(monday, cookies))
  }
  async getSemesters(forceRefresh: boolean = false): Promise<SemesterInfo[]> {
    AcademicAccount.requireSelection()
    if (AcademicAccount.isGraduate()) return []
    return this.withService(CampusService.TIMETABLE, async (cookies: string) => {
      const repository = JwglRepository.getInstance()
      repository.setSession(cookies)
      return repository.getSemesters(forceRefresh)
    })
  }

  async getCurrentSemester(forceRefresh: boolean = false): Promise<SemesterInfo> {
    AcademicAccount.requireSelection()
    if (AcademicAccount.isGraduate()) throw new Error('研究生系统未提供本科教务学期列表，请查看全部课程成绩。')
    return this.withService(CampusService.TIMETABLE, async (cookies: string): Promise<SemesterInfo> => {
      const repository = JwglRepository.getInstance()
      repository.setSession(cookies)
      return repository.getCurrentSemester(forceRefresh)
    })
  }

  /** Upstream fallback when the undergraduate semester bundle cannot be obtained. */
  async getCourseGradesFromDataCenter(): Promise<CourseGrade[]> {
    AcademicAccount.requireSelection()
    if (AcademicAccount.isGraduate()) return this.getCourseGrades()
    return this.withService(CampusService.MY_FUDAN, async (cookies: string): Promise<CourseGrade[]> =>
      new DataCenterRepository().getCourseGrades(cookies))
  }
  private async getGraduateCourses(): Promise<Course[]> {
    let firstError: Error | undefined = undefined
    for (const host of GraduateRepository.TIMETABLE_HOSTS) {
      try {
        return await GraduateRepository.courses(host, this.cookiesFor(host))
      } catch (e) {
        if (e instanceof FduAuthCancelledError) throw e
        if (e instanceof HttpError && (e.statusCode === -2 || e.statusCode === 401)) {
          this.graduateVerificationService = host + GraduateRepository.TIMETABLE_PATH
          // /wsxk is a PUBLIC shell: it returns 200 + a cookie before login.
          // Upstream authenticates the protected data URL itself. Only this
          // request can establish that CAS completed for the timetable service.
          // Return the promise directly so a rejected verification cannot cause
          // another host's browser to open during the same user action.
          return this.withService(host + GraduateRepository.TIMETABLE_PATH,
            async (cookies: string) => GraduateRepository.courses(host, cookies))
        }
        // Fail over only for an unavailable endpoint, never a login/parser error.
        if (!(e instanceof HttpError) || (e.statusCode !== -1 && e.statusCode !== 404 && e.statusCode < 500)) throw e as Error
        if (firstError === undefined || (firstError instanceof HttpError && firstError.statusCode === -1)) firstError = e as Error
      }
    }
    throw firstError ?? new Error('研究生课表暂不可用')
  }

}
