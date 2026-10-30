import { NetworkProxy } from '../common/NetworkProxy'
/**
 * HTTP utility for network requests.
 * Uses HarmonyOS @kit.NetworkKit http module.
 *
 * Error model: a failed request THROWS HttpError. It deliberately does not
 * resolve with a synthetic `success: false` response — doing so made every
 * `.catch()` in the app unreachable, so network failures looked like empty
 * data instead of errors.
 */

import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { Constant } from '../common/Constant'
import { Person } from '../model/Person'
import { CampusCookies } from '../common/CampusCookies'
import { FduAuthPolicy } from '../model/FduAuth'
import { DormHistoryDiagnostics, DormHistoryQuery, DormHistoryTransfer } from '../model/DormHistoryDiagnostics'
import { RequestDiagnostics } from '../model/RequestDiagnostics'
import { DormHistoryReceiveDeadline } from './DormHistoryReceiveDeadline'
import { DormRequestPolicy } from '../model/DormRequestPolicy'
import { CampusSsoRedirect } from './CampusSsoRedirect'

/** Successful HTTP response body. */
export interface HttpResponse {
  code: number
  data: string
  headers: Record<string, string>
  success: boolean
  errorMessage: string
  /** Per-request redirect headers; safe when other requests run concurrently. */
  hopHeaders?: Record<string, string>[]
  /** Final URL of a manually followed campus redirect chain. */
  finalUrl?: string
  /** Metadata from this exact request chain, never headers, bodies or query values. */
  diagnostics?: string
}

/** Bounded, silent portal recovery. Cookies are scoped to the starting host;
 * sendCampus resolves the jar again and strips them on cross-host redirects. */
export interface CampusSsoReadOptions {
  timeoutMs: number
  freshConnection: boolean
  fallbackCookies: string
  historyQuery?: DormHistoryQuery
}

/** Shape of the backend's JSON error payload, when it sends one. */
interface ApiErrorBody {
  code: number
  message: string
}

/**
 * Raised for any non-2xx response or transport failure.
 * `statusCode` is the HTTP status, or -1 when the request never completed.
 * `code` is the business error code from the JSON body when present.
 */
export class HttpError extends Error {
  readonly statusCode: number
  readonly code: number
  readonly body: string
  readonly transportPhase: string
  readonly authenticationRecovery: boolean
  diagnostics: string = ''

  constructor(statusCode: number, code: number, message: string, body: string, transportPhase: string = '', authenticationRecovery: boolean = false,
    diagnostics: string = '') {
    super(message)
    this.name = 'HttpError'
    this.statusCode = statusCode
    this.code = code
    this.body = body
    this.transportPhase = transportPhase
    this.authenticationRecovery = authenticationRecovery
    this.diagnostics = diagnostics
  }

  /** True when the server rejected our credentials. */
  isUnauthorized(): boolean {
    return this.statusCode === 401
  }

  /** No completed HTTP response. The peer may already have received a body. */
  isNetworkFailure(): boolean {
    return this.statusCode === -1
  }
}

/**
 * Called on a 401 so the owner can refresh the token.
 * Return true if a new token is available and the request should be retried.
 */
export type UnauthorizedHandler = () => Promise<boolean>

/**
 * Supplies the bearer token for a request, given its full URL.
 * Routing by URL keeps a forum JWT off unrelated hosts and keeps /login free
 * of a stale Authorization header.
 */
export type TokenProvider = (url: string) => string

/** Account generation, stable across a same-account JWT refresh. */
export type TokenScopeProvider = (url: string) => number

function parseErrorCode(body: string): number {
  if (!body) return 0
  try {
    const parsed = JSON.parse(body) as ApiErrorBody
    if (parsed && typeof parsed.code === 'number') return parsed.code
  } catch (e) {
    // Body was not JSON (HTML error page, empty response, ...).
  }
  return 0
}

function parseErrorMessage(body: string, fallback: string): string {
  if (!body) return fallback
  try {
    const parsed = JSON.parse(body) as ApiErrorBody
    if (parsed && typeof parsed.message === 'string' && parsed.message.length > 0) {
      return parsed.message
    }
  } catch (e) {
    // Body was not JSON; fall through to the status-code fallback.
  }
  return fallback
}

/**
 * Render a thrown value into something a human can act on.
 *
 * This exists because `String(e)` on an ArkTS BusinessError yields the literal
 * text "[object Object]". Every transport failure therefore surfaced as
 * "网络请求失败：[object Object]", which says nothing about whether the cause
 * was a rejected TLS certificate, a DNS failure or a timeout -- and those need
 * completely different responses. The error CODE is the whole diagnostic, so
 * it has to survive the wrap.
 */
function describeThrown(e: Object): string {
  // Deliberately NOT `e instanceof Error`: ArkTS throws BusinessError values
  // that do not satisfy that check, so testing for it sent every one of them
  // down the String(e) path and back to "[object Object]". The properties are
  // read directly instead.
  const be = e as BusinessError
  const message: string = be !== null && be !== undefined ? be.message : ''
  const code: number = be !== null && be !== undefined ? be.code : 0
  if (message !== undefined && message !== null && message.length > 0) {
    return code !== undefined && code !== null && code !== 0
      ? message + ' (code ' + code + ')'
      : message
  }
  return String(e)
}

function thrownCode(e: Object): number {
  const code = (e as BusinessError)?.code
  return typeof code === 'number' && Number.isFinite(code) ? code : 0
}

/** Observe native progress without changing request lifetimes or disposing an in-flight request. */
class HttpTransferTrace {
  private started: number = Date.now()
  private budget: number
  private connectBudget: number = 0
  private readBudget: number = 0
  private sentBytes: number = 0
  private uploadBytes: number = 0
  private receivedBytes: number = 0
  private expectedBytes: number = 0
  private sendMs: number = -1
  private headerMs: number = -1
  private firstByteMs: number = -1
  private timing: http.PerformanceTiming | null = null
  private reused: boolean = false
  private proxied: boolean = false
  private connectionKnown: boolean = false
  private usingProxy: boolean = false
  private proxyPolicy: string = 'system'

  constructor(request: http.HttpRequest, budget: number) {
    this.budget = budget
    request.on('dataSendProgress', (progress: http.DataSendProgressInfo) => {
      this.sentBytes = Math.max(this.sentBytes, progress.sendSize)
      this.uploadBytes = Math.max(this.uploadBytes, progress.totalSize)
      if (progress.sendSize > 0 && this.sendMs < 0) this.sendMs = Date.now() - this.started
    })
    request.on('dataReceiveProgress', (progress: http.DataReceiveProgressInfo) => {
      this.receivedBytes = Math.max(this.receivedBytes, progress.receiveSize)
      this.expectedBytes = Math.max(this.expectedBytes, progress.totalSize)
      if (progress.receiveSize > 0 && this.firstByteMs < 0) this.firstByteMs = Date.now() - this.started
    })
  }

