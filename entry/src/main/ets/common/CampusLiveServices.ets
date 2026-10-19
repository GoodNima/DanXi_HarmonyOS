import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { CampusPreviewItem } from '../model/CampusPreviewItem'
import { CampusSignal } from './CampusSignal'
import { DiningPresentation } from './DiningPresentation'
import { AppState } from './AppState'
import { AppLanguage } from './AppLanguage'
import { CampusCookies } from './CampusCookies'
import { CampusPreference } from './CampusPreference'
import { CampusService } from './CampusService'
import { AnnouncementConfig } from './AnnouncementConfig'
import { DeveloperNotice } from '../model/AnnouncementConfigData'
import { CampusLiveData, CampusLiveSummary, DiningSnapshot, DiningOutsideMealTime, DiningTraffic } from '../model/CampusLiveData'
import { CampusLiveRepository } from '../repository/CampusLiveRepository'
import { FduRepository } from '../repository/FduRepository'
import { HttpError } from '../util/HttpUtil'

export interface CampusLiveSource {
  detail(feature: string, force: boolean, campus: string): Promise<CampusLiveData>
  history?(force: boolean, campus: string): Promise<CampusLiveData>
  owner(): string
}

export class DefaultCampusLiveSource implements CampusLiveSource {
  detail(feature: string, force: boolean, campus: string): Promise<CampusLiveData> {
    return feature === 'electricity' ? CampusLiveServices.currentElectricity(force, campus) : CampusLiveServices.detail(feature, force, campus)
  }
  history(force: boolean, campus: string): Promise<CampusLiveData> { return CampusLiveServices.detail('electricity', force, campus) }
  owner(): string { return CampusLiveServices.owner() }
}

/** Only classified transport/service errors enter the outage cooldown. */
class DiningReadFailure {
  error: HttpError
  retryAt: number
  constructor(error: HttpError, retryAt: number) { this.error = error; this.retryAt = retryAt }
}

class DiningReadState {
  version: number = 0
  settledVersion: number = 0
  snapshot: DiningSnapshot | null = null
  error: Error | null = null
}

/** Shared read-only snapshots. Home previews never open a new authentication page. */
export class CampusLiveServices {
  // The upstream build limit refers to Flutter's build space, not Harmony's
  // versionCode. This compatibility baseline is pinned pubspec 1.5.3+350.
  static readonly UPSTREAM_REFERENCE_BUILD: number = 350
  static readonly REVISION: string = 'campus_live_services_revision'
  private static readonly cache: Map<string, CampusLiveData> = new Map<string, CampusLiveData>()
  private static readonly flights: Map<string, Promise<CampusLiveData>> = new Map<string, Promise<CampusLiveData>>()
  private static readonly diningSnapshots: Map<string, DiningSnapshot> = new Map<string, DiningSnapshot>()
  private static readonly diningFlights: Map<string, Promise<DiningSnapshot>> = new Map<string, Promise<DiningSnapshot>>()
  private static readonly diningFailures: Map<string, DiningReadFailure> = new Map<string, DiningReadFailure>()
  private static readonly diningReadStates: Map<string, DiningReadState> = new Map<string, DiningReadState>()

  static owner(): string {
    return String(AppState.isLoggedIn()) + ':' + AppState.getPerson().getStudentId() + ':' + String(CampusCookies.generation())
  }
  static currentNotices(rows: DeveloperNotice[]): DeveloperNotice[] {
    return rows.filter((row: DeveloperNotice) => row.maxBuild >= CampusLiveServices.UPSTREAM_REFERENCE_BUILD)
  }
  static title(feature: string): Resource {
    if (feature === 'dining') return $r('app.string.live_dining_title')
    if (feature === 'library') return $r('app.string.live_library_title')
    if (feature === 'electricity') return $r('app.string.live_electricity_title')
    return $r('app.string.live_developer_title')
  }
  static describe(error: Object, revision: number = 0): string {
    if (error instanceof HttpError) return ErrorDiagnostics.message(error)
    if (error instanceof DiningOutsideMealTime) return AppLanguage.text($r('app.string.live_dining_outside'), revision)
    return ErrorDiagnostics.message(error, AppLanguage.text($r('app.string.live_load_error'), revision))
  }

