import { http } from '@kit.NetworkKit'
import { HttpUtil, HttpError, HttpResponse } from '../util/HttpUtil'
import { FduRepository } from '../repository/FduRepository'
import { ForumRoute } from './ForumRoute'
import { AppLanguage } from './AppLanguage'
import { Constant } from './Constant'
import { ForumRouteContext, ForumRouteHints } from './ForumRouteHints'

class ForumConnectionState {
  origin: string = ''
  direct: boolean | undefined = undefined
  checkedAt: number = 0
  checking: Promise<boolean> | null = null
  reading: Promise<boolean> | null = null
  readAuthentication: boolean = false
  readOwnerGuard: (() => void) | null = null
  readFailure: HttpError | null = null
  failedAt: number = 0
  failedCookies: string = ''
  failedAuthentication: boolean = false
  failedOwnerGuard: (() => void) | null = null
}

/** Reads select a route using their actual GET, never a separate root probe.
 * Writes retain the anonymous reachability check and are never replayed.
 * Each host/network has one initial read exploration and a short failure delay.
 */
export class ForumNetwork {
  private static instance: ForumNetwork | null = null
  private http: HttpUtil = HttpUtil.getInstance()
  private connections: ForumConnectionState[] = []
  private contextLoaded: boolean = false
  private networkId: number = -1
  private proxyAddress: string = ''
  private contextGeneration: number = -1

  static getInstance(): ForumNetwork {
    if (ForumNetwork.instance === null) ForumNetwork.instance = new ForumNetwork()
    return ForumNetwork.instance
  }

  async get(url: string, params?: Record<string, string>, headers?: Record<string, string>,
    timeoutMs: number = 15000, allowAuthentication: boolean = true): Promise<HttpResponse> {
    return this.send(http.RequestMethod.GET, url, undefined, params, headers, timeoutMs, allowAuthentication)
  }

  /** Explicit application action carried over GET, such as AI regeneration.
   * Select its route first; an uncertain result must never dispatch it again. */
  async getOnce(url: string, params?: Record<string, string>, headers?: Record<string, string>,
    timeoutMs: number = 15000, allowAuthentication: boolean = true): Promise<HttpResponse> {
    return this.send(http.RequestMethod.GET, url, undefined, params, headers, timeoutMs, allowAuthentication, false)
  }

  async post(url: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.send(http.RequestMethod.POST, url, body, undefined, headers)
  }

  async put(url: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.send(http.RequestMethod.PUT, url, body, undefined, headers)
  }

  async patch(url: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.send(http.RequestMethod.PATCH, url, body, undefined, headers)
  }

  async delete(url: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.send(http.RequestMethod.DELETE, url, body, undefined, headers)
  }

  private connection(origin: string): ForumConnectionState {
    const known = this.connections.find((row: ForumConnectionState): boolean => row.origin === origin)
    if (known !== undefined) return known
    const created = new ForumConnectionState()
    created.origin = origin
    this.connections.push(created)
    return created
  }

  private syncRouteContext(): ForumRouteContext {
    const context: ForumRouteContext = ForumRouteHints.context()
    const proxy: string = context.proxyAddress
    const network: number = context.available ? context.networkId : this.networkId
    if (this.contextLoaded && (context.generation !== this.contextGeneration ||
      network !== this.networkId || proxy !== this.proxyAddress)) this.connections = []
    this.contextLoaded = true; this.networkId = network; this.proxyAddress = proxy
    this.contextGeneration = context.generation
    return context
  }

  private async canConnectDirectly(state: ForumConnectionState): Promise<boolean> {
    // Successful paths remain usable for five minutes; failed paths are
    // reconsidered sooner so switching to campus Wi-Fi recovers naturally.
    const ttl: number = state.direct === true ? 300000 : 60000
    if (state.direct !== undefined && Date.now() - state.checkedAt < ttl) return state.direct
    if (state.checking !== null) return state.checking
    const pending: Promise<boolean> = this.probe(state.origin)
    state.checking = pending
    try {
      state.direct = await pending
      state.checkedAt = Date.now()
      return state.direct
    } finally { if (state.checking === pending) state.checking = null }
  }

