import { BaseRepository } from './BaseRepository'
import { HttpError, HttpResponse, HttpUtil } from '../util/HttpUtil'
import { DiningCampusData, DiningOutsideMealTime, DiningSnapshot, DiningTraffic, ElectricityUsage, LibraryVisitors } from '../model/CampusLiveData'
import { FduAuthPolicy } from '../model/FduAuth'
import { CampusCookies } from '../common/CampusCookies'
import { DormHistoryDiagnostics, DormHistoryQuery } from '../model/DormHistoryDiagnostics'
import { DiningPresentation } from '../common/DiningPresentation'
import { Constant } from '../common/Constant'

export type DormHistorySessionRecovery = (cookies: string, query: DormHistoryQuery) => Promise<string>

interface LibraryEnvelope { data?: LibraryWire[]; code?: Object; message?: string }
interface LibraryWire { campusId?: Object; campusName?: Object; inNum?: Object; canInNumb?: Object; libraryOpenTime?: Object }
interface HistoryEnvelope { data?: Object[][] }

/** Read-only endpoints and field layouts from DanXi 1.5.3+350, commit 551a88c7. */
export class CampusLiveRepository extends BaseRepository {
  static readonly DINING_URL: string = 'https://my.fudan.edu.cn/simple_list/stqk'
  static readonly LIBRARY_URL: string = 'https://mlibrary.fudan.edu.cn/api/common/h5/getspaceseat'
  static readonly ELECTRICITY_HISTORY_URL: string = 'https://my.fudan.edu.cn/data_tables/ykt_xszsqyydqk.json'
  static readonly CAMPUSES: string[] = Constant.CAMPUS_NAMES
  // Older university chart triples use their own wire order, independent of UI.
  private static readonly DINING_WIRE_CAMPUSES: string[] = ['邯郸', '枫林', '张江', '江湾']
  private static historyFlights: Map<string, Promise<ElectricityUsage[]>> = new Map()
  private static historyRetries: Map<string, number> = new Map()

  async dining(cookies: string, campus: string): Promise<DiningTraffic[]> {
    return CampusLiveRepository.parseDining(await this.diningDocument(cookies), campus)
  }

  async diningSnapshot(cookies: string): Promise<DiningSnapshot> {
    const body = await this.diningDocument(cookies)
    const result = new DiningSnapshot()
    for (const campus of CampusLiveRepository.CAMPUSES) {
      const item = new DiningCampusData(); item.campus = campus
      try {
        item.traffic = CampusLiveRepository.parseDining(body, campus)
      } catch (error) {
        if (error instanceof DiningOutsideMealTime) {
          result.campuses = []; result.status = 'outside'; break
        }
        if (error instanceof HttpError) throw error
        item.error = error instanceof Error ? error.message : String(error)
      }
      result.campuses.push(item)
    }
    if (result.campuses.length > 0 && result.campuses.every(item => item.error.length > 0)) {
      throw new Error(result.campuses[0].error)
    }
    result.updatedAt = Date.now()
    return result
  }

  private async diningDocument(cookies: string): Promise<string> {
    if (!cookies) throw new HttpError(-2, 0, 'Missing campus session', '')
    let response: HttpResponse
    try {
      response = await this.httpUtil.get(CampusLiveRepository.DINING_URL, undefined,
        { 'Cookie': cookies, 'User-Agent': HttpUtil.BROWSER_UA, 'Referer': 'https://my.fudan.edu.cn/',
          'Accept': '*/*', 'Content-Type': '' }, 12000)
    } catch (error) {
      if (error instanceof HttpError && error.statusCode >= 500) {
        throw new HttpError(error.statusCode, error.code,
          '食堂排队人数服务暂时异常（HTTP ' + String(error.statusCode) + '），请稍后刷新。', error.body)
      }
      throw error as Error
    }
    return response.data
  }