  static async preview(feature: string, force: boolean = false): Promise<CampusLiveSummary> {
    const result = new CampusLiveSummary()
    const data = await CampusLiveServices.load(feature, force, CampusPreference.current(), false)
    const diningError: string = data.diningCampuses.find(item => item.campus === data.campus)?.error ?? ''
    if (feature === 'dining' && diningError) throw new Error(diningError)
    result.status = data.status; result.updatedAt = data.updatedAt
    if (data.status === 'pending') {
      result.value = AppLanguage.text($r('app.string.campus_preview_open'))
      result.description = AppLanguage.text($r('app.string.live_sign_in_hint'))
    } else if (data.status === 'outside') {
      result.value = AppLanguage.text($r('app.string.live_dining_outside'))
      result.description = AppLanguage.text($r('app.string.campus_dining_outside_hint'))
    } else if (feature === 'developer_notice') {
      const notices = CampusLiveServices.currentNotices(data.notices)
      result.value = notices[0]?.content.trim() ?? AppLanguage.text($r('app.string.live_no_notices'))
      result.description = notices.length > 0 ? AppLanguage.text($r('app.string.campus_notice_read_full')) : ''
      const date: string = CampusLiveServices.noticeDateLabel(notices[0]?.updatedAt ?? '').split(' ')[0]
      result.secondary = date ? AppLanguage.text($r('app.string.campus_notice_updated'), 0, date) : ''
      if (notices.length > 1) result.secondary += ' · ' + AppLanguage.text($r('app.string.campus_notice_more'), 0, notices.length - 1)
    } else if (feature === 'library') {
      const current: string = CampusPreference.current()
      const selected = data.libraries.find(item => current === '邯郸' ? /文科|理科|邯郸/.test(item.name) :
        current === '枫林' ? /医科|枫林/.test(item.name) : item.name.includes(current)) ?? data.libraries[0]
      result.value = selected?.visitors ?? AppLanguage.text($r('app.string.ui_no_data'))
      if (selected !== undefined) result.tone = CampusSignal.dining(Number(selected.visitors), selected.capacity)
      result.description = selected?.name ?? ''
      result.secondary = AppLanguage.text($r('app.string.live_visitors'))
      const libraries = selected === undefined ? [] : [selected].concat(data.libraries.filter(item => item !== selected))
      result.items = libraries.map(item => {
        const entry = new CampusPreviewItem(); entry.label = item.name; entry.value = item.visitors; entry.detail = item.openTime
        entry.tone = CampusSignal.dining(Number(item.visitors), item.capacity)
        return entry
      })
    } else if (feature === 'electricity' && data.electricity !== null) {
      result.tone = CampusSignal.amount(data.electricity.available)
      result.value = data.electricity.available
      result.description = AppLanguage.text($r('app.string.live_remaining_kwh'))
      result.secondary = data.electricity.dormName
    } else if (feature === 'dining') {
      CampusLiveServices.fillDiningSummary(result, data.dining)
    }
    return result
  }

  static fillDiningSummary(result: CampusLiveSummary, traffic: DiningTraffic[]): void {
    const sorted: DiningTraffic[] = DiningPresentation.ratios(traffic)
    const least: DiningTraffic | undefined = sorted[0]
    result.value = least?.name ?? AppLanguage.text($r('app.string.ui_no_data'))
    result.description = AppLanguage.text(least !== undefined ? $r('app.string.live_least_busy') :
      traffic.some((item: DiningTraffic): boolean => Number.isFinite(item.current) && item.current > 0) ?
        $r('app.string.dining_peak_missing') : $r('app.string.campus_dining_no_activity'))
    result.secondary = AppLanguage.campus(CampusPreference.current())
    result.items = []; result.tone = ''
    if (least === undefined) return
    result.tone = CampusSignal.dining(least.current, least.maximum)
    const most: DiningTraffic = sorted[sorted.length - 1]
    result.items = [least, most].map((item: DiningTraffic, index: number): CampusPreviewItem => {
      const row = new CampusPreviewItem()
      row.label = AppLanguage.text(index === 0 ? $r('app.string.live_least_busy') : $r('app.string.live_most_busy'))
      if (item.zone) row.label += ' · ' + item.zone
      row.value = DiningPresentation.windowName(item)
      row.detail = AppLanguage.text($r('app.string.campus_dining_peak_ratio'), 0, Math.round(item.ratio() * 100))
      row.tone = CampusSignal.dining(item.current, item.maximum)
      return row
    })
  }