  headers(): void { if (this.headerMs < 0) this.headerMs = Date.now() - this.started }

  applied(options: http.HttpRequestOptions): void {
    this.connectBudget = options.connectTimeout ?? 0
    this.readBudget = options.readTimeout ?? 0
    this.usingProxy = typeof options.usingProxy === 'object' && options.usingProxy !== null
    this.proxyPolicy = this.usingProxy ? 'custom' : options.usingProxy === false ? 'disabled' : 'system'
  }

  complete(result: http.HttpResponse): void {
    this.timing = result.performanceTiming ?? null
    if (result.connectionExtraInfo) {
      this.connectionKnown = true
      this.reused = result.connectionExtraInfo.isReusedConnection
      this.proxied = result.connectionExtraInfo.isProxyConnection
    }
  }

  phase(code: number = 0): string {
    if (code === 2300005 || code === 2300006) return 'dns'
    if (code === 2300035 || code === 2300058 || code === 2300060) return 'tls'
    if (code === 2300007) return 'connect'
    if (this.headerMs >= 0) return 'response-body'
    return this.sentBytes > 0 ? 'await-response-headers' : 'connect-or-send'
  }

  details(): string {
    let result = 'budgetMs=' + String(this.budget) + '; connectBudgetMs=' + String(this.connectBudget) +
      '; readBudgetMs=' + String(this.readBudget) + '; sentBytes=' + String(this.sentBytes) +
      '; uploadBytes=' + String(this.uploadBytes) + '; receivedBytes=' + String(this.receivedBytes) +
      '; expectedBytes=' + String(this.expectedBytes) + '; sendMs=' + String(this.sendMs) +
      '; headerMs=' + String(this.headerMs) + '; firstByteMs=' + String(this.firstByteMs) +
      '; headersReceived=' + String(this.headerMs >= 0) + '; sendCompleted=' +
      String(this.uploadBytes > 0 && this.sentBytes >= this.uploadBytes) +
      '; usingProxy=' + (this.proxyPolicy === 'system' ? 'unknown' : String(this.usingProxy)) +
      '; proxyPolicy=' + this.proxyPolicy + '; timingAvailable=' + String(this.timing !== null)
    if (this.timing !== null) {
      result += '; dnsMs=' + String(this.timing.dnsTiming) + '; tcpMs=' + String(this.timing.tcpTiming) +
        '; tlsMs=' + String(this.timing.tlsTiming) + '; firstReceiveMs=' + String(this.timing.firstReceiveTiming)
    } else result += '; dnsMs=unknown; tcpMs=unknown; tlsMs=unknown'
    if (this.connectionKnown) result += '; reused=' + String(this.reused) + '; proxied=' + String(this.proxied)
    return result
  }
}

export class HttpUtil {
  private static activePortalReads: number = 0
  static requiresCampusLogin(url: string, hops: Record<string, string>[]): boolean {
    if (!FduAuthPolicy.isCampusUrl(url) || FduAuthPolicy.isIdUrl(url)) return false
    let finalUrl = url
    for (const headers of hops) {
      const location = headers['location'] ?? ''
      if (location) finalUrl = FduAuthPolicy.resolve(location, finalUrl)
    }
    return FduAuthPolicy.isIdUrl(finalUrl) || FduAuthPolicy.isWebVpnLoginUrl(finalUrl)
  }
  private static instance: HttpUtil | null = null

  /**
   * Campus web servers (jwc, id.fudan) reject the app's own Danta user agent
   * and serve a stripped page. Every request that scrapes or hand-shakes with
   * a university host presents this instead.
   */
  static readonly BROWSER_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

  /** Upstream FudanSession mobile identity, also used for zlapp SSO callbacks. */
  static readonly MOBILE_BROWSER_UA: string =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/145.0.0.0 Mobile Safari/537.36'

  private person: Person | null = null
  private unauthorizedHandler: UnauthorizedHandler | null = null
  private tokenProvider: TokenProvider | null = null
  private tokenScopeProvider: TokenScopeProvider | null = null

  /**
   * Headers of every response from the most recent `hop()`, in arrival order.
   *
   * Kept because the login flow needs a value (`lck`) that the server issues
   * ONLY as a `Location` header on an intermediate 302 of a redirect chain, and
   * this SDK exposes no other way to observe an intermediate response.
   */
  private lastHops: Record<string, string>[] = []

  private constructor() {}

  static getInstance(): HttpUtil {
    if (!HttpUtil.instance) {
      HttpUtil.instance = new HttpUtil()
    }
    return HttpUtil.instance
  }

  setPerson(person: Person): void {
    this.person = person
  }

  getPerson(): Person | null {
    return this.person
  }

  /**
   * Headers of every response of the last `hop()`, in arrival order — including
   * the intermediate 3xx responses, whose `location` is the only place Fudan's
   * CAS publishes `lck`.
   */
  lastHopHeaders(): Record<string, string>[] {
    return this.lastHops
  }

  /** Register the token-refresh hook used to recover from a 401. */
  setUnauthorizedHandler(handler: UnauthorizedHandler): void {
    this.unauthorizedHandler = handler
  }

  /**
   * Register the per-URL token source. When set it takes precedence over the
   * UIS `Person` token, so services with their own credentials (the forum JWT)
   * can coexist with the campus login.
   */
  setTokenProvider(provider: TokenProvider, scopeProvider?: TokenScopeProvider): void {
    this.tokenProvider = provider
    this.tokenScopeProvider = scopeProvider ?? null
  }

  private tokenScope(url: string): number {
    return this.tokenScopeProvider !== null ? this.tokenScopeProvider(url) : 0
  }

  /** Route retries belong to the account that started them, even when a
   * fallback or service authentication introduces another async boundary. */
  captureTokenScopeGuard(url: string): () => void {
    const scope: number = this.tokenScope(url)
    return (): void => { this.requireTokenScope(url, scope) }
  }

  private ownedToken(url: string, headers: Record<string, string>): string {
    const token: string = this.tokenProvider !== null ? this.tokenProvider(url) : ''
    const keys: string[] = Object.keys(headers).filter((key: string): boolean => key.toLowerCase() === 'authorization')
    return token.length > 0 && keys.length > 0 && keys.every((key: string): boolean => headers[key] === 'Bearer ' + token) ? token : ''
  }

