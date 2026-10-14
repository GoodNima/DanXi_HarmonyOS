import { AppState } from '../common/AppState'
import { CampusCookies } from '../common/CampusCookies'
import { HttpUtil, HttpError, HttpResponse } from '../util/HttpUtil'
import { FduAuthPolicy } from '../model/FduAuth'
import { CampusHtml, CampusHtmlNode } from '../model/CampusHtml'
import { LibraryAccountParser, LibraryReader, LibraryAccountResult, LibraryAccountItem, LibraryPickupList, LibraryRequestPolicy, LibraryRequestOptions } from '../model/LibraryAccount'
import { LibraryHolding } from '../model/LibraryBooks'
import { LibraryReadDiagnostics } from '../common/LibraryReadDiagnostics'

interface LibraryToken { access_token: string; expires_in: number }
interface LibraryCallback { openToken: string }
interface LibraryAuthorization { redirectUri?: string }
interface LibraryCache { body: string; at: number }
interface LibraryClient { target: string; response_type: string; loginType: string; client_id: string; redirect_uri: string }
interface LibraryRequestPage { range: number; pageSize: number; pageNo: number }
interface LibraryBarcode { itemBarcode: string }
interface LibraryRenewal extends LibraryBarcode { userBarcode: string }
interface LibraryCancellation { requestId: number }
interface LibraryNewRequest extends LibraryBarcode { expectDate: string; pickupLocation: string; allowReplace: string }
/** Official OPAC OAuth, matching LibraryAccountAPI.swift. Tokens stay in memory;
 * only explicit verification opens a browser. The campus SSO jar is reused. */