  static detail(feature: string, force: boolean = false, campus: string = CampusPreference.current()): Promise<CampusLiveData> {
    return CampusLiveServices.load(feature, force, CampusPreference.normalize(campus), true)
  }

  static noticeDateLabel(value: string): string { return value.replace('T', ' ').replace(/(?:[+-]\d{2}:?\d{2}|Z)$/, '') }

  static currentElectricity(force: boolean, campus: string): Promise<CampusLiveData> {
    return CampusLiveServices.load('electricity', force, CampusPreference.normalize(campus), true, false)
  }

  static cachedElectricityPreview(): CampusLiveSummary | undefined {
    if (!AppState.isLoggedIn()) return undefined
    const key: string = 'electricity:' + CampusPreference.current() + ':' + CampusLiveServices.owner() + ':current'
    const data: CampusLiveData | undefined = CampusLiveServices.cache.get(key)
    if (data === undefined || data.electricity === null || data.status !== 'ready' ||
      data.updatedAt <= 0 || Date.now() - data.updatedAt >= 600000) return undefined
    const result = new CampusLiveSummary()
    result.value = data.electricity.available
    result.description = AppLanguage.text($r('app.string.live_remaining_kwh'))
    result.secondary = data.electricity.dormName
    result.tone = CampusSignal.amount(data.electricity.available)
    result.updatedAt = data.updatedAt
    return result
  }

  private static async load(feature: string, force: boolean, campus: string, authorized: boolean, includeHistory: boolean = true): Promise<CampusLiveData> {
    if (!['developer_notice', 'dining', 'library', 'electricity'].includes(feature)) throw new Error('Unknown campus live feature')
    // Passive home balance refreshes must not replace the separate history
    // snapshot with an empty array or evict its last successful records.
    if (feature === 'electricity' && !authorized) includeHistory = false
    const owner: string = CampusLiveServices.owner()
    const fdu: FduRepository = FduRepository.getInstance()
    // A verified detail is already the newest balance for this account.
    // Passive previews may reuse it without probing session readiness again.
    if (feature === 'electricity' && !force && !includeHistory) {
      const current: CampusLiveData | undefined = CampusLiveServices.cache.get('electricity:' + campus + ':' + owner + ':current')
      if (current !== undefined && current.electricity !== null && Date.now() - current.updatedAt < 600000) return current
    }
    const service: string = feature === 'electricity' ? CampusService.DORM : CampusService.MY_FUDAN
    const cookies: string = fdu.cookiesFor(service)
    // A protected home card is never the trigger for MFA. Opening its detail is.
    if (!authorized && (feature === 'dining' || feature === 'electricity') && (!AppState.isLoggedIn() || !cookies)) {
      const pending = new CampusLiveData(); pending.feature = feature; pending.campus = campus; pending.status = 'pending'; return pending
    }
    // Session cookie rotation is not a new account or new data. The logout
    // generation already separates owners and prevents private reuse.
    const key: string = feature + ':' + campus + ':' + (feature === 'developer_notice' || feature === 'library' ? 'public' : owner) + (includeHistory ? '' : ':current')
    const cached: CampusLiveData | undefined = CampusLiveServices.cache.get(key)
    if (!force && cached !== undefined && Date.now() - cached.updatedAt < (feature === 'electricity' ? 600000 : feature === 'library' ? 60000 : 300000) &&
      (!includeHistory || !authorized || feature !== 'electricity' ||
        (cached.historyError.length > 0 ? Date.now() - cached.updatedAt < 15000 :
          cached.historyUpdatedAt > 0 && Date.now() - cached.historyUpdatedAt < 600000))) return cached
    // A verification route can install a new service cookie while the original
    // read is still pending. Its returning page joins that account's flight.
    const flightKey: string = feature + ':' + campus + ':' + owner + ':' + String(authorized) + (includeHistory ? '' : ':current')
    const existing: Promise<CampusLiveData> | undefined = CampusLiveServices.flights.get(flightKey)
    if (existing !== undefined) return existing
    const task = CampusLiveServices.fetch(feature, campus, authorized, cookies, owner, force, includeHistory).then((data: CampusLiveData): CampusLiveData => {
      if (feature !== 'developer_notice' && feature !== 'library' && owner !== CampusLiveServices.owner()) throw new Error('Campus account changed')
      // Separate passive/detail reads can overlap. An older source result may
      // finish while the newer explicit read is still pending; let that caller
      // finish without publishing an obsolete campus projection or revision.
      const diningState = CampusLiveServices.diningReadStates.get(owner)
      if (feature === 'dining' && diningState !== undefined && data.diningReadVersion < diningState.version) return data
      CampusLiveServices.cache.set(key, data)
      while (CampusLiveServices.cache.size > 32) { const oldest: string | undefined = CampusLiveServices.cache.keys().next().value; if (oldest !== undefined) CampusLiveServices.cache.delete(oldest) }
      AppStorage.setOrCreate<number>(CampusLiveServices.REVISION, (AppStorage.get<number>(CampusLiveServices.REVISION) ?? 0) + 1)
      return data
    })
    CampusLiveServices.flights.set(flightKey, task)
    try { return await task } finally { if (CampusLiveServices.flights.get(flightKey) === task) CampusLiveServices.flights.delete(flightKey) }
  }

