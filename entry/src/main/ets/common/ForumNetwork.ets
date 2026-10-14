import { http } from '@kit.NetworkKit'
import { HttpUtil, HttpError, HttpResponse } from '../util/HttpUtil'
import { FduRepository } from '../repository/FduRepository'
import { ForumRoute } from './ForumRoute'
import { AppLanguage } from './AppLanguage'
import { Constant } from './Constant'

class ForumConnectionState {
  origin: string = ''
  direct: boolean | undefined = undefined
  checkedAt: number = 0
  checking: Promise<boolean> | null = null
}

/** Keep upstream's anonymous fast probe and shared WebVPN SSO, but scope the
 * route decision to its actual host. A reachable forum host does not prove
 * that the separate account/authentication or DanKe host is reachable.
 */
export class ForumNetwork {
  private static instance: ForumNetwork | null = null
  private http: HttpUtil = HttpUtil.getInstance()
  private connections: ForumConnectionState[] = []

  static getInstance(): ForumNetwork {
    if (ForumNetwork.instance === null) ForumNetwork.instance = new ForumNetwork()
    return ForumNetwork.instance
  }

  async get(url: string, params?: Record<string, string>, headers?: Record<string, string>,
    timeoutMs: number = 15000, allowAuthentication: boolean = true): Promise<HttpResponse> {
    return this.send(http.RequestMethod.GET, url, undefined, params, headers, timeoutMs, allowAuthentication)
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
    return error instanceof HttpError && error.isNetworkFailure() &&
      [0, 2300005, 2300006, 2300007, 2300028, 2300052, 2300055, 2300056, 2300999].includes(error.code)
  }

  private async send(method: http.RequestMethod, url: string, body: string | undefined,
    params: Record<string, string> | undefined, headers: Record<string, string> | undefined,
    timeoutMs: number = 15000, allowAuthentication: boolean = true): Promise<HttpResponse> {
    const translated = ForumRoute.proxyUrl(url)
    if (!translated || AppStorage.get<boolean>(Constant.KEY_USE_WEBVPN) === false) {
      return this.request(method, url, body, params, headers, timeoutMs)
    }
    // proxyUrl already restricts this branch to the fixed HTTPS host list.
    const originMatch = url.match(/^https:\/\/[^/?#]+/)
    const state = this.connection(originMatch === null ? url : originMatch[0])
    if (await this.canConnectDirectly(state)) {
      try { return await this.request(method, url, body, params, headers, timeoutMs) }
      catch (e) {
        if (!ForumNetwork.isConnectionFailure(e)) throw e as Error
        state.direct = false
        state.checkedAt = Date.now()
        // A write may already have reached the server. Only reads are replayed
        // on route changes; login/post/vote retry stays under the user's control.
        if (method !== http.RequestMethod.GET) throw e as Error
      }
    }
    const campus = FduRepository.getInstance()
    if (!allowAuthentication) {
      // Home summaries may reuse a verified proxy session, but must never
      // open or renew a browser while unrelated cards are being loaded.
      const cookies: string = campus.cookiesFor(ForumRoute.LOGIN_URL)
      if (!cookies) throw new HttpError(-2, 0, AppLanguage.text($r('app.string.forum_webvpn_login_required')), '')
      const scoped: Record<string, string> = {}
      if (headers) for (const key of Object.keys(headers)) scoped[key] = headers[key]
      scoped['Cookie'] = cookies
      return this.request(method, translated, body, params, scoped, timeoutMs)
    }
    if (!campus.canLoginOnDemand() && !campus.cookiesFor(ForumRoute.LOGIN_URL)) {
      throw new HttpError(-2, 0, AppLanguage.text($r('app.string.forum_webvpn_login_required')), '')
    }
    return campus.withService(ForumRoute.LOGIN_URL,
      async (cookies: string): Promise<HttpResponse> => {
        const scoped: Record<string, string> = {}
        if (headers) for (const key of Object.keys(headers)) scoped[key] = headers[key]
        scoped['Cookie'] = cookies
        return this.request(method, translated, body, params, scoped, timeoutMs)
      }, false)
  }

  private request(method: http.RequestMethod, url: string, body: string | undefined,
    params: Record<string, string> | undefined, headers: Record<string, string> | undefined,
    timeoutMs: number): Promise<HttpResponse> {
    if (method === http.RequestMethod.GET) return this.http.get(url, params, headers, timeoutMs)
    if (method === http.RequestMethod.POST) return this.http.post(url, body, headers)
    if (method === http.RequestMethod.PUT) return this.http.put(url, body, headers)
    if (method === http.RequestMethod.PATCH) return this.http.patch(url, body, headers)
    return this.http.delete(url, body, headers)
  }
}