export class LibraryAccountSession {
  static readonly AUTH: string = 'https://fdulib.a-lsp.com'
  static readonly GATEWAY: string = 'https://fdulspgw.fudan.edu.cn'
  static readonly PARAMETERS: string = 'target=true&response_type=code&loginType=member&client_id=rfid&redirect_uri=' + encodeURIComponent('https://opac.fudan.edu.cn/#/redirect')
  static readonly PAGE: string = LibraryAccountSession.AUTH + '/authServer/?' + LibraryAccountSession.PARAMETERS
  private static token: string = ''
  private static expires: number = 0
  private static tokenOwner: string = ''
  private static flight: Promise<string> | undefined = undefined
  static owner(): string { return AppState.getPerson().getStudentId() + '/' + AppState.isLoggedIn() + '/' + CampusCookies.generation() }
  private static headers(referer: string): Record<string, string> {
    const headers: Record<string, string> = {}; headers['Authorization'] = ''; headers['Accept'] = 'application/json'
    headers['User-Agent'] = HttpUtil.BROWSER_UA; headers['tenant-id'] = 'fdulib'; headers['Origin'] = LibraryAccountSession.AUTH; headers['Referer'] = referer
    return headers
  }
  static reset(): void { LibraryAccountSession.token = ''; LibraryAccountSession.expires = 0 }
  static access(): Promise<string> {
    const owner = LibraryAccountSession.owner()
    if (!AppState.isLoggedIn()) return Promise.reject(new HttpError(-2, 0, '请先登录复旦账号，再查询图书馆借阅和预约。', ''))
    if (LibraryAccountSession.tokenOwner !== owner) { LibraryAccountSession.reset(); LibraryAccountSession.tokenOwner = owner; LibraryAccountSession.flight = undefined }
    if (LibraryAccountSession.token && LibraryAccountSession.expires > Date.now() + 60000) return Promise.resolve(LibraryAccountSession.token)
    if (LibraryAccountSession.flight !== undefined) return LibraryAccountSession.flight
    const task = LibraryAccountSession.login(owner).finally(() => { if (LibraryAccountSession.flight === task) LibraryAccountSession.flight = undefined })
    LibraryAccountSession.flight = task; return task
  }
  private static async login(owner: string): Promise<string> {
    const http = HttpUtil.getInstance()
    await http.getCampusSso(LibraryAccountSession.PAGE)
    const client: LibraryClient = { target: 'true', response_type: 'code', loginType: 'member', client_id: 'rfid', redirect_uri: 'https://opac.fudan.edu.cn/#/redirect' }
    const clientHeaders = LibraryAccountSession.headers(LibraryAccountSession.PAGE); clientHeaders['Content-Type'] = 'application/json'
    const response = await http.post(LibraryAccountSession.AUTH + '/open-api/openapi/oauth2/getClientParams', JSON.stringify(client), clientHeaders)
    const loginUrl = LibraryAccountParser.data<string>(response.data)
    if (!FduAuthPolicy.isCampusUrl(loginUrl)) throw new Error('Invalid library SSO client URL')
    if (FduAuthPolicy.isIdUrl(loginUrl)) throw new HttpError(-2, 0, '图书馆借阅需要读者身份验证，请点击继续验证。', '')
    let login = await http.getCampusSso(loginUrl)
    let callback = login.finalUrl ?? ''
    if (!LibraryAccountSession.callback(callback)) {
      login = await LibraryAccountSession.submitForm(login); callback = login.finalUrl ?? ''
    }
    if (owner !== LibraryAccountSession.owner()) throw new Error('Library account changed')
    if (!LibraryAccountSession.callback(callback)) throw new HttpError(-2, 0, '图书馆借阅需要读者身份验证，请点击继续验证。', '')
    const query: string = callback.split('?')[1].split('#')[0]
    const verified = await http.get(LibraryAccountSession.AUTH + '/open-api/openapi/oauth2/authCallBack?' + query, undefined, LibraryAccountSession.headers(callback))
    const token = LibraryAccountParser.data<LibraryCallback>(verified.data).openToken
    if (!token) throw new Error('Library open token is missing')
    const headers = LibraryAccountSession.headers(callback); headers['openToken'] = token
    const url: string = LibraryAccountSession.AUTH + '/open-api/openapi/oauth2/authorize?' + LibraryAccountSession.PARAMETERS
    let authorization = LibraryAccountParser.data<LibraryAuthorization>((await http.get(url, undefined, headers)).data)
    if (!authorization.redirectUri) {
      LibraryAccountParser.status((await http.get(LibraryAccountSession.AUTH + '/open-api/openapi/oauth2/doConfirm?' + LibraryAccountSession.PARAMETERS, undefined, headers)).data)
      authorization = LibraryAccountParser.data<LibraryAuthorization>((await http.get(url, undefined, headers)).data)
    }
    return LibraryAccountSession.accept(authorization.redirectUri ?? '', owner)
  }
  private static callback(url: string): boolean { return /^https:\/\/fdulib\.a-lsp\.com\/authServer\/auth\?/.test(url) && /[?&]authCode=/.test(url) && /[?&]ticket=/.test(url) }
  private static async submitForm(response: HttpResponse): Promise<HttpResponse> {
    const url: string = response.finalUrl ?? ''
    if (FduAuthPolicy.origin(url) !== 'https://rwsjcas.fudan.edu.cn') throw new HttpError(-2, 0, '图书馆借阅需要读者身份验证，请点击继续验证。', '')
    const form = CampusHtml.parse(response.data).findId('fm1')
    if (form === undefined) throw new HttpError(-2, 0, '图书馆读者会话需要继续验证。', '')
    const action: string = FduAuthPolicy.resolve(form.attributes['action'] ?? '', url)
    if (FduAuthPolicy.origin(action) !== 'https://rwsjcas.fudan.edu.cn') throw new Error('Invalid library CAS form action')
    const fields: Record<string, string> = {}; LibraryAccountSession.inputs(form, fields)
    const names: string[] = ['username', 'password', 'domainName', 'source']
    for (const name of names) { const match = new RegExp('[?&]' + name + '=([^&#]*)').exec(action); if (match !== null) fields[name] = decodeURIComponent(match[1].replace(/\+/g, ' ')) }
    if (!fields['username'] || !fields['password']) throw new HttpError(-2, 0, '请在图书馆官方页面完成读者身份验证。', '')
    if (fields['imgverifycode'] !== undefined) fields['imgverifycode'] = '******'
    const headers: Record<string, string> = {}; headers['Authorization'] = ''; headers['Origin'] = 'https://rwsjcas.fudan.edu.cn'; headers['Referer'] = url
    return HttpUtil.getInstance().postForm(action, fields, headers)
  }
  private static inputs(node: CampusHtmlNode, fields: Record<string, string>): void {
    if (node.tag === 'input' && node.attributes['name']) fields[node.attributes['name']] = node.attributes['value'] ?? ''
    for (const child of node.children) LibraryAccountSession.inputs(child, fields)
  }
  static async accept(url: string, owner: string = LibraryAccountSession.owner()): Promise<string> {
    if (!/^https:\/\/opac\.fudan\.edu\.cn\/(?:#\/redirect\?|\?)/.test(url)) throw new Error('Invalid library OAuth redirect')
    const match = /[?&]code=([^&#]+)/.exec(url); if (match === null) throw new Error('Library authorization code is missing')
    const headers: Record<string, string> = {}; headers['Authorization'] = ''; headers['Origin'] = 'https://opac.fudan.edu.cn'; headers['Referer'] = 'https://opac.fudan.edu.cn/'; headers['Accept'] = 'application/json'
    const response = await HttpUtil.getInstance().get(LibraryAccountSession.GATEWAY + '/alsp/open-api/openapi/oauth2/getToken?client_id=rfid&code=' + encodeURIComponent(decodeURIComponent(match[1])) + '&grant_type=authorization_code', undefined, headers)
    const token = LibraryAccountParser.data<LibraryToken>(response.data)
    if (!token.access_token || !Number.isFinite(token.expires_in) || owner !== LibraryAccountSession.owner()) throw new Error('Invalid or expired library token owner')
    LibraryAccountSession.token = token.access_token; LibraryAccountSession.expires = Date.now() + token.expires_in * 1000; LibraryAccountSession.tokenOwner = owner
    await CampusCookies.persist(); return token.access_token
  }
  static async data(path: string, payload?: Object, mutation: boolean = false): Promise<string> {
    const owner = LibraryAccountSession.owner()
    let usedToken: string = ''
    const read = async (token: string): Promise<string> => {
      usedToken = token
      const headers: Record<string, string> = {}; headers['Authorization'] = ''; headers['access_token'] = token
      headers['Accept'] = 'application/json'; headers['Referer'] = 'https://opac.fudan.edu.cn/'; headers['Content-Type'] = 'application/json'
      const url = LibraryAccountSession.GATEWAY + '/alsp/open-api' + path
      try {
        const response = payload === undefined ? await HttpUtil.getInstance().get(url, undefined, headers) : await HttpUtil.getInstance().post(url, JSON.stringify(payload), headers)
        LibraryAccountParser.status(response.data); return response.data
      } catch (error) {
        if (error instanceof HttpError && (error.statusCode === 401 || error.statusCode === 403)) throw new HttpError(-2, error.code, '图书馆读者会话已失效，请点击继续验证。 HTTP ' + error.statusCode, '')
        throw error as Error
      }
    }
    try { const body = await read(await LibraryAccountSession.access()); if (owner !== LibraryAccountSession.owner()) throw new Error('Library account changed'); return body }
    catch (e) {
      if (!mutation && owner === LibraryAccountSession.owner() && e instanceof HttpError && e.statusCode === -2 && usedToken) {
        // Another failed read may already be renewing this token. Join that
        // renewal, and never invalidate a newer successful OAuth completion.
        if (LibraryAccountSession.token === usedToken) LibraryAccountSession.reset()
        const body = await read(await LibraryAccountSession.access()); if (owner !== LibraryAccountSession.owner()) throw new Error('Library account changed'); return body
      }
      throw e as Error
    }
  }
}
export interface LibraryAccountSource {
  owner(): string
  list(kind: string, history: boolean, page: number, force: boolean): Promise<LibraryAccountResult>
  renew(row: LibraryAccountItem): Promise<void>
  cancel(id: number): Promise<void>
  options(holding: LibraryHolding): Promise<LibraryRequestOptions>
  request(holding: LibraryHolding, pickup: string, day: string, replace: boolean): Promise<void>
}
export class LibraryAccountRepository implements LibraryAccountSource {
  private static cache: Map<string, LibraryCache> = new Map()
  private static flights: Map<string, Promise<string>> = new Map()
  private static mutations: Map<string, Promise<void>> = new Map()
  owner(): string { return LibraryAccountSession.owner() }
  private read(path: string, payload?: Object, force: boolean = false, validate?: (body: string) => void): Promise<string> {
    const owner = this.owner(), key = owner + '/' + path + JSON.stringify(payload)
    const cached = LibraryAccountRepository.cache.get(key); if (!force && cached !== undefined && Date.now() - cached.at < 60000) return Promise.resolve(cached.body)
    const joined = LibraryAccountRepository.flights.get(key); if (joined !== undefined) return joined
    const task = LibraryAccountSession.data(path, payload).then((body: string): string => {
      if (owner !== this.owner()) throw new Error('Library account changed')
      if (validate !== undefined) validate(body)
      LibraryAccountRepository.cache.set(key, { body, at: Date.now() }); while (LibraryAccountRepository.cache.size > 32) { const first: string | undefined = LibraryAccountRepository.cache.keys().next().value; if (first !== undefined) LibraryAccountRepository.cache.delete(first) } return body
    }).finally(() => { if (LibraryAccountRepository.flights.get(key) === task) LibraryAccountRepository.flights.delete(key) })
    LibraryAccountRepository.flights.set(key, task); return task
  }
  async list(kind: string, history: boolean, page: number, force: boolean): Promise<LibraryAccountResult> {
    if (!Number.isInteger(page) || page < 1) throw new Error('Invalid library page')
    if (kind === 'requests') {
      const payload: LibraryRequestPage = { range: history ? 1 : 0, pageSize: 20, pageNo: page }
      return LibraryAccountParser.requests(await this.read('/elib5/searchReaderRequest', payload, force,
        (body: string): void => { LibraryAccountParser.requests(body, page) }), page)
    }
    // History uses the official API's ten-row default. Missing server data is
    // a data error, not evidence that an already valid reader token expired.
    const size: number = history ? 10 : 20
    const owner: string = this.owner()
    const body = await this.read('/elib5/' + (history ? 'v2/getReaderHistoryLoan' : 'getReaderCurrentLoan') + '?pageSize=' + size + '&pageNo=' + page, undefined, force,
      (value: string): void => {
        LibraryReadDiagnostics.record(owner, kind, history, page, size, value)
        if (history) LibraryAccountParser.history(value, page, size); else LibraryAccountParser.current(value, page)
      })
    return history ? LibraryAccountParser.history(body, page, size) : LibraryAccountParser.current(body, page)
  }
  private mutate(key: string, operation: () => Promise<void>): Promise<void> {
    const owner = this.owner(), id = owner + '/' + key, joined = LibraryAccountRepository.mutations.get(id); if (joined !== undefined) return joined
    const task = operation().then(() => { if (owner !== this.owner()) throw new Error('Library account changed'); LibraryAccountRepository.cache.clear() })
      .finally(() => { if (LibraryAccountRepository.mutations.get(id) === task) LibraryAccountRepository.mutations.delete(id) })
    LibraryAccountRepository.mutations.set(id, task); return task
  }
  renew(row: LibraryAccountItem): Promise<void> { return this.mutate('renew/' + row.barcode, async (): Promise<void> => {
    const reader = LibraryAccountParser.data<LibraryReader>(await this.read('/elib5/getReaderInfo'))
    if (!row.barcode || !reader.barcode) throw new Error('Library renewal barcode is missing')
    const payload: LibraryRenewal = { itemBarcode: row.barcode, userBarcode: reader.barcode }
    await LibraryAccountSession.data('/elib5/renewLoan', payload, true)
  }) }
  cancel(id: number): Promise<void> { return this.mutate('cancel/' + id, async (): Promise<void> => {
    if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Invalid library request ID')
    const payload: LibraryCancellation = { requestId: id }; await LibraryAccountSession.data('/elib5/cancelRequest', payload, true)
  }) }
  async options(holding: LibraryHolding): Promise<LibraryRequestOptions> {
    if (!holding.barcode || !holding.libraryCode || !holding.locationCode || holding.canRequest === false) throw new Error('This copy cannot be requested')
    const payload: LibraryBarcode = { itemBarcode: holding.barcode }
    const policy = LibraryAccountParser.data<LibraryRequestPolicy>(await this.read('/elib5/selectRequestDays', payload))
    const locations = LibraryAccountParser.data<LibraryPickupList>(await this.read('/system/location/canPickupSimpleList?libraryCode=' + encodeURIComponent(holding.libraryCode) + '&locationCode=' + encodeURIComponent(holding.locationCode)))
    if (!Number.isInteger(policy.requestDateRange) || policy.requestDateRange < 0 || !Array.isArray(locations.available)) throw new Error('Invalid library request policy')
    return { policy, locations: locations.available }
  }
  request(holding: LibraryHolding, pickup: string, day: string, replace: boolean): Promise<void> { return this.mutate('request/' + holding.barcode, async (): Promise<void> => {
    if (!holding.barcode || !pickup || !/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new Error('Invalid book request')
    const payload: LibraryNewRequest = { itemBarcode: holding.barcode, expectDate: day, pickupLocation: pickup, allowReplace: replace ? '1' : '0' }
    await LibraryAccountSession.data('/elib5/addRequest', payload, true)
  }) }
}
