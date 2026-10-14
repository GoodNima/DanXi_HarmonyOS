/**
 * zlapp.fudan.edu.cn — 校车时刻 (bus) and 宿舍电费 (dorm electricity).
 *
 * ── What the upstream app actually does ──
 *
 * Successful responses are JSON; expired sessions can instead return HTML.
 * Neither data request needs a
 * `service=` / `refer=` / `redirect=` parameter: the identity comes from the
 * CAS session cookie alone. Upstream reaches them through one shared
 * `FudanSession` cookie jar for all of fudan.edu.cn
 * (lib/repository/fdu/neo_login_tool.dart:57-63), which is why a single login
 * against `CampusService.BUS` / `CampusService.DORM` is what opens them here.
 *
 * Bus requests are `multipart/form-data` with one field, `holiday` — upstream
 * builds a Dio `FormData` (bus_repository.dart:42-43), which is multipart by
 * default. The dorm request has no body and no parameters at all
 * (dorm_repository.dart:33-36).
 *
 * ── Honesty note ──
 *
 * The two PARSERS are faithful ports of the upstream Dart and are unit-tested
 * against the exact JSON shapes upstream documents. The LIVE response has not
 * been observed, because that needs a real Fudan ID session. So this code
 * throws at the session guard rather than returning anything invented, and
 * nothing here may be described as "verified against the live service" until
 * someone runs it with an account.
 */

import { BaseRepository } from './BaseRepository'
import { HttpUtil, HttpResponse, HttpError } from '../util/HttpUtil'
import { BusSchedule, BusDirection, ElectricityInfo } from '../model/Academic'
import { FduAuthPolicy } from '../model/FduAuth'
import { DormRequestPolicy } from '../model/DormRequestPolicy'

/** A data-format failure is distinct from a proven expired login session. */
export class ZlappDataFormatError extends HttpError {
  readonly isHtml: boolean

  constructor(message: string, body: string) {
    const html: boolean = /<!doctype\s+html|<(?:html|head|body|script|form|title)[\s>]/i.test(body)
    super(200, 0, message + '\n\n详细信息 / Details\nHttpError (status=200, code=0): ZLAPP_NON_JSON (responseKind=' +
      (html ? 'html' : body.trim() ? 'text' : 'empty') + '; phase=json-decode)', body, 'json-decode')
    this.isHtml = html
  }
}

/** The server's own campus names, in the order its ordinal mapping uses. */
const CAMPUS_NAMES: string[] = ['邯郸', '枫林', '江湾', '张江']

// Locally-declared response shapes. Every field is optional and typed `Object`
// because this is a loose third-party payload: a field can arrive as a string
// or a number (`arrow`/`holiday` are parsed from strings upstream, but nothing
// in the protocol promises that). `textOf` normalises both without inventing.
interface BusEnvelope {
  d?: BusData
}

interface BusData {
  data?: BusRoute[]
}

interface BusRoute {
  lists?: BusItem[]
}

interface BusItem {
  id?: Object
  start?: Object
  end?: Object
  stime?: Object
  etime?: Object
  arrow?: Object
  holiday?: Object
}

interface DormEnvelope {
  d?: DormData
}

interface DormData {
  fj_surplus?: Object
  fj_used?: Object
  fj_update_time?: Object
  roomid?: Object
  xq?: Object
  ssmc?: Object
  fjmc?: Object
}

export class ZlappRepository extends BaseRepository {
  static readonly HOST: string = 'https://zlapp.fudan.edu.cn'

  /** Upstream `_INFO_URL` (lib/repository/fdu/bus_repository.dart:29-30). POST. */
  static readonly BUS_URL: string =
    'https://zlapp.fudan.edu.cn/fudanbus/wap/default/lists'

  /** Upstream `electricityUrl` (lib/repository/fdu/dorm_repository.dart:24-25). GET. */
  static readonly DORM_URL: string =
    'https://zlapp.fudan.edu.cn/fudanelec/wap/default/info'

  /**
   * Upstream `Constant.defaultUserAgent`, mobile branch
   * (lib/common/constant.dart:71-72) — the value the Flutter app really sent.
   * Kept verbatim: a UA mismatch here surfaces as an opaque login redirect
   * rather than as an error, so it is not a free choice.
   */
  private static readonly UA: string = HttpUtil.MOBILE_BROWSER_UA