  async library(): Promise<LibraryVisitors[]> {
    // Match upstream dio.post(url) with no body. The native HTTP API rejects
    // extraData: '' as parameter error 401 before reaching this public service.
    const response = await this.httpUtil.post(CampusLiveRepository.LIBRARY_URL, undefined,
      { 'User-Agent': HttpUtil.BROWSER_UA, 'Accept': 'application/json', 'Authorization': '' })
    return CampusLiveRepository.parseLibrary(response.data)
  }

  async electricityHistory(cookies: string, offset: number = 0, size: number = 30,
    recoverSession?: DormHistorySessionRecovery): Promise<ElectricityUsage[]> {
    if (!cookies) throw new HttpError(-2, 0, 'Missing campus session', '')
    if (!Number.isInteger(offset) || offset < 0 || !Number.isInteger(size) || size < 1 || size > 100) {
      throw new Error('Invalid electricity history range')
    }
    const epoch: number = CampusCookies.generation()
    const key: string = String(epoch) + ':' + cookies + ':' + offset + ':' + size + ':' + String(recoverSession !== undefined)
    const existing = CampusLiveRepository.historyFlights.get(key)
    if (existing !== undefined) return existing
    const task = this.readElectricityHistory(cookies, offset, size, epoch, recoverSession)
    CampusLiveRepository.historyFlights.set(key, task)
    try { return await task } finally {
      if (CampusLiveRepository.historyFlights.get(key) === task) CampusLiveRepository.historyFlights.delete(key)
    }
  }

  private async readElectricityHistory(cookies: string, offset: number, size: number, epoch: number,
    recoverSession?: DormHistorySessionRecovery): Promise<ElectricityUsage[]> {
    const retryKey: string = String(epoch) + ':' + cookies
    const diagnosticQuery: number = DormHistoryDiagnostics.begin(epoch)
    let firstTimeout: string = ''
    let currentCookies: string = cookies
    for (let attempt: number = 0; attempt < 2; attempt++) {
      if (epoch !== CampusCookies.generation()) throw new Error('Campus account changed')
      try {
        // This POST only queries a DataTables page; it cannot write or pay.
        // Dio budgets connect/send/receive separately. Native readTimeout is
        // CURLOPT_TIMEOUT_MS (the whole transfer), so 5 seconds here would
        // prematurely consume the response budget during a cold handshake.
        // Keep the aggregate bound for a cold connection. HttpUtil caps
        // connect at 5 seconds and now starts the original 5-second response
        // header deadline after the upload completes; it does not permit that
        // phase alone to consume the entire 15-second transfer allowance.
        const response = await this.httpUtil.postMultipart(CampusLiveRepository.ELECTRICITY_HISTORY_URL,
          { 'draw': '2', 'start': String(offset), 'length': String(size) },
          { 'Cookie': currentCookies, 'Referer': 'https://my.fudan.edu.cn/' }, 15000,
          attempt > 0 || Date.now() < (CampusLiveRepository.historyRetries.get(retryKey) ?? 0),
          { id: diagnosticQuery, attempt: attempt + 1 })
        if (epoch !== CampusCookies.generation()) throw new Error('Campus account changed')
        const rows = CampusLiveRepository.parseElectricityHistory(response.data)
        // A recovered read must not suppress recovery of a later query. Keep
        // the cooldown only for an unresolved failure, not a repaired session.
        CampusLiveRepository.historyRetries.delete(retryKey)
        return rows
      } catch (error) {
        if (epoch !== CampusCookies.generation()) throw new Error('Campus account changed')
        // Keep both attempts' safe, transport-only diagnostics. Showing only
        // the fresh retry concealed whether the first transfer sent its form.
        if (attempt > 0 && firstTimeout && error instanceof HttpError && error.statusCode === -1 && error.code === 2300028) {
          throw new HttpError(error.statusCode, error.code, error.message + '\nPrevious request: ' + firstTimeout, '', error.transportPhase)
        }
        if (attempt > 0 || !(error instanceof HttpError) || error.statusCode !== -1 || error.code !== 2300028 ||
          Date.now() < (CampusLiveRepository.historyRetries.get(retryKey) ?? 0)) throw error as Error
        firstTimeout = error.message
        CampusLiveRepository.historyRetries.set(retryKey, Date.now() + 300000)
        while (CampusLiveRepository.historyRetries.size > 8) {
          const oldest: string | undefined = CampusLiveRepository.historyRetries.keys().next().value
          if (oldest !== undefined) CampusLiveRepository.historyRetries.delete(oldest)
        }
        if (recoverSession !== undefined && error.transportPhase === 'await-response-headers') {
          try {
            currentCookies = await recoverSession(currentCookies, { id: diagnosticQuery, attempt: 1 })
          } catch (recoveryError) {
            if (epoch !== CampusCookies.generation()) throw new Error('Campus account changed')
            // A confirmed login landing needs explicit user verification, not
            // another POST. Other bounded check failures preserve the existing
            // single fresh retry and the original query diagnostics.
            if (recoveryError instanceof HttpError &&
              (recoveryError.statusCode === -2 || recoveryError.statusCode === 401)) throw recoveryError
            if (!(recoveryError instanceof HttpError)) throw recoveryError as Error
          }
          if (epoch !== CampusCookies.generation()) throw new Error('Campus account changed')
        }
      }
    }
    throw new Error('Electricity history unavailable')
  }