  private static async fetch(feature: string, campus: string, authorized: boolean, cookies: string, owner: string, force: boolean, includeHistory: boolean = true): Promise<CampusLiveData> {
    const data = new CampusLiveData(); data.feature = feature; data.campus = campus
    const repository = new CampusLiveRepository(); const fdu = FduRepository.getInstance()
    if (feature === 'developer_notice') {
      const snapshot = await AnnouncementConfig.load(force)
      if (snapshot.error && snapshot.cachedAt <= 0) throw new Error(snapshot.error)
      data.notices = snapshot.notices.slice(); data.updatedAt = snapshot.cachedAt
    } else if (feature === 'library') {
      data.libraries = await repository.library()
    } else if (feature === 'dining') {
      try {
        const snapshot = await CampusLiveServices.readDining(owner, cookies, authorized, force)
        const selected = snapshot.campuses.find(item => item.campus === campus)
        if (selected?.error && !authorized) throw new Error(selected.error)
        data.dining = selected?.traffic.slice() ?? []
        data.diningCampuses = snapshot.campuses
        data.status = snapshot.status; data.updatedAt = snapshot.updatedAt
        data.diningReadVersion = snapshot.readVersion
      } catch (e) { if (e instanceof DiningOutsideMealTime) data.status = 'outside'; else throw e as Error }
    } else if (feature === 'electricity') {
      if (authorized && includeHistory) {
        // Opening history reuses the balance already read by this account.
        // When cold, start independent balance/history reads together rather
        // than serializing two service handshakes before showing usage.
        const current = CampusLiveServices.cache.get('electricity:' + campus + ':' + owner + ':current')
        const balance: Promise<void> = current?.electricity !== null && current?.electricity !== undefined &&
          Date.now() - current.updatedAt < 600000 ? Promise.resolve().then(() => { data.electricity = current.electricity }) :
          fdu.getDormElectricity(false).then(value => { data.electricity = value })
        const history: Promise<void> = fdu.withService(CampusService.MY_FUDAN,
          (session: string) => repository.electricityHistory(session, 0, 30,
            (cookies, query) => fdu.recoverDormHistorySession(cookies, query))).then(rows => {
            data.history = rows; data.historyUpdatedAt = Date.now()
          }).catch((error: Object) => {
            // A failed refresh must not erase readable records, and must not
            // masquerade as a successful ten-minute cached history response.
            const previous = CampusLiveServices.cache.get('electricity:' + campus + ':' + owner)
            data.history = previous?.history ?? []; data.historyUpdatedAt = previous?.historyUpdatedAt ?? 0
            data.historyFailure = error; data.historyError = CampusLiveServices.describe(error)
          })
        await Promise.all([balance, history])
        if (owner !== CampusLiveServices.owner()) throw new Error('Campus account changed')
        data.updatedAt = Date.now()
        return data
      }
      // Home previews require an existing session before reaching this branch.
      // Share the account-scoped reader with details so stale service cookies
      // can resume through the existing ID jar without passwords or navigation.
      data.electricity = await fdu.getDormElectricity(force && !includeHistory)
      if (owner !== CampusLiveServices.owner()) throw new Error('Campus account changed')
      if (authorized && includeHistory) {
        try {
          data.history = await fdu.withService(CampusService.MY_FUDAN,
            (session: string) => repository.electricityHistory(session, 0, 30,
              (cookies, query) => fdu.recoverDormHistorySession(cookies, query)))
        } catch (e) { data.historyFailure = e as Object; data.historyError = CampusLiveServices.describe(e as Object) }
      }
    }
    if (data.updatedAt <= 0) data.updatedAt = Date.now()
    return data
  }