  private static instance: ZlappRepository | null = null

  /** Session cookie string for zlapp.fudan.edu.cn; in memory only. */
  private campusCookies: string = ''
  private electricityCookie: string = ''
  private electricityAt: number = 0
  private electricityValue: ElectricityInfo | null = null
  private electricityFlight: Promise<ElectricityInfo> | null = null
  private electricityFlightCookie: string = ''
  private electricityVersion: number = 0
  private electricityFailure: HttpError | null = null
  private electricityRetryAt: number = 0
  private electricityFailureCookie: string = ''
  private electricitySsoSerial: number = 0

  dormSsoSerial(): number { return this.electricitySsoSerial }
  acceptDormSso(cookies: string, response: HttpResponse): void {
    const result: ElectricityInfo = ZlappRepository.parseElectricity(response.data)
    this.setSession(cookies)
    this.electricityValue = result; this.electricityCookie = cookies; this.electricityAt = Date.now()
    this.electricityFailure = null
    this.electricitySsoSerial++
  }

  private constructor() {
    super()
  }

  static getInstance(): ZlappRepository {
    if (!ZlappRepository.instance) {
      ZlappRepository.instance = new ZlappRepository()
    }
    return ZlappRepository.instance
  }

  setSession(cookies: string): void {
    this.campusCookies = cookies
  }

  hasSession(): boolean {
    return this.campusCookies.length > 0
  }

  forgetSession(): void {
    this.campusCookies = ''
    this.electricityCookie = ''
    this.electricityValue = null
    this.electricityFlight = null
    this.electricityVersion++
    this.electricityFailure = null
  }

  private sessionError(): HttpError {
    return new HttpError(
      0,
      0,
      '校车与宿舍电费需要先用复旦 ID 登录（服务 zlapp.fudan.edu.cn）。',
      ''
    )
  }