  private requireTokenScope(url: string, scope: number): void {
    if (scope !== this.tokenScope(url)) throw new HttpError(401, 0, '茶楼账号已切换或退出，请重新加载。', '')
  }

  private async renewRejectedToken(url: string, method: http.RequestMethod, sentToken: string, scope: number): Promise<boolean> {
    if (!sentToken || this.tokenProvider === null || this.unauthorizedHandler === null) return false
    this.requireTokenScope(url, scope)
    const current: string = this.tokenProvider(url)
    if (!current) return false
    // Another request already refreshed this account. A late old 401 must not
    // rotate its new token again; only reads gain this additional retry route.
    if (sentToken !== current) return method === http.RequestMethod.GET
    let refreshed: boolean = false
    try { refreshed = await this.unauthorizedHandler() }
    catch (e) {
      this.requireTokenScope(url, scope)
      // The API already answered 401. A failure in its separate credential
      // recovery must not be mistaken for API-host connectivity and replayed
      // through another route by ForumNetwork.
      if (e instanceof HttpError) throw new HttpError(e.statusCode, e.code, e.message, e.body, e.transportPhase, true, e.diagnostics)
      throw new HttpError(-1, thrownCode(e), '网络请求失败：' + describeThrown(e), '', 'credential-recovery', true)
    }
    this.requireTokenScope(url, scope)
    return refreshed && this.tokenProvider(url).length > 0
  }

  private static remainingBudget(deadline: number, recovery: boolean = false, diagnostics: string = ''): number {
    const remaining: number = deadline - Date.now()
    if (remaining <= 0) throw new HttpError(-1, 2300028, '网络请求超时，请稍后重新加载。', '',
      recovery ? 'credential-recovery' : 'request-budget', recovery, diagnostics)
    return remaining
  }