  /** The upstream document carries every campus, so switching campus must not
   * repeat SSO or download it four times. Private data stays in memory and is
   * bound to the existing account/logout epoch, just like the detail cache. */
  private static async readDining(owner: string, cookies: string, authorized: boolean, force: boolean): Promise<DiningSnapshot> {
    const cached = CampusLiveServices.diningSnapshots.get(owner)
    if (!force && cached !== undefined && Date.now() - cached.updatedAt < 300000) return cached
    // A passive preview cannot join a detail's authentication continuation.
    // Successful snapshots are shared; in-flight read semantics stay explicit.
    const key = owner + ':' + String(authorized)
    const existing = CampusLiveServices.diningFlights.get(key)
    if (existing !== undefined) return existing
    const failure = CampusLiveServices.diningFailures.get(key)
    if (!force && failure !== undefined && Date.now() < failure.retryAt) throw failure.error
    let state = CampusLiveServices.diningReadStates.get(owner)
    if (state === undefined) {
      state = new DiningReadState()
      CampusLiveServices.diningReadStates.set(owner, state)
      while (CampusLiveServices.diningReadStates.size > 4) {
        const oldest: string | undefined = CampusLiveServices.diningReadStates.keys().next().value
        if (oldest !== undefined) CampusLiveServices.diningReadStates.delete(oldest)
      }
    }
    const readState: DiningReadState = state
    const readVersion = ++readState.version
    const repository = new CampusLiveRepository()
    const task = (authorized ? FduRepository.getInstance().withService(CampusService.MY_FUDAN,
      (session: string): Promise<DiningSnapshot> => repository.diningSnapshot(session)) : repository.diningSnapshot(cookies))
      .then((snapshot: DiningSnapshot): DiningSnapshot => {
        if (owner !== CampusLiveServices.owner()) throw new Error('Campus account changed')
        snapshot.readVersion = readVersion
        // Reuse only a newer *completed* result. A passive read never waits for
        // or joins an authorized service's pending authentication continuation.
        if (readVersion < readState.settledVersion) {
          if (readState.snapshot !== null) return readState.snapshot
          if (readState.error !== null) throw readState.error
        }
        if (readVersion < readState.version) return snapshot
        readState.snapshot = snapshot; readState.error = null; readState.settledVersion = readVersion
        CampusLiveServices.diningSnapshots.set(owner, snapshot)
        // A manual refresh replaces the whole source document, including
        // campuses visited earlier. Drop old projections before publishing.
        CampusLiveServices.cache.forEach((value: CampusLiveData, cacheKey: string) => {
          if (value.feature === 'dining' && cacheKey.endsWith(':' + owner)) CampusLiveServices.cache.delete(cacheKey)
        })
        CampusLiveServices.diningFailures.delete(key)
        while (CampusLiveServices.diningSnapshots.size > 4) {
          const oldest: string | undefined = CampusLiveServices.diningSnapshots.keys().next().value
          if (oldest !== undefined) CampusLiveServices.diningSnapshots.delete(oldest)
        }
        return snapshot
      }).catch((error: Error): DiningSnapshot => {
        if (owner !== CampusLiveServices.owner()) throw error
        if (readVersion < readState.settledVersion) {
          if (readState.snapshot !== null) return readState.snapshot
          if (readState.error !== null) throw readState.error
        }
        if (readVersion < readState.version) throw error
        readState.snapshot = null; readState.error = error; readState.settledVersion = readVersion
        if (owner === CampusLiveServices.owner() && error instanceof HttpError &&
          (error.statusCode >= 500 || error.statusCode === 406 || error.statusCode === -1)) {
          CampusLiveServices.diningFailures.set(key, new DiningReadFailure(error, Date.now() + 30000))
          while (CampusLiveServices.diningFailures.size > 8) {
            const oldest: string | undefined = CampusLiveServices.diningFailures.keys().next().value
            if (oldest !== undefined) CampusLiveServices.diningFailures.delete(oldest)
          }
        }
        throw error
      })
    CampusLiveServices.diningFlights.set(key, task)
    try { return await task } finally {
      if (CampusLiveServices.diningFlights.get(key) === task) CampusLiveServices.diningFlights.delete(key)
    }
  }
}