  private sessionHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': ZlappRepository.UA,
      'Cookie': this.campusCookies,
    }
    return headers
  }

  /**
   * Bus timetable.
   *
   * `holiday` selects the weekend/holiday timetable; upstream decides it from
   * the weekday (`isTodayHoliday()`, lib/feature/bus_feature.dart:57-60) and
   * the dashboard loads both variants. The field is sent as "1" or "0" — the
   * server's own encoding (lib/util/public_extension_methods.dart:121-126).
   */
  async getBusSchedules(holiday: boolean): Promise<BusSchedule[]> {
    if (!this.hasSession()) {
      throw this.sessionError()
    }
    const fields: Record<string, string> = { 'holiday': holiday ? '1' : '0' }
    const response: HttpResponse = await this.httpUtil.postMultipart(
      ZlappRepository.BUS_URL,
      fields,
      this.sessionHeaders()
    )
    const schedules: BusSchedule[] = ZlappRepository.parseBusSchedules(response.data)
    if (schedules.length === 0) {
      // A 200 that decodes to nothing means the payload changed shape or the
      // session lapsed and we got a login page. Rendering that as "no buses
      // today" would be a lie, so it is an error.
      throw new HttpError(
        response.code,
        0,
        '校车时刻未能解析（可能是会话已失效或接口结构变化）。',
        response.data
      )
    }
    return schedules
  }

  /**
   * Dorm electricity for the account the session belongs to.
   *
   * The request carries no room or campus identifier: the server picks the room
   * from the session (upstream dorm_repository.dart:33-36).
   */
  async getDormElectricity(force: boolean = false, timeoutMs: number = DormRequestPolicy.WAIT_MS,
    ssoSerial: number = this.electricitySsoSerial): Promise<ElectricityInfo> {
    if (!this.hasSession()) {
      throw this.sessionError()
    }
    const cookie: string = this.campusCookies
    if ((!force || this.electricitySsoSerial > ssoSerial) && this.electricityValue !== null &&
      this.electricityCookie === cookie && Date.now() - this.electricityAt < 600000) return this.electricityValue
    if (this.electricityFlight !== null && this.electricityFlightCookie === cookie) return this.electricityFlight
    if (!force && this.electricityFailure !== null && this.electricityFailureCookie === cookie && Date.now() < this.electricityRetryAt) throw this.electricityFailure
    if (timeoutMs <= 0) throw new HttpError(-1, 2300028,
      '寝室电费读取超时，请稍后重新加载。 Operation timeout (phase=dorm-budget; totalBudgetMs=60000)', '', 'dorm-budget')
    const version: number = ++this.electricityVersion
    const headers: Record<string, string> = this.sessionHeaders()
    // Match the upstream body-free GET. Do not send an empty Content-Type
    // or negotiate JSON as a request body; the response parser stays JSON.
    headers['Content-Type'] = ''
    headers['Accept'] = '*/*'
    const deadline: number = Date.now() + timeoutMs
    const task: Promise<ElectricityInfo> = this.httpUtil.get(ZlappRepository.DORM_URL, undefined, headers, timeoutMs)
      .catch((error: Object): Promise<HttpResponse> => {
        if (version !== this.electricityVersion || cookie !== this.campusCookies ||
          !(error instanceof HttpError) || error.statusCode !== -1 || error.code !== 2300060 || Date.now() >= deadline) throw error as Error
        // One read-only retry with ordinary TLS validation, bounded by the
        // original deadline. It does not renew login or call usage history.
        return this.httpUtil.get(ZlappRepository.DORM_URL, undefined, headers, deadline - Date.now(), true)
      })
      .then((response: HttpResponse): ElectricityInfo => {
        const result: ElectricityInfo = ZlappRepository.parseElectricity(response.data)
        if (version === this.electricityVersion && cookie === this.campusCookies) {
          this.electricityValue = result; this.electricityCookie = cookie; this.electricityAt = Date.now()
          this.electricityFailure = null
        }
        return result
      }).catch((error: Object): ElectricityInfo => {
        if (version === this.electricityVersion && cookie === this.campusCookies && error instanceof HttpError &&
          (error.statusCode === -1 || error.statusCode >= 500 || error instanceof ZlappDataFormatError)) {
          this.electricityFailure = error; this.electricityFailureCookie = cookie; this.electricityRetryAt = Date.now() + 30000
        }
        throw error as Error
      })
    this.electricityFlight = task
    this.electricityFlightCookie = cookie
    try { return await task } finally { if (this.electricityFlight === task) this.electricityFlight = null }
  }

  // ─────────────────────────── parsing ───────────────────────────

  /**
   * Decode the bus payload.
   *
   * Shape (bus_repository.dart:48-54): root `d` → `data` (array of routes) →
   * per-route `lists` (array of departures). Upstream flattens every route into
   * one list and keeps the route object nowhere, so there is no line name here
   * either.
   *
   * Rows whose `stime` and `etime` are both empty are dropped, matching
   * upstream's `filter((e) => e.realStartTime != null)` (bus_repository.dart:55).
   * A malformed time is treated as empty rather than throwing: upstream would
   * throw on `int.parse` for the whole response, and losing one departure is
   * strictly better than losing the timetable.
   */
  static parseBusSchedules(body: string): BusSchedule[] {
    if (FduAuthPolicy.isLoginDocument(body)) throw new HttpError(-2, 0, '校车服务会话已失效，请继续身份验证。', '')
    let envelope: BusEnvelope | null = null
    try {
      envelope = JSON.parse(body.trim()) as BusEnvelope
    } catch (e) {
      throw new ZlappDataFormatError('校车时刻暂时无法读取，服务返回了非 JSON 内容。', body)
    }
    const out: BusSchedule[] = []
    if (!envelope || !envelope.d || !envelope.d.data) {
      return out
    }
    const routes: BusRoute[] = envelope.d.data
    for (const route of routes) {
      const items: BusItem[] | undefined = route.lists
      if (!items) {
        // Upstream skips a route whose `lists` is not a list rather than failing.
        continue
      }
      for (const item of items) {
        const startTime: string = ZlappRepository.parseBusTime(
          ZlappRepository.textOf(item.stime)
        )
        const endTime: string = ZlappRepository.parseBusTime(
          ZlappRepository.textOf(item.etime)
        )
        if (startTime.length === 0 && endTime.length === 0) {
          continue
        }
        const arrow: number = ZlappRepository.intOf(item.arrow, 0)
        const schedule: BusSchedule = {
          id: ZlappRepository.textOf(item.id),
          startCampus: ZlappRepository.campusName(ZlappRepository.textOf(item.start)),
          endCampus: ZlappRepository.campusName(ZlappRepository.textOf(item.end)),
          startTime: startTime,
          endTime: endTime,
          direction: ZlappRepository.directionOf(arrow),
          holidayRun: ZlappRepository.intOf(item.holiday, 0) !== 0,
        }
        out.push(schedule)
      }
    }
    return out
  }

  /**
   * Decode the dorm payload.
   *
   * Shape (dorm_repository.dart:40-51): everything under root `d`, and upstream
   * reads exactly `fj_surplus`, `fj_used`, `fj_update_time`, `roomid`, `xq`,
   * `ssmc`, `fjmc`. `dormName` is the server's own `xq + ssmc + fjmc`
   * concatenation, reproduced verbatim.
   *
   * Deviation from upstream, deliberate: upstream calls `.toString()` on each
   * key, so an absent one becomes the literal text "null" and a student sees
   * "邯郸nullnull". Here a missing value is `''`. Absent data is reported as
   * absent rather than as the word "null".
   */
  static parseElectricity(body: string): ElectricityInfo {
    if (FduAuthPolicy.isLoginDocument(body)) throw new HttpError(-2, 0, '宿舍电费服务会话已失效，请继续身份验证。', '')
    let envelope: DormEnvelope | null = null
    try {
      envelope = JSON.parse(body.trim()) as DormEnvelope
    } catch (e) {
      throw new ZlappDataFormatError('宿舍电费暂时无法读取，服务返回了非 JSON 内容。', body)
    }
    if (!envelope || !envelope.d) {
      throw new HttpError(200, 0, '宿舍电费响应缺少 d 字段，接口结构可能已变化。', body)
    }
    const data: DormData = envelope.d
    const dormName: string =
      ZlappRepository.textOf(data.xq) +
      ZlappRepository.textOf(data.ssmc) +
      ZlappRepository.textOf(data.fjmc)
    const info: ElectricityInfo = {
      available: ZlappRepository.textOf(data.fj_surplus),
      used: ZlappRepository.textOf(data.fj_used),
      updateTime: ZlappRepository.textOf(data.fj_update_time),
      roomId: ZlappRepository.textOf(data.roomid),
      dormName: dormName,
    }
    return info
  }

  /**
   * `08.30` / `8:3` → `08:30`. Empty when unparseable.
   *
   * Upstream `_parseTime` replaces dots with colons before handing the value to
   * `VagueTime.onlyHHmm` (bus_repository.dart:88-93); the zero padding here is
   * the same padding upstream applies at render time via `NumberFormat("00")`
   * (bus_repository.dart:160-165).
   */
  static parseBusTime(raw: string): string {
    if (raw.length === 0) {
      return ''
    }
    const parts: string[] = raw.replace(/\./g, ':').split(':')
    if (parts.length < 2) {
      return ''
    }
    const hour: number = parseInt(parts[0], 10)
    const minute: number = parseInt(parts[1], 10)
    if (isNaN(hour) || isNaN(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return ''
    }
    return String(hour).padStart(2, '0') + ':' + String(minute).padStart(2, '0')
  }

  /**
   * Map the server's campus text to one of the four campuses.
   *
   * Upstream `CampusEx.fromChineseName` is a substring match against
   * ["邯郸", "枫林", "江湾", "张江"] and falls back to `Campus.NONE`
   * (lib/common/constant.dart:613-626). `''` is that NONE here.
   */
  static campusName(raw: string): string {
    for (const name of CAMPUS_NAMES) {
      if (raw.indexOf(name) >= 0) {
        return name
      }
    }
    return ''
  }

  /** Server ordinal → enum; an unknown ordinal is NONE, never a guess. */
  static directionOf(value: number): BusDirection {
    if (value === 1) {
      return BusDirection.DUAL
    }
    if (value === 2) {
      return BusDirection.BACKWARD
    }
    if (value === 3) {
      return BusDirection.FORWARD
    }
    return BusDirection.NONE
  }

  /** Loose JSON field → text. Objects and arrays yield `''`, never "[object]". */
  private static textOf(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value === 'string') {
      return value as string
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value)
    }
    return ''
  }

  /** Loose JSON field → int, with an explicit fallback. */
  private static intOf(value: Object | undefined, fallback: number): number {
    const text: string = ZlappRepository.textOf(value)
    if (text.length === 0) {
      return fallback
    }
    const parsed: number = parseInt(text, 10)
    return isNaN(parsed) ? fallback : parsed
  }
}