  private buildHeaders(url: string, extra?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      // WebVPN's HTML login entry may leave JSON-negotiated requests waiting
      // without a redirect. Keep JSON for APIs, HTML for this exact entry.
      'Accept': FduAuthPolicy.isWebVpnLoginUrl(url) ?
        'text/html,application/xhtml+xml,*/*;q=0.8' : 'application/json',
      'User-Agent': Constant.USER_AGENT,
    }
    // Resolved per attempt, so a retry after a token refresh sends the NEW
    // token rather than replaying the stale Authorization header.
    if (this.tokenProvider !== null) {
      const token: string = this.tokenProvider(url)
      if (token.length > 0) {
        headers['Authorization'] = 'Bearer ' + token
      }
    }
    // Person stores campus cookies, not a bearer token. Only the URL-scoped
    // forum provider may supply Authorization; campus repositories set Cookie.
    if (extra) {
      const keys = Object.keys(extra)
      for (const key of keys) {
        headers[key] = extra[key]
      }
    }
    return this.nonEmptyHeaders(headers)
  }

  private nonEmptyHeaders(headers: Record<string, string>): Record<string, string> {
    const result: Record<string, string> = {}
    for (const key of Object.keys(headers)) {
      if (headers[key].length > 0) result[key] = headers[key]
    }
    return result
  }

  async get(url: string, params?: Record<string, string>, headers?: Record<string, string>, timeoutMs: number = 15000,
    freshConnection: boolean = false, allowRetry: boolean = true): Promise<HttpResponse> {
    let fullUrl = url
    if (params) {
      const queryParts: string[] = []
      const keys = Object.keys(params)
      for (const key of keys) {
        queryParts.push(encodeURIComponent(key) + '=' + encodeURIComponent(params[key]))
      }
      if (queryParts.length > 0) {
        const fragment: number = fullUrl.indexOf('#')
        const suffix: string = fragment >= 0 ? fullUrl.substring(fragment) : ''
        const address: string = fragment >= 0 ? fullUrl.substring(0, fragment) : fullUrl
        const separator: string = address.includes('?') ? /[?&]$/.test(address) ? '' : '&' : '?'
        fullUrl = address + separator + queryParts.join('&') + suffix
      }
    }
    return this.send(http.RequestMethod.GET, fullUrl, undefined, headers, allowRetry, timeoutMs, freshConnection)
  }

  async post(url: string, body?: string, headers?: Record<string, string>, timeoutMs: number = 15000): Promise<HttpResponse> {
    return this.request(http.RequestMethod.POST, url, body, headers, timeoutMs)
  }

  async put(url: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.request(http.RequestMethod.PUT, url, body, headers)
  }

  /**
   * DELETE with an optional body.
   * `DELETE /user/favorites` carries `{hole_id}` in the body rather than the
   * path, so a bodyless DELETE is not enough for the forum API.
   */
  async delete(url: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.request(http.RequestMethod.DELETE, url, body, headers)
  }

  /** PATCH with an optional body — e.g. the bodyless /holes/{id} view bump. */
  async patch(url: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.request(http.RequestMethod.PATCH, url, body, headers)
  }

  /**
   * One hop of a redirect chain, with NO following.
   *
   * The Fudan ID login cannot use `get()`: the `lck` token it needs is handed
   * out in the `Location` header of a 302 as a URL *fragment*, and fragments
   * are never sent back to the server. A client that follows redirects
   * transparently lands on the SPA shell having silently dropped the only
   * value the flow needs. `maxRedirects: 0` (see @ohos.net.http.d.ts) stops at
   * the 3xx so the header is still readable.
   *
   * Unlike the other methods this RESOLVES on 3xx instead of throwing — a
   * redirect is the expected, useful answer here. It still throws on a
   * transport failure, so "the network is down" stays distinguishable from
   * "the server stopped redirecting".
   */
  async hop(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    const httpRequest = http.createHttp()
    const trace = new HttpTransferTrace(httpRequest, 15000)
    const diagnosticEpoch: number = CampusCookies.generation()
    const diagnosticStarted: number = Date.now()
    let diagnosticStatus: number = 0
    let diagnosticCode: number = 0
    let failure: HttpError | null = null
    try {
      const merged: Record<string, string> = {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'User-Agent': HttpUtil.BROWSER_UA,
      }
      if (headers) {
        const keys = Object.keys(headers)
        for (const key of keys) {
          merged[key] = headers[key]
        }
      }
      // Collect EVERY response's headers, not just the last one.
      // `headersReceive` fires once per hop, which is the only way to observe an
      // intermediate 3xx: `maxRedirects: 0` does NOT hand back the 3xx, it fails
      // the whole request with error 2300047 and the error carries no Location.
      const hops: Record<string, string>[] = []
      httpRequest.on('headersReceive', (raw: Object) => {
        trace.headers()
        const rec = raw as Record<string, string>
        const lower: Record<string, string> = {}
        const recKeys = Object.keys(rec)
        for (const k of recKeys) {
          lower[k.toLowerCase()] = String(rec[k])
        }
        hops.push(lower)
      })

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: merged,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000,
        // A cached redirect can pair a spent login context with a newer Cookie.
        usingCache: false,
        // Follow the chain to its end: the hops are captured above, so stopping
        // early buys nothing -- and it is not possible anyway.
        maxRedirects: 10,
      }
      const applied = NetworkProxy.apply(options)
      trace.applied(applied)
      const result = await httpRequest.request(url, applied)
      trace.complete(result)
      this.lastHops = hops
      diagnosticStatus = result.responseCode

      const responseHeaders: Record<string, string> = {}
      if (result.header) {
        const headerKeys = Object.keys(result.header)
        for (const key of headerKeys) {
          responseHeaders[key.toLowerCase()] = String(result.header[key])
        }
      }
      const body: string = typeof result.result === 'string' ? result.result as string : ''
      const out: HttpResponse = {
        code: result.responseCode,
        data: body,
        headers: responseHeaders,
        success: result.responseCode >= 200 && result.responseCode < 400,
        errorMessage: '',
        hopHeaders: hops,
        diagnostics: RequestDiagnostics.record(diagnosticEpoch, CampusCookies.generation(), 'GET', url, diagnosticStatus, 0,
          Date.now() - diagnosticStarted, 'complete', trace.details()),
      }
      return out
    } catch (e) {
      diagnosticStatus = -1; diagnosticCode = thrownCode(e as Object)
      failure = new HttpError(-1, thrownCode(e), '网络请求失败：' + describeThrown(e), '', trace.phase(diagnosticCode))
      throw failure
    } finally {
      httpRequest.destroy()
      if (failure !== null) failure.diagnostics = RequestDiagnostics.record(diagnosticEpoch, CampusCookies.generation(), 'GET', url,
        diagnosticStatus, diagnosticCode, Date.now() - diagnosticStarted, trace.phase(diagnosticCode), trace.details()) || ''
    }
  }

  /** Authentication-only GET: shared CAS cookies may obtain another service's
   * ticket without credentials or a browser route. Ordinary get() still stops
   * at authentication, so a passive API response cannot open a login window. */
  async getCampusSso(url: string, options?: CampusSsoReadOptions): Promise<HttpResponse> {
    if (!FduAuthPolicy.isCampusUrl(url) || FduAuthPolicy.isIdUrl(url)) {
      throw new HttpError(0, 0, '无法访问该校园服务认证入口。', '')
    }
    const headers: Record<string, string> = {
      'User-Agent': FduAuthPolicy.origin(url) === 'https://zlapp.fudan.edu.cn' ? HttpUtil.MOBILE_BROWSER_UA : HttpUtil.BROWSER_UA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Content-Type': '',
    }
    if (options?.fallbackCookies) headers['Cookie'] = options.fallbackCookies
    return this.sendCampus(http.RequestMethod.GET, url, undefined, headers, false,
      options?.timeoutMs ?? (DormRequestPolicy.isDorm(url) ? DormRequestPolicy.WAIT_MS : 15000),
      true, options?.freshConnection ?? false, options?.historyQuery)
  }

  /** One-use authentication result, not a business POST. Only the observed
   * ecard broker callback is supported; the caller validates its source form
   * and redirect-chain evidence before invoking this bounded, non-retry path. */
  async postCampusSso(url: string, fields: Record<string, string>, options?: CampusSsoReadOptions): Promise<HttpResponse> {
    if (!HttpUtil.isWorkflowAuthResult(url)) {
      throw new HttpError(0, 0, '无法提交该校园服务认证结果。', '')
    }
    const parts: string[] = []
    for (const key of Object.keys(fields)) parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(fields[key]))
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
      'User-Agent': HttpUtil.BROWSER_UA
    }
    return this.sendCampus(http.RequestMethod.POST, url, parts.join('&'), headers, false,
      options?.timeoutMs ?? 15000, true, options?.freshConnection ?? false, options?.historyQuery)
  }

  private static isWorkflowAuthResult(url: string): boolean {
    return /^https:\/\/workflow1\.fudan\.edu\.cn(?::443)?\/site\/login\/cas-login\/?(?:[?#]|$)/i.test(url)
  }

  /** A library ID/reader result already bound by its caller to the callback
   * returned in this transaction. Never used for loan/reservation mutations. */
  async postLibrarySso(url: string, fields: Record<string, string>, expectedCallback: string,
    headers?: Record<string, string>, timeoutMs: number = 15000): Promise<HttpResponse> {
    if (!HttpUtil.isLibraryAuthResult(url) || url !== expectedCallback || url.includes('#')) {
      throw new HttpError(0, 0, '图书馆认证回调与当前会话不匹配，请重新加载。', '')
    }
    const parts: string[] = []
    for (const key of Object.keys(fields)) parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(fields[key]))
    const merged: Record<string, string> = {
      'Authorization': '', 'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
      'User-Agent': HttpUtil.BROWSER_UA
    }
    if (headers !== undefined) for (const key of Object.keys(headers)) merged[key] = headers[key]
    merged['Content-Type'] = 'application/x-www-form-urlencoded'
    return this.sendCampus(http.RequestMethod.POST, url, parts.join('&'), merged, false, timeoutMs, true)
  }

  private static isLibraryAuthResult(url: string): boolean {
    return FduAuthPolicy.origin(url) === 'https://rwsjcas.fudan.edu.cn'
  }

  /**
   * POST an `application/x-www-form-urlencoded` body.
   *
   * The last step of the Fudan ID login (`/idp/authCenter/authnEngine`) is a
   * form post, not JSON; sending it as JSON makes the server answer with the
   * login page again instead of a ticket, which looks like a credential
   * failure but is really a content-type mismatch.
   */
  async postForm(
    url: string,
    fields: Record<string, string>,
    headers?: Record<string, string>,
    timeoutMs: number = 15000
  ): Promise<HttpResponse> {
    const parts: string[] = []
    const keys = Object.keys(fields)
    for (const key of keys) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(fields[key]))
    }
    const merged: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
      'User-Agent': HttpUtil.BROWSER_UA,
    }
    if (headers) {
      const extraKeys = Object.keys(headers)
      for (const key of extraKeys) {
        merged[key] = headers[key]
      }
    }
    if (HttpUtil.isIdTokenExchange(url)) {
      return this.sendCampus(http.RequestMethod.POST, url, parts.join('&'), merged, false, timeoutMs, true)
    }
    return this.send(http.RequestMethod.POST, url, parts.join('&'), merged, false, timeoutMs)
  }

  private static isIdTokenExchange(url: string): boolean {
    return FduAuthPolicy.isIdUrl(url) && url.split(/[?#]/)[0].toLowerCase() ===
      FduAuthPolicy.ID_ORIGIN + '/idp/authcenter/authnengine'
  }

  /**
   * POST a `multipart/form-data` body.
   *
   * The bus endpoint takes its single parameter as a multipart form field —
   * upstream `lib/repository/fdu/bus_repository.dart` builds a Dio `FormData`,
   * which is multipart by default. A urlencoded body is NOT equivalent here:
   * the server parses the multipart part and ignores a urlencoded one, which
   * comes back as a page with no routes rather than as an error.
   *
   * The boundary is a fixed literal. It is not a security boundary, and a
   * constant one keeps the encoded body reproducible.
   */
  async postMultipart(
    url: string,
    fields: Record<string, string>,
    headers?: Record<string, string>,
    timeoutMs: number = 15000,
    freshConnection: boolean = false,
    historyQuery?: DormHistoryQuery
  ): Promise<HttpResponse> {
    const boundary: string = '----DanxiFormBoundaryNq3Kx8Tb1VwZa'
    const merged: Record<string, string> = {
      'Content-Type': 'multipart/form-data; boundary=' + boundary,
      'Accept': '*/*',
      'User-Agent': HttpUtil.BROWSER_UA,
    }
    if (headers) {
      const extraKeys = Object.keys(headers)
      for (const key of extraKeys) {
        merged[key] = headers[key]
      }
    }
    const body: string = HttpUtil.buildMultipartBody(boundary, fields)
    return this.send(http.RequestMethod.POST, url, body, merged, false, timeoutMs, freshConnection, historyQuery)
  }

  /**
   * Encode fields as a multipart/form-data body.
   *
   * Split out from the request so the encoding itself is unit-testable: the
   * server treats a urlencoded body as "no parameters" rather than as an error,
   * so a silent encoding mistake here would look like an empty timetable.
   */
  static buildMultipartBody(boundary: string, fields: Record<string, string>): string {
    const lines: string[] = []
    const keys = Object.keys(fields)
    for (const key of keys) {
      lines.push('--' + boundary)
      lines.push('Content-Disposition: form-data; name="' + key + '"')
      lines.push('')
      lines.push(fields[key])
    }
    lines.push('--' + boundary + '--')
    lines.push('')
    return lines.join('\r\n')
  }

  private async request(
    method: http.RequestMethod,
    url: string,
    body?: string,
    extraHeaders?: Record<string, string>,
    timeoutMs: number = 15000
  ): Promise<HttpResponse> {
    return this.send(method, url, body, extraHeaders, true, timeoutMs)
  }

  private async send(
    method: http.RequestMethod,
    url: string,
    body: string | undefined,
    extraHeaders: Record<string, string> | undefined,
    allowRetry: boolean,
    timeoutMs: number = 15000,
    freshConnection: boolean = false,
    historyQuery?: DormHistoryQuery
  ): Promise<HttpResponse> {
    if (FduAuthPolicy.isCampusUrl(url) && !FduAuthPolicy.isIdUrl(url)) {
      return this.sendCampus(method, url, body, extraHeaders, allowRetry, timeoutMs, false, freshConnection, historyQuery)
    }
    const httpRequest = http.createHttp()
    const headers = this.buildHeaders(url, extraHeaders)
    const sentToken: string = this.ownedToken(url, headers)
    const tokenScope: number = this.tokenScope(url)
    const hops: Record<string, string>[] = []
    const cookieEpoch = CampusCookies.generation()
    const diagnosticStarted: number = Date.now()
    const trace = new HttpTransferTrace(httpRequest, timeoutMs)
    let diagnosticStatus: number = 0
    let diagnosticCode: number = 0
    let failure: HttpError | null = null
    let completed: HttpResponse | null = null

    try {
      const browserCookies = await CampusCookies.read(url)
      if (sentToken) this.requireTokenScope(url, tokenScope)
      if (browserCookies) headers['Cookie'] = browserCookies
      const remaining: number = HttpUtil.remainingBudget(diagnosticStarted + timeoutMs)
      httpRequest.on('headersReceive', (raw: Object) => {
        trace.headers()
        const source = raw as Record<string, string>
        const row: Record<string, string> = {}
        for (const key of Object.keys(source)) row[key.toLowerCase()] = String(source[key])
        hops.push(row)
      })
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: remaining,
        readTimeout: remaining,
        // An explicit refresh must bypass the native cache too, otherwise a
        // stale public document could be stamped with a new application TTL.
        usingCache: allowRetry && (method === http.RequestMethod.GET || method === http.RequestMethod.HEAD) &&
          !FduAuthPolicy.isCampusUrl(url) && !Object.keys(headers).some((key: string): boolean =>
            /^(?:authorization|cookie|access_token|opentoken)$/i.test(key) && headers[key].length > 0) &&
          !/\bno-cache\b|\bno-store\b/i.test(headers['Cache-Control'] ?? headers['cache-control'] ?? ''),
      }
      if (body !== undefined && body.length > 0) {
        options.extraData = body
      }

      // API26 may resend a body after a reused socket closes without headers.
      // Keep pooling for ordinary reads; non-repeatable requests start fresh.
      if (freshConnection || !allowRetry ||
        (method !== http.RequestMethod.GET && method !== http.RequestMethod.HEAD)) options.reuseConnections = false

      const applied = NetworkProxy.apply(options)
      trace.applied(applied)
      const result = await httpRequest.request(url, applied)
      trace.complete(result)
      diagnosticStatus = result.responseCode
      const responseHeaders: Record<string, string> = {}
      if (result.header) {
        const headerKeys = Object.keys(result.header)
        for (const key of headerKeys) {
          responseHeaders[key.toLowerCase()] = String(result.header[key])
        }
      }

      const responseData: string = typeof result.result === 'string' ? result.result as string : ''
      const status: number = result.responseCode
      await CampusCookies.absorb(url, hops.length > 0 ? hops : [responseHeaders], cookieEpoch)
      if (status >= 200 && status < 300 && (HttpUtil.requiresCampusLogin(url, hops) ||
        (FduAuthPolicy.isCampusUrl(url) && !FduAuthPolicy.isIdUrl(url) &&
          FduAuthPolicy.isLoginDocument(responseData)))) {
        throw new HttpError(-2, 0, '校园服务会话已失效，需要继续身份验证。', '')
      }
      // ArkUI-X has no automatic native cookie jar. A redirect may rotate a
      // session before its last request fails. Retry a read once ONLY if that
      // response actually supplied a new, scoped cookie. Never replay POSTs.
      if (allowRetry && method === http.RequestMethod.GET && status >= 500 &&
        FduAuthPolicy.isCampusUrl(url) && !FduAuthPolicy.isIdUrl(url)) {
        const updatedCookies = await CampusCookies.read(url)
        if (updatedCookies && updatedCookies !== headers['Cookie']) {
          return this.send(method, url, body, extraHeaders, false,
            HttpUtil.remainingBudget(diagnosticStarted + timeoutMs), freshConnection)
        }
      }

      if (status >= 200 && status < 300) {
        const ok: HttpResponse = {
          code: status,
          data: responseData,
          headers: responseHeaders,
          success: true,
          errorMessage: '',
          hopHeaders: hops,
        }
        completed = ok
        return ok
      }

      // Credentials rejected: give the owner one chance to refresh the token.
      // Refresh only a request owned by the token provider. In particular,
      // /refresh itself and campus requests must never recursively refresh.
      if (status === 401 && allowRetry && await this.renewRejectedToken(url, method, sentToken, tokenScope)) {
        this.requireTokenScope(url, tokenScope)
        return this.send(method, url, body, extraHeaders, false,
          HttpUtil.remainingBudget(diagnosticStarted + timeoutMs, true), freshConnection)
      }

      throw new HttpError(
        status,
        parseErrorCode(responseData),
        parseErrorMessage(responseData, 'HTTP ' + status),
        responseData
      )
    } catch (e) {
      diagnosticStatus = e instanceof HttpError ? e.statusCode : -1
      diagnosticCode = e instanceof HttpError ? e.code : thrownCode(e as Object)
      if (e instanceof HttpError) {
        failure = e
        throw e
      }
      // Transport-level failure: no usable status code.
      failure = new HttpError(-1, thrownCode(e), '网络请求失败：' + describeThrown(e), '', trace.phase(diagnosticCode))
      throw failure
    } finally {
      httpRequest.destroy()
      const record = RequestDiagnostics.record(cookieEpoch, CampusCookies.generation(), String(method), url, diagnosticStatus,
        diagnosticCode, Date.now() - diagnosticStarted, diagnosticStatus >= 200 && diagnosticStatus < 400 ? 'complete' :
          diagnosticStatus === -2 ? 'authentication' : diagnosticStatus === -1 ? trace.phase(diagnosticCode) : 'http-error', trace.details()) || ''
      if (completed !== null) completed.diagnostics = record
      if (failure !== null) failure.diagnostics = (failure.diagnostics + (failure.diagnostics && record ? '\n\n' : '') + record).slice(0, 12000)
    }
  }

  /** Manual campus redirects import cookies before the next request and pick
   * the next host/path's jar. Native automatic redirects reuse the first
   * request's Cookie header before our final-response callback can rotate it. */
  private async sendCampus(method: http.RequestMethod, startUrl: string, body: string | undefined,
    extraHeaders: Record<string, string> | undefined, allowRetry: boolean, timeoutMs: number,
    allowSso: boolean = false, freshConnection: boolean = false, historyQuery?: DormHistoryQuery): Promise<HttpResponse> {
    const epoch = CampusCookies.generation()
    const deadline = Date.now() + timeoutMs
    const tokenScope: number = this.tokenScope(startUrl)
    let tokenOwned: boolean = false
    let url = startUrl
    let currentMethod = method
    let currentBody = body
    let previousCookie = ''
    const allHops: Record<string, string>[] = []
    let chainDiagnostics: string = ''
    for (let step: number = 0; step < 8; step++) {
      if (epoch !== CampusCookies.generation()) throw new HttpError(-2, 0, '校园账号已切换，请重新加载。', '')
      if (tokenOwned) this.requireTokenScope(startUrl, tokenScope)
      let remaining: number = deadline - Date.now()
      if (remaining <= 0) throw new HttpError(-1, 2300028, '校园服务连接超时，请稍后重试。', '', 'connect-or-send', false, chainDiagnostics)
      const headers = this.buildHeaders(startUrl, extraHeaders)
      // A body-free campus GET is not a JSON submission, including its first
      // hop. Authentication callbacks may return either JSON or HTML.
      if (currentBody === undefined) headers['Content-Type'] = ''
      if (step > 0) {
        // Do not forward bearer credentials, explicit cookies or private
        // request metadata to another host. Cookies are resolved afresh below.
        headers['Cookie'] = ''
        if (FduAuthPolicy.origin(url) !== FduAuthPolicy.origin(startUrl)) {
          headers['Authorization'] = ''
          headers['Referer'] = ''
          // Reader tokens belong to their exact service origin as well.
          for (const key of Object.keys(headers)) {
            if (/^(?:access_token|opentoken)$/i.test(key)) headers[key] = ''
          }
        }
        if (currentBody === undefined) headers['Content-Type'] = ''
      }
      const sentToken: string = this.ownedToken(startUrl, headers)
      if (step === 0) tokenOwned = sentToken.length > 0
      const cookie = await CampusCookies.read(url)
      if (epoch !== CampusCookies.generation()) throw new HttpError(-2, 0, '校园账号已切换，请重新加载。', '')
      if (tokenOwned) this.requireTokenScope(startUrl, tokenScope)
      if (cookie) headers['Cookie'] = cookie
      if (step === 0) previousCookie = headers['Cookie'] ?? ''
      remaining = HttpUtil.remainingBudget(deadline, false, chainDiagnostics)
      const request = http.createHttp()
      const trace = new HttpTransferTrace(request, remaining)
      let failure: HttpError | null = null
      const received: Record<string, string>[] = []
      let sentBytes: number = 0
      let sendElapsedMs: number = 0
      let firstSendElapsedMs: number = 0
      let uploadBytes: number = 0
      const historyRead: boolean = startUrl.split(/[?#]/)[0] ===
        'https://my.fudan.edu.cn/data_tables/ykt_xszsqyydqk.json' || historyQuery?.stage === 'portal-session'
      const portalRead: boolean = FduAuthPolicy.origin(url) === 'https://my.fudan.edu.cn'
      const transfer = new DormHistoryTransfer()
      const receiveDeadline: DormHistoryReceiveDeadline | null = historyRead && currentMethod === http.RequestMethod.POST ?
        new DormHistoryReceiveDeadline(remaining) : null
      transfer.query = historyQuery?.id ?? 0; transfer.attempt = historyQuery?.attempt ?? 0
      transfer.stage = historyQuery?.stage ?? 'query'
      transfer.startedAt = deadline - timeoutMs; transfer.budgetMs = timeoutMs; transfer.fresh = freshConnection
      transfer.peersAtStart = HttpUtil.activePortalReads
      if (portalRead) HttpUtil.activePortalReads++
      if (historyRead) request.on('dataSendProgress', (progress: http.DataSendProgressInfo) => {
        if (progress && progress.sendSize > sentBytes) {
          if (sentBytes === 0) firstSendElapsedMs = Math.max(0, Date.now() - transfer.startedAt)
          sentBytes = progress.sendSize
          uploadBytes = progress.totalSize
          sendElapsedMs = Math.max(0, Date.now() - transfer.startedAt)
          receiveDeadline?.upload(sentBytes, uploadBytes)
        }
      })
      request.on('headersReceive', (raw: Object) => {
        trace.headers()
        const source = raw as Record<string, string>
        const row: Record<string, string> = {}
        for (const key of Object.keys(source)) row[key.toLowerCase()] = String(source[key])
        received.push(row)
        receiveDeadline?.headers()
      })
      let status: number = 0
      let responseData = ''
      let responseHeaders: Record<string, string> = {}
      let redirectError: boolean = false
      try {
        const options: http.HttpRequestOptions = {
          method: currentMethod, header: this.nonEmptyHeaders(headers), expectDataType: http.HttpDataType.STRING,
          connectTimeout: remaining, readTimeout: remaining, usingCache: false, maxRedirects: 0,
        }
        if (allowSso && currentMethod === http.RequestMethod.POST &&
          (HttpUtil.isWorkflowAuthResult(url) || HttpUtil.isLibraryAuthResult(url))) {
          // API22+ stops at REDIRECTION and returns the actual 3xx. max=0
          // throws 2300047 before that interceptor on the supported runtime.
          if (!CampusSsoRedirect.attach(request)) throw new HttpError(0, 0, '无法读取校园认证跳转状态，请稍后重试。', '')
          options.maxRedirects = 1
        }
        // Match upstream Dart IO's HTTP/1.1 direct connection for zlapp.
        // Scope to this host; do not alter WebVPN routing or other hosts.
        if (FduAuthPolicy.origin(url) === 'https://zlapp.fudan.edu.cn' || FduAuthPolicy.origin(url) === 'https://my.fudan.edu.cn') {
          options.usingProtocol = http.HttpProtocol.HTTP1_1
          options.usingProxy = false
          // Bus and portal handshakes share the original remaining budget too;
          // a separate five-second cap can expire before any upload begins.
          options.connectTimeout = remaining
        }
        if (currentBody !== undefined && currentBody.length > 0) options.extraData = currentBody
        // API 26 keeps idle connections for 118 seconds by default. Only this
        // read-only history retry bypasses the connection that stalled.
        if (historyRead) {
          options.reuseConnections = !freshConnection
          options.inactivityMs = 5000
        }
        if (DormRequestPolicy.isDorm(startUrl)) options.reuseConnections = !freshConnection
        if (freshConnection || !allowRetry ||
          (method !== http.RequestMethod.GET && method !== http.RequestMethod.HEAD)) options.reuseConnections = false
        try {
          const applied = NetworkProxy.apply(options)
          trace.applied(applied)
          const operation: Promise<http.HttpResponse> = request.request(url, applied)
          const result: http.HttpResponse = receiveDeadline === null ? await operation :
            await Promise.race([operation, receiveDeadline.promise])
          trace.complete(result)
          status = result.responseCode
          transfer.status = status
          const timing = result.performanceTiming
          if (historyRead && timing) {
            transfer.timingKnown = true
            transfer.dnsMs = timing.dnsTiming; transfer.tcpMs = timing.tcpTiming
            transfer.tlsMs = timing.tlsTiming; transfer.firstReceiveMs = timing.firstReceiveTiming
          }
          const connection = result.connectionExtraInfo
          if (historyRead && connection) {
            transfer.connectionKnown = true
            transfer.reused = connection.isReusedConnection; transfer.proxied = connection.isProxyConnection
          }
          responseData = typeof result.result === 'string' ? result.result as string : ''
          if (result.header) {
            for (const key of Object.keys(result.header)) responseHeaders[key.toLowerCase()] = String(result.header[key])
          }
        } catch (error) {
          transfer.status = -1
          transfer.code = thrownCode(error as Object)
          // API 23+ reports a disabled redirect as 2300047, but the official
          // headersReceive event already supplied its Location and Set-Cookie.
          if (thrownCode(error as Object) !== 2300047 || received.length === 0 ||
            !received[received.length - 1]['location']) throw error as Error
          redirectError = true
          responseHeaders = received[received.length - 1]
          const receivedStatus = Number(responseHeaders[':status'] ?? responseHeaders['status'] ?? '0')
          status = receivedStatus >= 300 && receivedStatus < 400 ? receivedStatus : 0
        }
      } catch (error) {
        if (error instanceof HttpError) { failure = error; throw error }
        if (historyRead && thrownCode(error as Object) === 2300028) {
          // A partial response may already rotate the session. Preserve those
          // scoped cookies before the next read, even when its body times out.
          if (received.length > 0) await CampusCookies.absorb(url, received, epoch)
          const elapsed: number = Math.max(0, Date.now() - transfer.startedAt)
          const sendCompleted: boolean = uploadBytes > 0 && sentBytes >= uploadBytes
          const phase: string = received.length > 0 ? 'response-body' : sendCompleted ? 'await-response-headers' : 'connect-or-response'
          console.info('[DormHistoryTransport] phase=' + phase + ' fresh=' + String(freshConnection) +
            ' elapsedMs=' + String(elapsed) + ' totalBudgetMs=' + String(timeoutMs) +
            ' sentBytes=' + String(sentBytes) + ' sendElapsedMs=' + String(sendElapsedMs))
          failure = new HttpError(-1, 2300028, '用电记录读取超时，请稍后重新加载。' +
            ' Operation timeout (code 2300028; phase=' + phase + '; fresh=' + String(freshConnection) +
            '; elapsedMs=' + String(elapsed) + '; totalBudgetMs=' + String(timeoutMs) +
            '; sentBytes=' + String(sentBytes) + '; sendElapsedMs=' + String(sendElapsedMs) +
            '; uploadBytes=' + String(uploadBytes) + '; sendCompleted=' + String(sendCompleted) +
            '; firstSendElapsedMs=' + String(firstSendElapsedMs) + '; receiveBudgetMs=' + String(receiveDeadline?.budgetMs ?? 0) +
            '; timeoutSource=' + (receiveDeadline?.expired ? 'receive-deadline' : 'native') + ')', '', phase)
          throw failure
        }
        if (thrownCode(error as Object) === 2300028 && FduAuthPolicy.origin(startUrl) === 'https://zlapp.fudan.edu.cn' &&
          (/\/fudanelec\//.test(startUrl) || /fudanelec%2F/i.test(startUrl))) {
          const phase: string = allowSso ? '身份会话接续' : '余额读取'
          const progress: string = received.length > 0 ? '已收到响应头，正文未能及时读完' : '连接或等待服务响应未完成'
          console.info('[DormTransport] phase=' + (allowSso ? 'sso' : 'balance') + ' headersReceived=' + String(received.length > 0))
          failure = new HttpError(-1, 2300028, '寝室电费' + phase + '超时（' + progress + '；code 2300028），请稍后重新加载。' +
            ' Operation timeout (phase=' + (allowSso ? 'dorm-sso' : 'dorm-balance') +
            '; elapsedMs=' + String(Date.now() - transfer.startedAt) + '; totalBudgetMs=' + String(timeoutMs) +
            '; redirectHop=' + String(step) + '; headersReceived=' + String(received.length > 0) + ')',
            '', allowSso ? 'dorm-sso' : 'dorm-balance')
          throw failure
        }
        failure = new HttpError(-1, thrownCode(error as Object), '网络请求失败：' + describeThrown(error as Object), '', trace.phase(transfer.code))
        throw failure
      } finally {
        receiveDeadline?.cancel()
        request.destroy()
        if (portalRead) HttpUtil.activePortalReads--
        const record = RequestDiagnostics.record(epoch, CampusCookies.generation(), String(currentMethod), url,
          transfer.status, transfer.code, Date.now() - transfer.startedAt,
          redirectError ? 'redirect' : transfer.code !== 0 ? trace.phase(transfer.code) :
            status >= 200 && status < 300 ? 'complete' : 'http-error', trace.details()) || ''
        chainDiagnostics = (chainDiagnostics + (chainDiagnostics && record ? '\n\n' : '') + record).slice(-12000)
        if (failure !== null) failure.diagnostics = chainDiagnostics
        if (historyRead) {
          transfer.elapsedMs = Math.max(0, Date.now() - transfer.startedAt)
          transfer.sentBytes = sentBytes; transfer.uploadBytes = uploadBytes; transfer.sendElapsedMs = sendElapsedMs
          transfer.headersReceived = received.length > 0
          transfer.receiveBudgetMs = receiveDeadline?.budgetMs ?? 0
          transfer.timeoutSource = transfer.code === 2300028 ? (receiveDeadline?.expired ? 'receive-deadline' : 'native') : ''
          transfer.phase = redirectError ? 'redirect' : transfer.code === 2300028 ? (received.length > 0 ? 'response-body' :
            uploadBytes > 0 && sentBytes >= uploadBytes ? 'await-response-headers' : sentBytes > 0 ? 'upload-incomplete' : 'connect-or-send') :
            transfer.code !== 0 ? 'transport-error' : status >= 200 && status < 300 ? 'complete' : 'http-error'
          DormHistoryDiagnostics.record(epoch, CampusCookies.generation(), transfer)
        }
      }
      const hopRows = received.length > 0 ? received : [responseHeaders]
      await CampusCookies.absorb(url, hopRows, epoch)
      for (const row of hopRows) allHops.push(row)
      if (epoch !== CampusCookies.generation()) throw new HttpError(-2, 0, '校园账号已切换，请重新加载。', '')
      const location = responseHeaders['location'] ?? received[received.length - 1]?.['location'] ?? ''
      if (location && (redirectError || (status >= 300 && status < 400))) {
        const next = FduAuthPolicy.resolve(location, url)
        if (!FduAuthPolicy.isCampusUrl(next)) throw new HttpError(0, 0, '校园服务返回了不受支持的跳转。', '', '', false, chainDiagnostics)
        // A passive data read stops at authentication. Only verifyService may
        // enter the official browser; downloading its SPA cannot authenticate.
        if (!allowSso && (FduAuthPolicy.isIdUrl(next) || FduAuthPolicy.isWebVpnLoginUrl(next))) {
          throw new HttpError(-2, 0, '校园服务需要身份验证，请点击继续验证。', '', '', false, chainDiagnostics)
        }
        if (currentMethod !== http.RequestMethod.GET && currentMethod !== http.RequestMethod.HEAD) {
          // Never replay a POST. Known 303/301/302 becomes GET; 307/308 is
          // rejected. The one-use ID token endpoint may omit redirect status
          // in SDK 2300047: follow that exact endpoint's Location as GET only.
          const tokenRedirect = allowSso && currentMethod === http.RequestMethod.POST &&
            HttpUtil.isIdTokenExchange(url) && redirectError && status === 0
          if (status !== 303 && status !== 301 && status !== 302 && !tokenRedirect) {
            throw new HttpError(status || 0, 2300047, '校园服务请求需要重新加载，请稍后重试。', '', '', false, chainDiagnostics)
          }
          currentMethod = http.RequestMethod.GET
          currentBody = undefined
        }
        url = next
        continue
      }
      // A server/WAF error page is not evidence of an expired session, even
      // when its HTML mentions login. Actual auth redirects stop above.
      if (!allowSso && status >= 200 && status < 300 && (HttpUtil.requiresCampusLogin(startUrl, allHops) ||
        (FduAuthPolicy.isLoginDocument(responseData) && !FduAuthPolicy.isLifeCodeDocument(url, responseData)))) {
        throw new HttpError(-2, 0, '校园服务需要身份验证，请点击继续验证。', '', '', false, chainDiagnostics)
      }
      if (allowRetry && method === http.RequestMethod.GET && status >= 500) {
        const updated = await CampusCookies.read(startUrl)
        if (updated && updated !== previousCookie) return this.sendCampus(method, startUrl, body, extraHeaders, false,
          HttpUtil.remainingBudget(deadline, false, chainDiagnostics), allowSso, freshConnection, historyQuery)
      }
      if (status >= 200 && status < 300) return {
        code: status, data: responseData, headers: responseHeaders, success: true, errorMessage: '', hopHeaders: allHops,
        finalUrl: url, diagnostics: chainDiagnostics,
      }
      if (status === 401 && allowRetry && await this.renewRejectedToken(startUrl, method, sentToken, tokenScope)) {
        this.requireTokenScope(startUrl, tokenScope)
        return this.sendCampus(method, startUrl, body, extraHeaders, false,
          HttpUtil.remainingBudget(deadline, true, chainDiagnostics), allowSso, freshConnection, historyQuery)
      }
      throw new HttpError(status, parseErrorCode(responseData), parseErrorMessage(responseData, 'HTTP ' + status), responseData, '', false, chainDiagnostics)
    }
    throw new HttpError(-1, 2300047, '校园服务跳转次数过多，请稍后重试。', '', '', false, chainDiagnostics)
  }
}
