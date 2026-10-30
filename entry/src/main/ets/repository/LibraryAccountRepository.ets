import { AppState } from '../common/AppState'
import { CampusCookies } from '../common/CampusCookies'
import { HttpUtil, HttpError, HttpResponse } from '../util/HttpUtil'
import { FduAuthPolicy } from '../model/FduAuth'
import { CampusHtml, CampusHtmlNode } from '../model/CampusHtml'
import { LibraryAccountParser, LibraryReader, LibraryAccountResult, LibraryAccountItem, LibraryPickupList, LibraryRequestPolicy, LibraryRequestOptions } from '../model/LibraryAccount'
import { LibraryHolding } from '../model/LibraryBooks'
import { LibraryReadDiagnostics } from '../common/LibraryReadDiagnostics'
import { LibraryAccountSso } from '../model/LibraryAccountSso'
import { CasTicket } from '../model/CasTicket'

interface LibraryToken { access_token: string; expires_in: number }
interface LibraryCallback { openToken: string }
interface LibraryAuthorization { redirectUri?: string }
interface LibraryAuthenticationStatus { code?: number | string; e?: string; error?: string }
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
  private static revision: number = 0
  private static exchanges: Map<string, Promise<string>> = new Map()
  static owner(): string { return AppState.getPerson().getStudentId() + '/' + AppState.isLoggedIn() + '/' + CampusCookies.generation() }
  private static headers(referer: string): Record<string, string> {
    const headers: Record<string, string> = {}; headers['Authorization'] = ''; headers['Accept'] = 'application/json'
    headers['User-Agent'] = HttpUtil.BROWSER_UA; headers['tenant-id'] = 'fdulib'; headers['Origin'] = LibraryAccountSession.AUTH; headers['Referer'] = referer
    return headers
  }
  static reset(): void {
    LibraryAccountSession.token = ''; LibraryAccountSession.expires = 0
    LibraryAccountSession.revision++; LibraryAccountSession.exchanges.clear()
  }
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
    try { return await LibraryAccountSession.loginOnce(owner) }
    catch (error) {
      if (error instanceof HttpError && (error.statusCode === 401 || error.statusCode === 403)) {
        const failure = new HttpError(-2, error.code, '图书馆读者会话已失效，请点击继续验证。 HTTP ' + error.statusCode, '')
        failure.diagnostics = error.diagnostics
        throw failure
      }
      throw error as Error
    }
  }
  private static authenticationRequired(response: HttpResponse): boolean {
    if (response.code === 401 || response.code === 403) return true
    try {
      const status = JSON.parse(response.data) as LibraryAuthenticationStatus
      if (status !== null && (status.code === 401 || status.code === 403 || status.code === '401' || status.code === '403' ||
        status.code === 'UN_AUTH' || status.e === 'UN_AUTH' || status.error === 'UN_AUTH')) return true
    } catch (error) {}
    const origin = FduAuthPolicy.origin(response.finalUrl ?? '')
    return (origin === FduAuthPolicy.ID_ORIGIN || origin === 'https://rwsjcas.fudan.edu.cn') &&
      FduAuthPolicy.isLoginDocument(response.data)
  }
  private static responseFailure(response: HttpResponse, stage: string): HttpError {
    const authentication: boolean = LibraryAccountSession.authenticationRequired(response)
    const status: number = typeof response.code === 'number' && response.code > 0 ? response.code : 200
    let code: number = 0
    try {
      const wire = JSON.parse(response.data) as LibraryAuthenticationStatus
      if (wire !== null && typeof wire.code === 'number' && Number.isFinite(wire.code)) code = wire.code
      else if (wire !== null && (wire.code === '401' || wire.code === '403')) code = Number(wire.code)
    } catch (error) {}
    const error = new HttpError(authentication ? -2 : status, code, authentication ?
      '图书馆借阅需要读者身份验证，请点击继续验证。' :
      '图书馆认证服务返回了无法识别的数据，请稍后重新加载。 LibraryOAuthProtocolError (stage=' + stage + '; http=' + status + ')', '')
    if (!authentication) error.name = 'LibraryOAuthProtocolError'
    error.diagnostics = response.diagnostics ?? ''
    return error
  }
  private static responseData<T>(response: HttpResponse, stage: string): T {
    try { return LibraryAccountParser.data<T>(response.data) }
    catch (error) { throw LibraryAccountSession.responseFailure(response, stage) }
  }
  private static remaining(owner: string, revision: number, deadline: number, diagnostics: string = ''): number {
    if (owner !== LibraryAccountSession.owner() || revision !== LibraryAccountSession.revision) throw new Error('Library account owner changed')
    const remaining: number = deadline - Date.now()
    if (remaining <= 0) throw new HttpError(-1, 2300028,
      '图书馆身份会话接续超时，请稍后重新加载。 Library OAuth timeout', '', 'library-oauth', false, diagnostics)
    return Math.min(15000, remaining)
  }
  private static async loginOnce(owner: string): Promise<string> {
    const http = HttpUtil.getInstance()
    const revision: number = LibraryAccountSession.revision
    const deadline: number = Date.now() + 30000
    const entry = await http.getCampusSso(LibraryAccountSession.PAGE, {
      timeoutMs: LibraryAccountSession.remaining(owner, revision, deadline), freshConnection: false, fallbackCookies: ''
    })
    LibraryAccountSession.remaining(owner, revision, deadline, entry.diagnostics)
    if (LibraryAccountSession.authenticationRequired(entry)) throw LibraryAccountSession.responseFailure(entry, 'entry-authentication')
    const client: LibraryClient = { target: 'true', response_type: 'code', loginType: 'member', client_id: 'rfid', redirect_uri: 'https://opac.fudan.edu.cn/#/redirect' }
    const clientHeaders = LibraryAccountSession.headers(LibraryAccountSession.PAGE); clientHeaders['Content-Type'] = 'application/json'
    const response = await http.post(LibraryAccountSession.AUTH + '/open-api/openapi/oauth2/getClientParams', JSON.stringify(client), clientHeaders,
      LibraryAccountSession.remaining(owner, revision, deadline))
    LibraryAccountSession.remaining(owner, revision, deadline, response.diagnostics)
    const loginUrl = LibraryAccountSession.responseData<string>(response, 'client-parameters')
    if (typeof loginUrl !== 'string' || !FduAuthPolicy.isCampusUrl(loginUrl)) throw LibraryAccountSession.responseFailure(response, 'invalid-client-url')
    let login = await http.getCampusSso(loginUrl, {
      timeoutMs: LibraryAccountSession.remaining(owner, revision, deadline), freshConnection: false, fallbackCookies: ''
    })
    LibraryAccountSession.remaining(owner, revision, deadline, login.diagnostics)
    login = await LibraryAccountSession.completeReader(loginUrl, login, owner, revision, deadline)
    const callback: string = login.finalUrl ?? ''
    if (!LibraryAccountSession.callback(callback)) throw LibraryAccountSession.responseFailure(login, 'missing-oauth-callback')
    const query: string = callback.split('?')[1].split('#')[0]
    // OAuth results and grant/code requests are not repeatable business reads.
    // Explicitly disable native cache and connection-pool replay for each step.
    const verified = await http.get(LibraryAccountSession.AUTH + '/open-api/openapi/oauth2/authCallBack?' + query, undefined, LibraryAccountSession.headers(callback),
      LibraryAccountSession.remaining(owner, revision, deadline), false, false)
    LibraryAccountSession.remaining(owner, revision, deadline, verified.diagnostics)
    const token = LibraryAccountSession.responseData<LibraryCallback>(verified, 'oauth-callback').openToken
    if (!token) throw LibraryAccountSession.responseFailure(verified, 'missing-open-token')
    const headers = LibraryAccountSession.headers(callback); headers['openToken'] = token
    const url: string = LibraryAccountSession.AUTH + '/open-api/openapi/oauth2/authorize?' + LibraryAccountSession.PARAMETERS
    let authorizationResponse = await http.get(url, undefined, headers, LibraryAccountSession.remaining(owner, revision, deadline), false, false)
    LibraryAccountSession.remaining(owner, revision, deadline, authorizationResponse.diagnostics)
    let authorization = LibraryAccountSession.responseData<LibraryAuthorization>(authorizationResponse, 'authorize')
    if (!authorization.redirectUri) {
      const confirmation = await http.get(LibraryAccountSession.AUTH + '/open-api/openapi/oauth2/doConfirm?' + LibraryAccountSession.PARAMETERS, undefined, headers,
        LibraryAccountSession.remaining(owner, revision, deadline), false, false)
      LibraryAccountSession.remaining(owner, revision, deadline, confirmation.diagnostics)
      try { LibraryAccountParser.status(confirmation.data) }
      catch (error) { throw LibraryAccountSession.responseFailure(confirmation, 'confirm-authorization') }
      authorizationResponse = await http.get(url, undefined, headers, LibraryAccountSession.remaining(owner, revision, deadline), false, false)
      LibraryAccountSession.remaining(owner, revision, deadline, authorizationResponse.diagnostics)
      authorization = LibraryAccountSession.responseData<LibraryAuthorization>(authorizationResponse, 'authorize-after-confirmation')
    }
    if (!authorization.redirectUri) throw LibraryAccountSession.responseFailure(authorizationResponse, 'missing-authorization-redirect')
    return LibraryAccountSession.accept(authorization.redirectUri ?? '', owner, deadline, revision)
  }
  private static callback(url: string): boolean { return /^https:\/\/fdulib\.a-lsp\.com\/authServer\/auth\?/.test(url) && /[?&]authCode=/.test(url) && /[?&]ticket=/.test(url) }
  private static async completeReader(entry: string, initial: HttpResponse, owner: string, revision: number,
    deadline: number): Promise<HttpResponse> {
    let response = initial
    let hops: Record<string, string>[] = initial.hopHeaders ?? []
    let landing: string = response.finalUrl ?? CasTicket.finalUrl(entry, hops)
    response.finalUrl = landing
    const consumed: Set<string> = new Set<string>()
    for (let step: number = 0; !LibraryAccountSession.callback(landing); step++) {
      LibraryAccountSession.remaining(owner, revision, deadline, response.diagnostics)
      if (step >= 4) throw LibraryAccountSession.responseFailure(response, 'reader-form-limit')
      if (FduAuthPolicy.isIdUrl(landing)) {
        const expected: string = LibraryAccountSso.callbackFor(entry, landing, hops)
        const form = LibraryAccountSso.fromHtml(response.data, landing, expected)
        if (form === null) throw LibraryAccountSession.responseFailure(response, 'unexpected-reader-landing')
        const identity: string = form.method + '\n' + form.callback + '\n' +
          (form.method === 'POST' ? 'code:' + form.fields['code'] : 'ticket:' + form.fields['ticket'])
        if (consumed.has(identity)) throw LibraryAccountSession.responseFailure(response, 'repeated-reader-result')
        consumed.add(identity)
        const timeoutMs: number = LibraryAccountSession.remaining(owner, revision, deadline, response.diagnostics)
        response = form.method === 'POST' ? await HttpUtil.getInstance().postLibrarySso(form.target, form.fields, form.callback,
          { 'Authorization': '', 'Origin': FduAuthPolicy.ID_ORIGIN, 'Referer': landing }, timeoutMs) :
          await HttpUtil.getInstance().getCampusSso(form.target, { timeoutMs, freshConnection: false, fallbackCookies: '' })
        const formHop: Record<string, string> = {}; formHop['location'] = form.target
        hops = hops.concat([formHop], response.hopHeaders ?? [])
        landing = response.finalUrl ?? CasTicket.finalUrl(form.target, response.hopHeaders ?? [])
      } else {
        if (consumed.has('reader-form')) throw LibraryAccountSession.responseFailure(response, 'repeated-reader-form')
        consumed.add('reader-form')
        response = await LibraryAccountSession.submitForm(response,
          LibraryAccountSession.remaining(owner, revision, deadline, response.diagnostics))
        landing = response.finalUrl ?? ''
      }
      LibraryAccountSession.remaining(owner, revision, deadline, response.diagnostics)
    }
    response.finalUrl = landing
    return response
  }
  private static async submitForm(response: HttpResponse, timeoutMs: number): Promise<HttpResponse> {
    const url: string = response.finalUrl ?? ''
    if (FduAuthPolicy.origin(url) !== 'https://rwsjcas.fudan.edu.cn') throw LibraryAccountSession.responseFailure(response, 'unexpected-reader-landing')
    const form = CampusHtml.parse(response.data).findId('fm1')
    if (form === undefined || form.tag !== 'form') throw LibraryAccountSession.responseFailure(response, 'missing-reader-form')
    const action: string = FduAuthPolicy.resolve(form.attributes['action'] ?? '', url)
    if (FduAuthPolicy.origin(action) !== 'https://rwsjcas.fudan.edu.cn') throw LibraryAccountSession.responseFailure(response, 'invalid-reader-form-action')
    const fields: Record<string, string> = {}; LibraryAccountSession.inputs(form, fields)
    const names: string[] = ['username', 'password', 'domainName', 'source']
    for (const name of names) { const match = new RegExp('[?&]' + name + '=([^&#]*)').exec(action); if (match !== null) fields[name] = decodeURIComponent(match[1].replace(/\+/g, ' ')) }
    if (!fields['username'] || !fields['password']) throw LibraryAccountSession.responseFailure(response, 'incomplete-reader-form')
    if (fields['imgverifycode'] !== undefined) fields['imgverifycode'] = '******'
    const headers: Record<string, string> = {}; headers['Authorization'] = ''; headers['Origin'] = 'https://rwsjcas.fudan.edu.cn'; headers['Referer'] = url
    return HttpUtil.getInstance().postLibrarySso(action, fields, action, headers, timeoutMs)
  }
  private static inputs(node: CampusHtmlNode, fields: Record<string, string>): void {
    if (node.tag === 'input' && node.attributes['name']) fields[node.attributes['name']] = node.attributes['value'] ?? ''
    for (const child of node.children) LibraryAccountSession.inputs(child, fields)
  }
  static async accept(url: string, owner: string = LibraryAccountSession.owner(), deadline: number = Date.now() + 30000,
    revision: number = LibraryAccountSession.revision): Promise<string> {
    LibraryAccountSession.remaining(owner, revision, deadline)
    if (!/^https:\/\/opac\.fudan\.edu\.cn\/(?:#\/redirect\?|\?)/.test(url)) throw new Error('Invalid library OAuth redirect')
    if ((url.match(/[?&]code=/g) ?? []).length !== 1) throw new Error('Invalid library authorization code')
    const match = /[?&]code=([^&#]+)/.exec(url); if (match === null) throw new Error('Library authorization code is missing')
    const key: string = owner + '/' + decodeURIComponent(match[1])
    const joined = LibraryAccountSession.exchanges.get(key)
    if (joined !== undefined) return joined
    // Retain failed exchanges too: a lost response does not make a code reusable.
    const task = LibraryAccountSession.exchange(match[1], owner, deadline, revision)
    LibraryAccountSession.exchanges.set(key, task)
    return task
  }
  private static async exchange(code: string, owner: string, deadline: number, revision: number): Promise<string> {
    const headers: Record<string, string> = {}; headers['Authorization'] = ''; headers['Origin'] = 'https://opac.fudan.edu.cn'; headers['Referer'] = 'https://opac.fudan.edu.cn/'; headers['Accept'] = 'application/json'
    const response = await HttpUtil.getInstance().get(LibraryAccountSession.GATEWAY + '/alsp/open-api/openapi/oauth2/getToken?client_id=rfid&code=' + encodeURIComponent(decodeURIComponent(code)) + '&grant_type=authorization_code', undefined, headers,
      LibraryAccountSession.remaining(owner, revision, deadline), false, false)
    LibraryAccountSession.remaining(owner, revision, deadline, response.diagnostics)
    const token = LibraryAccountParser.data<LibraryToken>(response.data)
    if (!token.access_token || !Number.isFinite(token.expires_in) || owner !== LibraryAccountSession.owner()) throw new Error('Invalid or expired library token owner')
    LibraryAccountSession.token = token.access_token; LibraryAccountSession.expires = Date.now() + token.expires_in * 1000; LibraryAccountSession.tokenOwner = owner
    await CampusCookies.persist()
    LibraryAccountSession.remaining(owner, revision, deadline)
    return token.access_token
  }
  static async data(path: string, payload?: Object, mutation: boolean = false): Promise<string> {
    const owner = LibraryAccountSession.owner()
    let usedToken: string = ''
    const read = async (token: string): Promise<string> => {
      if (owner !== LibraryAccountSession.owner()) throw new Error('Library account changed')
      usedToken = token
      const headers: Record<string, string> = {}; headers['Authorization'] = ''; headers['access_token'] = token
      headers['Accept'] = 'application/json'; headers['Referer'] = 'https://opac.fudan.edu.cn/'; headers['Content-Type'] = 'application/json'
      const url = LibraryAccountSession.GATEWAY + '/alsp/open-api' + path
      try {
        const response = payload === undefined ? await HttpUtil.getInstance().get(url, undefined, headers) : await HttpUtil.getInstance().post(url, JSON.stringify(payload), headers)
        LibraryAccountParser.status(response.data); return response.data
      } catch (error) {
        if (error instanceof HttpError && (error.statusCode === 401 || error.statusCode === 403)) {
          const failure = new HttpError(-2, error.code, '图书馆读者会话已失效，请点击继续验证。 HTTP ' + error.statusCode, '')
          failure.diagnostics = error.diagnostics
          throw failure
        }
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
    const owner: string = this.owner()
    const reader = LibraryAccountParser.data<LibraryReader>(await this.read('/elib5/getReaderInfo'))
    if (owner !== this.owner()) throw new Error('Library account changed')
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