  private async probe(origin: string): Promise<boolean> {
    // Some native DNS/internal failures outlive HttpRequestOptions' timeout.
    // This wall-clock budget applies only to the anonymous GET probe. The
    // late native request still disposes itself in HttpUtil's finally, and
    // its completion cannot replace the route already chosen below.
    let timer: number = 0
    const deadline = new Promise<boolean>((resolve) => {
      timer = setTimeout(() => resolve(false), 1500)
    })
    // The trusted origin's root carries neither JWT nor email/password.
    // Probe before a login POST so an unavailable auth host is never tried
    // merely because a different host's content request succeeded.
    const outcome: Promise<boolean> = this.http.get(origin, undefined, undefined, 1500).then(
      (): boolean => true,
      (error: Object): boolean => {
        // HTTP errors prove the host is reachable. Never route around a
        // rejected certificate or infer that HTTP 401/500 is a network failure.
        return !ForumNetwork.isConnectionFailure(error)
      })
    try {
      return await Promise.race([outcome, deadline])
    } finally { clearTimeout(timer) }
  }

  static isConnectionFailure(error: Object): boolean {
    // API 26's native HTTP request reports 2300999 (Internal error) when a
    // direct host produces no HTTP response on the affected network. It is
    // not proof of reachability. Explicit SSL/certificate codes remain out
    // of this list; an ambiguous write is still never replayed by send().
    return error instanceof HttpError && !error.authenticationRecovery && error.isNetworkFailure() &&
      [0, 2300005, 2300006, 2300007, 2300028, 2300052, 2300055, 2300056, 2300999].includes(error.code)
  }