  static parseDining(body: string, campus: string): DiningTraffic[] {
    if (body.length > 2 * 1024 * 1024) throw new Error('Dining response is too large')
    if (FduAuthPolicy.isLoginDocument(body)) throw new HttpError(-2, 0, '该校园服务需要继续身份验证，请点击继续验证。', '')
    if (body.includes('仅') && !/<script[\s>]/i.test(body)) throw new DiningOutsideMealTime()
    const scripts: string[] = []
    const scriptPattern: RegExp = /<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi
    let script = scriptPattern.exec(body)
    while (script !== null) { scripts.push(script[1]); script = scriptPattern.exec(body) }
    const named: string[] | undefined = CampusLiveRepository.namedDiningArrays(scripts, campus)
    const arrays: string[] = []
    if (named !== undefined) arrays.push(...named)
    else for (const source of scripts) {
      const candidate = CampusLiveRepository.jsArrays(source)
      if (candidate.length >= 3) { arrays.push(...candidate); break }
    }
    const campusIndex: number = CampusLiveRepository.DINING_WIRE_CAMPUSES.indexOf(campus)
    const start: number = named !== undefined ? 0 : campusIndex * 3
    if (campusIndex < 0 || arrays.length < start + 3) {
      if (body.includes('仅')) throw new DiningOutsideMealTime()
      throw new Error('Dining response is missing campus arrays')
    }
    const names = CampusLiveRepository.scalarArray(arrays[start])
    const current = CampusLiveRepository.scalarArray(arrays[start + 1])
    const maximum = CampusLiveRepository.scalarArray(arrays[start + 2])
    if (names.length !== current.length || names.length !== maximum.length) throw new Error('Dining array lengths differ')
    const result: DiningTraffic[] = []
    for (let i: number = 0; i < names.length; i++) {
      const count: number = Number(current[i]); const max: number = Number(maximum[i])
      if (!names[i].trim() || !Number.isInteger(count) || count < 0 || !Number.isInteger(max) || max < 0) {
        throw new Error('Dining response contains invalid traffic values')
      }
      const item = new DiningTraffic(); item.name = names[i].replace(/\\n|\r?\n/g, '-').trim()
      item.current = count; item.maximum = max; item.zone = CampusLiveRepository.diningZone(item.name, campus)
      result.push(item)
    }
    return result
  }

  /** iOS identifies chart_bb/fl/jw/zj by name; Android's positional triples
   * interchange Jiangwan and Zhangjiang when the university reorders charts.
   * Read every window (including zero and duplicate names), without executing JS. */
  private static namedDiningArrays(scripts: string[], campus: string): string[] | undefined {
    let found: boolean = false
    const code: string = campus === '邯郸' ? 'bb' : campus === '枫林' ? 'fl' : campus === '江湾' ? 'jw' : 'zj'
    for (const source of scripts) {
      const pattern: RegExp = /initStqkChart\s*\(\s*['"]([^'"]+)['"]\s*,/g
      let call: RegExpExecArray | null = pattern.exec(source)
      while (call !== null) {
        found = true
        const position: number = pattern.lastIndex
        const next: RegExpExecArray | null = pattern.exec(source)
        if (call[1] === 'chart_' + code) {
          const arrays: string[] = CampusLiveRepository.jsArrays(source.substring(position, next?.index ?? source.length))
          if (arrays.length < 3) throw new Error('Dining response is missing campus arrays: ' + call[1])
          return arrays.slice(0, 3)
        }
        call = next
      }
    }
    if (found) throw new Error('Dining response is missing campus arrays: chart_' + code)
    return undefined
  }

  static diningZone(name: string, campus: string): string {
    return DiningPresentation.zone(name, campus)
  }

  static parseLibrary(body: string): LibraryVisitors[] {
    if (body.length > 2 * 1024 * 1024) throw new Error('Library response is too large')
    let parsed: LibraryEnvelope
    try { parsed = JSON.parse(body) as LibraryEnvelope } catch (e) { throw new Error('Library response is not JSON') }
    if (!parsed || !Array.isArray(parsed.data)) throw new Error('Library response is missing data')
    if (parsed.code !== undefined && !['1', '200'].includes(CampusLiveRepository.text(parsed.code))) throw new Error('Library service rejected the request')
    const result: LibraryVisitors[] = []
    for (const wire of parsed.data) {
      if (wire === null || wire === undefined) throw new Error('Library response contains invalid visitor data')
      const name: string = CampusLiveRepository.text(wire.campusName)
      const count: string = CampusLiveRepository.text(wire.inNum)
      if (!name || !/^\d+$/.test(count) || !Number.isSafeInteger(Number(count))) throw new Error('Library response contains invalid visitor data')
      const item = new LibraryVisitors(); item.id = CampusLiveRepository.text(wire.campusId) || name; item.name = name; item.visitors = count
      const remaining: string = CampusLiveRepository.text(wire.canInNumb)
      if (remaining && (!/^\d+$/.test(remaining) || !Number.isSafeInteger(Number(count) + Number(remaining)))) throw new Error('Library response contains invalid remaining capacity')
      if (remaining) { item.remaining = Number(remaining); item.capacity = Number(count) + item.remaining }
      item.openTime = CampusLiveRepository.text(wire.libraryOpenTime); result.push(item)
    }
    return result
  }

  static parseElectricityHistory(body: string): ElectricityUsage[] {
    if (body.length > 2 * 1024 * 1024) throw new Error('Electricity history response is too large')
    let parsed: HistoryEnvelope
    try { parsed = JSON.parse(body) as HistoryEnvelope } catch (e) { throw new Error('Electricity history is not JSON') }
    if (!parsed || !Array.isArray(parsed.data)) throw new Error('Electricity history is missing data')
    const result: ElectricityUsage[] = []
    for (const wire of parsed.data) {
      if (!Array.isArray(wire) || wire.length < 6) throw new Error('Electricity history fields are incomplete')
      const item = new ElectricityUsage()
      if (wire[5] !== null && wire[5] !== undefined && typeof wire[5] !== 'number' && typeof wire[5] !== 'string') {
        throw new Error('Electricity history contains invalid usage data')
      }
      item.dormName = [CampusLiveRepository.text(wire[1]), CampusLiveRepository.text(wire[2]), CampusLiveRepository.text(wire[3])].join('/')
      item.date = CampusLiveRepository.text(wire[4]); item.amount = CampusLiveRepository.text(wire[5])
      // The upstream service returns null for days without a meter reading.
      // Keep that date as unavailable, rather than rejecting every valid row
      // or inventing a zero consumption reading.
      if (!/^\d{4}-\d{2}-\d{2}/.test(item.date) ||
        (item.amount !== '' && !/^(?:\d+\.?\d*|\.\d+)$/.test(item.amount))) throw new Error('Electricity history contains invalid usage data')
      result.push(item)
    }
    return result
  }

  /** Parse quoted scalar JavaScript arrays without executing the campus page. */
  private static jsArrays(source: string): string[] {
    const out: string[] = []; let start: number = -1; let depth: number = 0; let quote: string = ''; let escape: boolean = false
    for (let i: number = 0; i < source.length; i++) {
      const c: string = source.charAt(i)
      if (quote) { if (escape) escape = false; else if (c === '\\') escape = true; else if (c === quote) quote = ''; continue }
      if (c === '"' || c === "'" || c === '`') { quote = c; continue }
      if (source.substring(i, i + 2) === '//' || source.substring(i, i + 2) === '/*') {
        const line: boolean = source.charAt(i + 1) === '/'
        const end: number = source.indexOf(line ? '\n' : '*/', i + 2)
        if (end < 0) break
        i = end + (line ? 0 : 1); continue
      }
      if (c === '[') {
        if (depth === 0) {
          let before: number = i - 1
          while (before >= 0 && /\s/.test(source.charAt(before))) before--
          start = /[\w$)\]]/.test(source.charAt(before)) ? -1 : i
        }
        depth++
      }
      else if (c === ']' && depth > 0) { depth--; if (depth === 0 && start >= 0) out.push(source.substring(start, i + 1)) }
    }
    return out
  }

  private static arraySpace(source: string, position: number): number {
    let index: number = position
    while (index < source.length) {
      if (/\s/.test(source.charAt(index))) { index++; continue }
      if (source.substring(index, index + 2) === '//') {
        const end: number = source.indexOf('\n', index + 2)
        index = end < 0 ? source.length : end + 1; continue
      }
      if (source.substring(index, index + 2) === '/*') {
        const end: number = source.indexOf('*/', index + 2)
        if (end < 0) throw new Error('Dining array has an unterminated comment')
        index = end + 2; continue
      }
      break
    }
    return index
  }

  private static scalarArray(source: string): string[] {
    const result: string[] = []
    let index: number = 1
    while (index < source.length - 1) {
      index = CampusLiveRepository.arraySpace(source, index)
      if (index === source.length - 1) break
      let token: string = ''
      const quote: string = source.charAt(index)
      if (quote === '"' || quote === "'") {
        index++; let closed: boolean = false
        while (index < source.length - 1) {
          const c: string = source.charAt(index++)
          if (c === quote) { closed = true; break }
          if (c !== '\\') { token += c; continue }
          const escaped: string = source.charAt(index++)
          if (escaped === 'u' || escaped === 'x') {
            const size: number = escaped === 'u' ? 4 : 2
            const hex: string = source.substring(index, index + size)
            if (hex.length !== size || !/^[0-9a-f]+$/i.test(hex)) throw new Error('Dining array has an invalid escape')
            token += String.fromCharCode(parseInt(hex, 16)); index += size
          } else token += escaped === 'n' ? '\n' : escaped === 'r' ? '\r' : escaped === 't' ? '\t' : escaped
        }
        if (!closed) throw new Error('Dining array has an unterminated string')
      } else {
        const start: number = index
        while (index < source.length - 1 && !/[\s,\/]/.test(source.charAt(index))) index++
        token = source.substring(start, index)
        if (!/^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/i.test(token)) throw new Error('Dining array is invalid')
      }
      result.push(token.trim())
      index = CampusLiveRepository.arraySpace(source, index)
      if (index === source.length - 1) break
      if (source.charAt(index++) !== ',') throw new Error('Dining array is invalid')
    }
    return result
  }

  private static text(value: Object | undefined): string {
    return typeof value === 'string' || typeof value === 'number' ? String(value).trim() : ''
  }
}