  private async send(method: http.RequestMethod, url: string, body: string | undefined,
    params: Record<string, string> | undefined, headers: Record<string, string> | undefined,
    timeoutMs: number = 15000, allowAuthentication: boolean = true, allowReadRecovery: boolean = true): Promise<HttpResponse> {
    const guard: () => void = this.http.captureTokenScopeGuard(url)
    const translated = ForumRoute.proxyUrl(url)
    if (!translated || AppStorage.get<boolean>(Constant.KEY_USE_WEBVPN) === false) {
      return this.request(method, url, body, params, headers, timeoutMs, guard, allowReadRecovery)
    }
    const context: ForumRouteContext = this.syncRouteContext()
    // proxyUrl already restricts this branch to the fixed HTTPS host list.
    const originMatch = url.match(/^https:\/\/[^/?#]+/)
    const state = this.connection(originMatch === null ? url : originMatch[0])
    if (method === http.RequestMethod.GET && allowReadRecovery) {
      return this.read(state, context, url, translated, params, headers, timeoutMs, allowAuthentication, guard)
    }
    if (await this.canConnectDirectly(state)) {
      try {
        const response = await this.request(method, url, body, params, headers, timeoutMs, guard, allowReadRecovery)
        state.direct = true
        state.checkedAt = Date.now()
        return response
      }
      catch (e) {
        if (!ForumNetwork.isConnectionFailure(e)) throw e as Error
        state.direct = false; state.checkedAt = Date.now()
        throw e as Error
      }
    }
    const response = await this.proxyRequest(method, translated, body, params, headers, timeoutMs, allowAuthentication, guard, allowReadRecovery)
    state.direct = false; state.checkedAt = Date.now()
    return response
  }

  private async read(state: ForumConnectionState, context: ForumRouteContext, url: string, translated: string,
    params: Record<string, string> | undefined, headers: Record<string, string> | undefined,
    timeoutMs: number, allowAuthentication: boolean, guard: () => void): Promise<HttpResponse> {
    guard()
    if (state.readOwnerGuard !== null) {
      try { state.readOwnerGuard() }
      catch (e) { state.reading = null; state.readOwnerGuard = null; state.readFailure = null; state.direct = undefined; state.checkedAt = 0 }
    }
    if (state.reading !== null) {
      const mayAuthenticate: boolean = state.readAuthentication
      try { await state.reading }
      catch (e) {
        guard()
        // A passive preview may not renew SSO. Entering the actual page can.
        if (!allowAuthentication || mayAuthenticate || !(e instanceof HttpError) || e.statusCode !== -2) throw e as Error
      }
      guard()
    }
    const cookies: string = FduRepository.getInstance().cookiesFor(ForumRoute.LOGIN_URL)
    // A persisted proxy preference is not permission to start authentication
    // when this account has no current VPN session at all.
    if (state.direct === false && !cookies) { state.direct = undefined; state.checkedAt = 0 }
    if (state.failedOwnerGuard !== null) {
      try { state.failedOwnerGuard() }
      catch (e) { state.readFailure = null; state.failedOwnerGuard = null }
    }
    const failureAge: number = Date.now() - state.failedAt
    if (state.readFailure !== null && failureAge >= 0 && failureAge < 3000 && cookies === state.failedCookies &&
      (!allowAuthentication || state.failedAuthentication)) throw state.readFailure
    const age: number = Date.now() - state.checkedAt
    if (state.direct === undefined || age < 0 || age >= (state.direct ? 300000 : 60000)) {
      const hint = await ForumRouteHints.read(state.origin, context)
      guard()
      if (hint === true || hint === false && cookies.length > 0) { state.direct = hint; state.checkedAt = Date.now() }
      else { state.direct = undefined; state.checkedAt = 0 }
    }
    // A sibling can acquire the flight while a persisted hint was read.
    if (state.reading !== null) return this.read(state, context, url, translated, params, headers, timeoutMs, allowAuthentication, guard)
    const exploring: boolean = state.direct === undefined
    const task = this.readRoute(state, context, url, translated, params, headers, timeoutMs, allowAuthentication, guard)
    const routing: Promise<boolean> | null = exploring ? task.then((): boolean => state.direct === true, (e: Object): boolean => {
      // HTTP/TLS rejection proves which route answered, not that a sibling
      // endpoint has the same error. Followers send their own actual request.
      if (state.direct !== undefined) return state.direct
      throw e as Error
    }) : null
    if (routing !== null) {
      routing.catch(() => {}); state.reading = routing; state.readAuthentication = allowAuthentication; state.readOwnerGuard = guard
    }
    try { return await task }
    catch (e) {
      guard()
      if (e instanceof HttpError && !e.authenticationRecovery && (e.statusCode === -2 || ForumNetwork.isConnectionFailure(e))) {
        state.readFailure = e; state.failedAt = Date.now(); state.failedCookies = cookies
        state.failedAuthentication = allowAuthentication; state.failedOwnerGuard = guard
      }
      throw e as Error
    } finally { if (state.reading === routing) state.reading = null }
  }

  private rememberRead(state: ForumConnectionState, context: ForumRouteContext, direct: boolean): void {
    state.direct = direct; state.checkedAt = Date.now(); state.readFailure = null; state.failedAt = 0
    ForumRouteHints.remember(state.origin, context, direct)
  }

  private async readRoute(state: ForumConnectionState, context: ForumRouteContext, url: string, translated: string,
    params: Record<string, string> | undefined, headers: Record<string, string> | undefined,
    timeoutMs: number, allowAuthentication: boolean, guard: () => void): Promise<HttpResponse> {
    const known: boolean | undefined = state.direct
    let directFailure: HttpError | null = null
    let proxyFailure: HttpError | null = null
    // The actual native GET must terminate before fallback. No detached race
    // can hide a late TLS rejection or leave an overlapping native transfer.
    if (known !== false) {
      try {
        const response = await this.request(http.RequestMethod.GET, url, undefined, params, headers,
          known === undefined ? Math.min(2000, timeoutMs) : timeoutMs, guard)
        guard(); this.rememberRead(state, context, true)
        return response
      } catch (e) {
        if (!ForumNetwork.isConnectionFailure(e)) {
          guard(); state.direct = true; state.checkedAt = Date.now()
          throw e as Error
        }
        directFailure = e as HttpError
      }
    }
    guard()
    try {
      const response = await this.proxyRequest(http.RequestMethod.GET, translated, undefined, params, headers,
        timeoutMs, allowAuthentication, guard)
      guard(); this.rememberRead(state, context, false)
      return response
    } catch (e) {
      if (!(e instanceof HttpError && !e.authenticationRecovery && e.statusCode === -2) && !ForumNetwork.isConnectionFailure(e)) {
        guard(); state.direct = false; state.checkedAt = Date.now()
        throw e as Error
      }
      proxyFailure = e as HttpError
    }
    guard()
    // A short first read is not proof of a dead host. If VPN also fails, one
    // normal-budget direct read can still finish a slow response. Never retry VPN.
    if (known !== true) {
      try {
        const response = await this.request(http.RequestMethod.GET, url, undefined, params, headers, timeoutMs, guard)
        guard(); this.rememberRead(state, context, true)
        return response
      } catch (e) {
        if (!ForumNetwork.isConnectionFailure(e)) {
          guard(); state.direct = true; state.checkedAt = Date.now()
          throw e as Error
        }
        if (directFailure !== null) {
          const previous: string = directFailure.diagnostics
          directFailure = e as HttpError
          directFailure.diagnostics = previous + '\n' + directFailure.diagnostics
        } else directFailure = e as HttpError
      }
    }
    guard()
    state.direct = undefined; state.checkedAt = 0
    ForumRouteHints.forget(state.origin, context)
    const needsAuthentication: boolean = proxyFailure !== null && proxyFailure.statusCode === -2
    const failure = new HttpError(needsAuthentication ? -2 : -1, directFailure?.code ?? proxyFailure?.code ?? 0,
      needsAuthentication ? '直连连接失败，备用校园通道需要身份验证。' : '直连和校园备用通道均未连接成功，请稍后重试。', '', 'route-selection')
    failure.diagnostics = this.routeFailure('direct', directFailure) + '\n\n' + this.routeFailure('proxy', proxyFailure)
    throw failure
  }

  private routeFailure(route: string, error: HttpError | null): string {
    if (error === null) return 'route=' + route + '; no completed attempt'
    return 'route=' + route + '\nHttpError (status=' + error.statusCode + ', code=' + error.code + '): ' +
      error.message + (error.diagnostics ? '\n' + error.diagnostics : '')
  }

  private async proxyRequest(method: http.RequestMethod, translated: string, body: string | undefined,
    params: Record<string, string> | undefined, headers: Record<string, string> | undefined,
    timeoutMs: number, allowAuthentication: boolean, guard: () => void, allowReadRecovery: boolean = true): Promise<HttpResponse> {
    guard()
    const campus = FduRepository.getInstance()
    if (!allowAuthentication) {
      // Home summaries may reuse a verified proxy session, but must never
      // open or renew a browser while unrelated cards are being loaded.
      const cookies: string = campus.cookiesFor(ForumRoute.LOGIN_URL)
      if (!cookies) throw new HttpError(-2, 0, AppLanguage.text($r('app.string.forum_webvpn_login_required')), '')
      const scoped: Record<string, string> = {}
      if (headers) for (const key of Object.keys(headers)) scoped[key] = headers[key]
      scoped['Cookie'] = cookies
      return this.request(method, translated, body, params, scoped, timeoutMs, guard, allowReadRecovery)
    }
    if (!campus.canLoginOnDemand() && !campus.cookiesFor(ForumRoute.LOGIN_URL)) {
      throw new HttpError(-2, 0, AppLanguage.text($r('app.string.forum_webvpn_login_required')), '')
    }
    return campus.withService(ForumRoute.LOGIN_URL,
      async (cookies: string): Promise<HttpResponse> => {
        guard()
        const scoped: Record<string, string> = {}
        if (headers) for (const key of Object.keys(headers)) scoped[key] = headers[key]
        scoped['Cookie'] = cookies
        return this.request(method, translated, body, params, scoped, timeoutMs, guard, allowReadRecovery)
      }, false, undefined, method === http.RequestMethod.GET && allowReadRecovery)
  }

  private request(method: http.RequestMethod, url: string, body: string | undefined,
    params: Record<string, string> | undefined, headers: Record<string, string> | undefined,
    timeoutMs: number, guard: () => void, allowReadRecovery: boolean = true): Promise<HttpResponse> {
    guard()
    if (method === http.RequestMethod.GET) return this.http.get(url, params, headers, timeoutMs, false, allowReadRecovery)
    if (method === http.RequestMethod.POST) return this.http.post(url, body, headers)
    if (method === http.RequestMethod.PUT) return this.http.put(url, body, headers)
    if (method === http.RequestMethod.PATCH) return this.http.patch(url, body, headers)
    return this.http.delete(url, body, headers)
  }
}
