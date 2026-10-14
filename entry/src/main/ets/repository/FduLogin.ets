/**
 * Fudan ID (id.fudan.edu.cn) authentication.
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * The port used to carry a comment saying the ID system "answers
 * {"code":"500"} to every request shape, so the chain is not usable". That was
 * wrong, and wrong in the most expensive way: it recorded a fixable
 * implementation bug as a dead end, so the whole campus-data surface (grades,
 * timetable, ecard, bus) stayed switched off behind it.
 *
 * The one thing queryAuthMethods actually requires is `lck`. POST with `{}`
 * returns code 500; POST with `{"lck": ...}` returns the real authentication
 * chain. And `lck` is not something you can guess or fetch: it is handed out
 * as a URL FRAGMENT in the Location header of a 302, and fragments are never
 * transmitted to a server. It has to be read off the redirect hop itself.
 *
 * Contract source: lib/repository/fdu/neo_login_tool.dart
 *   authenticate      :382-452   walk to the ID host
 *   _getAuthParams    :477-516   lck/entityId -> authChainCode
 *   _getPublicKey     :468-475   base64 SPKI -> PEM
 *   _login            :518-555   RSA PKCS#1 v1.5 -> authExecute -> loginToken
 *   _postToken        :557-565   authnEngine (form post) -> ticket page
 *   _retrieveUrlWithTicket :456-466  #logon action + #ticket value
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { HttpUtil, HttpResponse, HttpError, CampusSsoReadOptions } from '../util/HttpUtil'
import { FduAuthChallenge, FduAuthPolicy } from '../model/FduAuth'
import { CasTicket } from '../model/CasTicket'
import { CampusCookies } from '../common/CampusCookies'
import { DormRequestPolicy } from '../model/DormRequestPolicy'

/** One offered authentication method from /idp/authn/queryAuthMethods. */
interface AuthMethod {
  moduleCode: string
  authChainCode: string
  chainName: string
}

interface QueryAuthMethodsResponse {
  code: string
  status: string
  message: string
  second?: boolean
  data?: AuthMethod[]
}

interface PublicKeyResponse {
  code: string
  status: string
  data?: string
}

interface AuthExecuteResponse {
  code: number
  message: string
  loginToken?: string | null
  second?: boolean | null
  moduleCode?: string | null
}

/** What the caller gets back from a successful ID login. */
export interface FduSession {
  /** Ticket-bearing URL that must be fetched to turn the ticket into cookies. */
  targetUrl: string
  /** Cookies collected across the whole handshake, for the service session. */
  cookies: string
  /** Present when the HTTP redirect already redeemed the one-use ticket. */
  serviceCookies?: string
  /** A successful dorm SSO already read the balance; reuse those exact bytes. */
  dormResponse?: HttpResponse
}

/** Distinguishes the failure modes a login UI has to react to differently. */
export enum FduLoginFailure {
  /** Server rejected the username/password pair. Retrying may help. */
  CREDENTIALS_INVALID = 0,
  /** Server demands a captcha; automated login must stop and hand over. */
  CAPTCHA_REQUIRED = 1,
  /** Server requires the official webpage to finish enhanced authentication. */
  ENHANCED_AUTH_REQUIRED = 2,
  /** The handshake itself broke — network, markup change, protocol drift. */
  PROTOCOL_ERROR = 3,
  /** Account lock/expiry or another form error needs user input, not MFA. */
  ACCOUNT_ACTION_REQUIRED = 4,
}

export class FduLoginError extends Error {
  readonly failure: FduLoginFailure
  readonly detail: string
  challenge: FduAuthChallenge | null = null

  constructor(failure: FduLoginFailure, message: string, detail: string) {
    super(message)
    this.name = 'FduLoginError'
    this.failure = failure
    this.detail = detail
  }
}

/**
 * Error strings the server sends. Both are quoted verbatim from the upstream
 * client so a wording change on the server shows up as PROTOCOL_ERROR rather
 * than being silently mistaken for success.
 *   CAPTCHA_CODE_NEEDED   neo_login_tool.dart:369
 *   CREDENTIALS_INVALID   neo_login_tool.dart:380
 */
const CAPTCHA_CODE_NEEDED: string = '请输入验证码'

export class FduLogin {
  private static readonly ID_HOST: string = 'https://id.fudan.edu.cn'
  private static readonly ID_HOSTNAME: string = 'id.fudan.edu.cn'

  private readonly http: HttpUtil
  private readonly cookies: Map<string, string> = new Map<string, string>()
  private readonly idCookieRecords: Map<string, string> = new Map<string, string>()
  private loginUrl: string = ''

  constructor(http: HttpUtil) {
    this.http = http
  }

  private cookieHeader(): string {
    const parts: string[] = []
    this.cookies.forEach((value: string, name: string) => {
      parts.push(name + '=' + value)
    })
    return parts.join('; ')
  }

  private absorbCookies(response: HttpResponse): void {
    this.absorbCookieHeader(response.headers['set-cookie'])
  }

  /**
   * Absorb a raw Set-Cookie header value.
   *
   * HarmonyOS surfaces the header as a single comma-joined string, but an
   * Expires attribute also contains commas, so split on the `, <name>=`
   * boundary rather than on every comma.
   *
   * Separate from `absorbCookies` because cookies are not only set on the final
   * response: CAS sets REQID on the intermediate hop that hands out `lck`.
   */
  private absorbCookieHeader(raw: string): void {
    if (!raw || raw.length === 0) {
      return
    }
    const chunks: string[] = FduAuthPolicy.splitSetCookies(raw)
    for (const chunk of chunks) {
      const pair: string = chunk.split(';')[0]
      const eq: number = pair.indexOf('=')
      if (eq > 0) {
        this.cookies.set(pair.substring(0, eq).trim(), pair.substring(eq + 1).trim())
        this.idCookieRecords.set(pair.substring(0, eq).trim(), chunk)
      }
    }
  }

  private browserHeaders(extra?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': HttpUtil.BROWSER_UA,
    }
    const cookie: string = this.cookieHeader()
    if (cookie.length > 0) {
      headers['Cookie'] = cookie
    }
    if (extra) {
      const keys = Object.keys(extra)
      for (const key of keys) {
        headers[key] = extra[key]
      }
    }
    return headers
  }

  /**
   * Step 1 — follow the redirect chain to the ID host and read `lck` and
   * `entityId` out of the hash fragment of the SPA entry URL.
   *
   * `lck` is published nowhere else: not in a response body, not in a cookie,
   * not in any other header. It appears only as the `Location` of the third hop,
   * so that hop has to be observed. `HttpUtil.hop()` follows the whole chain in
   * a single call and reports every hop's headers through `lastHopHeaders()`;
   * there is no way to ask this SDK to stop at a 3xx instead.
   */
  private async walkToLogin(service: string): Promise<Record<string, string>> {
    const cookieEpoch = CampusCookies.generation()
    const response: HttpResponse = await this.http.hop(service, this.browserHeaders())
    const hops: Record<string, string>[] = response.hopHeaders ?? this.http.lastHopHeaders()
    await CampusCookies.absorb(service, hops, cookieEpoch)

    // Cookies are not only set on the last response — CAS sets REQID on the very
    // hop that hands out `lck` — so every hop contributes.
    for (const cookie of FduAuthPolicy.cookiesForOrigin(service, hops, FduAuthPolicy.ID_ORIGIN)) {
      this.absorbCookieHeader(cookie)
    }

    // The SPA entry URL is a redirect target, so it shows up as some hop's
    // `location`. Scan in order; the final response's own `location` is kept as
    // a fallback because the SDK also leaves the last hop's value there.
    const candidates: string[] = []
    for (let i = 0; i < hops.length; i++) {
      const loc: string = hops[i]['location']
      if (loc !== undefined && loc !== null && loc.length > 0) {
        candidates.push(loc)
      }
    }
    const finalLocation: string = response.headers['location']
    if (finalLocation !== undefined && finalLocation !== null && finalLocation.length > 0) {
      candidates.push(finalLocation)
    }

    for (let i = 0; i < candidates.length; i++) {
      const url: string = candidates[i]
      if (!FduAuthPolicy.isIdUrl(url) || url.indexOf('/ac/') < 0) {
        continue
      }
      const params: Record<string, string> = FduLogin.fragmentParams(url)
      if (params['lck'] && params['entityId']) {
        this.loginUrl = url
        return params
      }
    }

    throw new FduLoginError(
      FduLoginFailure.PROTOCOL_ERROR,
      '登录服务未按预期跳转',
      'status ' + response.code + '; hops=' + hops.length +
        '; lastLocation=' + (hops.length > 0 ? hops[hops.length - 1]['location'] : 'none')
    )
  }

  /** Resolve a possibly-relative Location against the URL it came from. */
  private static resolve(location: string, base: string): string {
    if (location.indexOf('//') === 0) {
      const scheme: string = base.substring(0, base.indexOf(':'))
      return scheme + ':' + location
    }
    const colon: number = base.indexOf('://')
    const slash: number = base.indexOf('/', colon + 3)
    const origin: string = slash < 0 ? base : base.substring(0, slash)
    return location.indexOf('/') === 0 ? origin + location : origin + '/' + location
  }
  /**
   * `#/index?lck=...&entityId=...` — a route followed by a query string, so
   * the parameters begin after the `?`, not after the `#`. Parsing the whole
   * fragment yields one bogus key and silently loses every real parameter,
   * which then shows up much later as an unexplained code 500.
   */
  private static fragmentParams(url: string): Record<string, string> {
    const out: Record<string, string> = {}
    const hash: number = url.indexOf('#')
    if (hash < 0) {
      return out
    }
    const query: number = url.indexOf('?', hash)
    if (query < 0) {
      return out
    }
    const pairs: string[] = url.substring(query + 1).split('&')
    for (const pair of pairs) {
      const eq: number = pair.indexOf('=')
      if (eq > 0) {
        out[FduLogin.decodeComponent(pair.substring(0, eq))] =
          FduLogin.decodeComponent(pair.substring(eq + 1))
      }
    }
    return out
  }

  private static decodeComponent(text: string): string {
    try {
      return decodeURIComponent(text.replace(/\+/g, ' '))
    } catch (e) {
      return text
    }
  }

  private jsonHeaders(): Record<string, string> {
    return this.browserHeaders({
      'Content-Type': 'application/json;charset=UTF-8',
      'Accept': 'application/json, text/plain, */*',
      'Origin': FduLogin.ID_HOST,
      'Referer': FduLogin.ID_HOST + '/ac/',
      'X-Requested-With': 'XMLHttpRequest',
    })
  }

  /** Step 2 — the server's RSA public key, as base64 SPKI (DER). */
  private async fetchPublicKey(): Promise<Uint8Array> {
    const response: HttpResponse = await this.http.post(
      FduLogin.ID_HOST + '/idp/authn/getJsPublicKey',
      '{}',
      this.jsonHeaders()
    )
    this.absorbCookies(response)
    let parsed: PublicKeyResponse | null = null
    try {
      parsed = JSON.parse(response.data) as PublicKeyResponse
    } catch (e) {
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        '无法解析公钥响应',
        response.data.substring(0, 200)
      )
    }
    if (!parsed || !parsed.data) {
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        '登录服务未返回公钥',
        response.data.substring(0, 200)
      )
    }
    try {
      return new util.Base64Helper().decodeSync(parsed.data)
    } catch (e) {
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        '公钥不是合法的 base64',
        String(e)
      )
    }
  }

  /** Step 3 — exchange `lck` for the authentication chain. */
  private async fetchAuthChainCode(lck: string, entityId: string): Promise<string> {
    const payload: Record<string, string> = { 'lck': lck, 'entityId': entityId }
    const response: HttpResponse = await this.http.post(
      FduLogin.ID_HOST + '/idp/authn/queryAuthMethods',
      JSON.stringify(payload),
      this.jsonHeaders()
    )
    this.absorbCookies(response)

    let parsed: QueryAuthMethodsResponse | null = null
    try {
      parsed = JSON.parse(response.data) as QueryAuthMethodsResponse
    } catch (e) {
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        '无法解析认证方式响应',
        response.data.substring(0, 200)
      )
    }
    if (!parsed) {
      throw new FduLoginError(FduLoginFailure.PROTOCOL_ERROR, '认证方式响应为空', response.data)
    }

    const formFailure = FduLogin.formFailure(parsed.message ?? '')
    if (formFailure !== null) throw formFailure

    // The server answers code 500 to a body without `lck`; this is the exact
    // shape that made the port declare the whole API unusable. Surface it as
    // what it is — a request we built wrong — rather than a server outage.
    if (parsed.second === true) {
      throw new FduLoginError(
        FduLoginFailure.ENHANCED_AUTH_REQUIRED,
        '请在复旦官方页面完成二次验证',
        response.data.substring(0, 200)
      )
    }
    const methods: AuthMethod[] = parsed.data ? parsed.data : []
    if (methods.length === 0) {
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        '服务器未提供任何认证方式',
        'code=' + parsed.code + ' message=' + parsed.message
      )
    }
    let chosen: AuthMethod | null = null
    for (const method of methods) {
      if (method.moduleCode === 'userAndPwd') {
        chosen = method
      }
    }
    if (chosen === null) {
      const offered: string[] = []
      for (const method of methods) {
        offered.push(method.moduleCode)
      }
      throw new FduLoginError(
        FduLoginFailure.ENHANCED_AUTH_REQUIRED,
        '请在复旦官方页面选择认证方式',
        'offered: ' + offered.join(', ')
      )
    }
    return chosen.authChainCode
  }

  /** Step 4a — RSA PKCS#1 v1.5 encrypt the password, base64-encoded. */
  private async encryptPassword(spki: Uint8Array, password: string): Promise<string> {
    let pubKey: cryptoFramework.PubKey | null = null
    try {
      const generator: cryptoFramework.AsyKeyGenerator =
        cryptoFramework.createAsyKeyGenerator('RSA3072')
      const blob: cryptoFramework.DataBlob = { data: spki }
      const keyPair: cryptoFramework.KeyPair = await generator.convertKey(blob, null)
      pubKey = keyPair.pubKey
    } catch (e) {
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        '无法载入服务器公钥',
        String(e)
      )
    }

    try {
      // PKCS1 here means PKCS#1 v1.5 padding, which is what the server expects.
      // PKCS1_OAEP would produce a well-formed ciphertext the server rejects.
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('RSA3072|PKCS1')
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, pubKey, null)
      // TextEncoder.encodeInto() returns a bare Uint8Array; the crypto API
      // wants the DataBlob wrapper, so it has to be constructed explicitly.
      const plain: cryptoFramework.DataBlob = { data: new util.TextEncoder().encodeInto(password) }
      const encrypted: cryptoFramework.DataBlob = await cipher.doFinal(plain)
      return new util.Base64Helper().encodeToStringSync(encrypted.data)
    } catch (e) {
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        '密码加密失败',
        String(e)
      )
    }
  }

  /** Step 4b — submit the encrypted credential and collect the login token. */
  private async authExecute(
    lck: string,
    entityId: string,
    authChainCode: string,
    studentId: string,
    encryptedPassword: string
  ): Promise<string> {
    const authPara: Record<string, string> = {
      'loginName': studentId,
      'password': encryptedPassword,
      'verifyCode': '',
    }
    const payload: Record<string, Object> = {
      'authModuleCode': 'userAndPwd',
      'authChainCode': authChainCode,
      'entityId': entityId,
      'requestType': 'chain_type',
      'lck': lck,
      'authPara': authPara,
    }
    const response: HttpResponse = await this.http.post(
      FduLogin.ID_HOST + '/idp/authn/authExecute',
      JSON.stringify(payload),
      this.jsonHeaders()
    )
    this.absorbCookies(response)

    let parsed: AuthExecuteResponse | null = null
    try {
      parsed = JSON.parse(response.data) as AuthExecuteResponse
    } catch (e) {
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        '无法解析登录响应',
        response.data.substring(0, 200)
      )
    }
    if (!parsed) {
      throw new FduLoginError(FduLoginFailure.PROTOCOL_ERROR, '登录响应为空', response.data)
    }

    const message: string = parsed.message ? parsed.message : ''
    const formFailure = FduLogin.formFailure(message)
    if (formFailure !== null) throw formFailure
    if (message.indexOf(CAPTCHA_CODE_NEEDED) >= 0) {
      throw new FduLoginError(
        FduLoginFailure.CAPTCHA_REQUIRED,
        '请在复旦官方页面输入验证码',
        message
      )
    }
    const token: string = parsed.loginToken ? parsed.loginToken : ''
    if (token.length === 0) {
      if (parsed.second === true || (parsed.moduleCode && parsed.moduleCode !== 'userAndPwd')) {
        throw new FduLoginError(
          FduLoginFailure.ENHANCED_AUTH_REQUIRED,
          '请在复旦官方页面继续身份验证',
          message
        )
      }
      throw new FduLoginError(
        FduLoginFailure.PROTOCOL_ERROR,
        message.length > 0 ? message.substring(0, 180) : '登录服务未返回有效结果，请稍后重试',
        message.length > 0 ? message : response.data.substring(0, 200)
      )
    }
    return token
  }

  /** Fatal input errors take precedence over the server's second-step flag.
   * Unknown errors remain errors; lack of a token is not evidence of MFA. */
  private static formFailure(message: string): FduLoginError | null {
    if (/(?:用户名|用户|账号|账户|学号|密码).{0,16}(?:错误|不正确|不匹配|不存在|有误)|(?:invalid|incorrect|wrong).{0,20}(?:credential|password|username)|(?:password|username).{0,20}(?:invalid|incorrect|wrong)/i.test(message)) {
      return new FduLoginError(FduLoginFailure.CREDENTIALS_INVALID, '学号或密码错误，请重新输入', message)
    }
    if (/(?:账号|账户|用户|密码).{0,16}(?:锁定|冻结|禁用|过期|失效)|(?:重试|尝试).{0,8}(?:次数|上限)|(?:locked|disabled|expired|too many attempts)|验证码.{0,8}(?:错误|不正确|失效)/i.test(message)) {
      return new FduLoginError(FduLoginFailure.ACCOUNT_ACTION_REQUIRED,
        message.substring(0, 180), message)
    }
    return null
  }

  /** Reuse the shared ID/CAS jar exactly as upstream's first request and CAS
   * auto-submit form. This never submits a password or presents UI. */
  async resume(service: string, entry: string = service, options?: CampusSsoReadOptions): Promise<FduSession> {
    const scoped: CampusSsoReadOptions | undefined = options ?? (DormRequestPolicy.isDorm(service) ? {
      timeoutMs: DormRequestPolicy.WAIT_MS, freshConnection: false, fallbackCookies: ''
    } : undefined)
    const deadline: number = Date.now() + (scoped?.timeoutMs ?? 15000)
    let response = await this.http.getCampusSso(entry, scoped)
    let finalUrl = response.finalUrl ?? CasTicket.finalUrl(entry, response.hopHeaders ?? [])
    const ticket = CasTicket.fromHtml(response.data, finalUrl, service)
    if (ticket) {
      if (scoped !== undefined) {
        const remaining: number = deadline - Date.now()
        if (remaining <= 0) throw new HttpError(-1, 2300028,
          DormRequestPolicy.isDorm(service) ? '寝室电费身份会话接续超时，请稍后重新加载。' : '门户会话检查超时，请稍后重新加载。',
          '', DormRequestPolicy.isDorm(service) ? 'dorm-sso' : '')
        const ticketOptions: CampusSsoReadOptions = {
          timeoutMs: remaining, freshConnection: scoped.freshConnection,
          fallbackCookies: FduAuthPolicy.origin(ticket) === FduAuthPolicy.origin(service) ? scoped.fallbackCookies : '',
          historyQuery: scoped.historyQuery
        }
        response = await this.http.getCampusSso(ticket, ticketOptions)
      } else {
        response = await this.http.getCampusSso(ticket)
      }
      finalUrl = response.finalUrl ?? CasTicket.finalUrl(ticket, response.hopHeaders ?? [])
    }
    const requiresQr = service.split(/[?#]/)[0].endsWith('/wxpage/fudan/zfm/qrcode')
    const savedCookies: string = await CampusCookies.read(finalUrl)
    const cookies: string = savedCookies || (FduAuthPolicy.isServiceUrl(finalUrl, service) ? options?.fallbackCookies ?? '' : '')
    if ((!requiresQr || FduAuthPolicy.isLifeCodeDocument(finalUrl, response.data)) &&
      FduAuthPolicy.isServiceDocument(finalUrl, service, response.data, cookies)) {
      if (DormRequestPolicy.isDorm(service)) return {
        targetUrl: finalUrl, cookies: '', serviceCookies: cookies, dormResponse: response
      }
      return { targetUrl: finalUrl, cookies: '', serviceCookies: cookies }
    }
    const error = new FduLoginError(FduLoginFailure.ENHANCED_AUTH_REQUIRED,
      '该校园服务需要继续身份验证，请点击继续验证', '')
    error.challenge = new FduAuthChallenge(FduAuthPolicy.isIdUrl(finalUrl) ? finalUrl : entry, service, [])
    throw error
  }

  /** Resume official browser SSO after a process restart without retaining a password. */
  async browserChallenge(service: string): Promise<FduAuthChallenge> {
    await this.walkToLogin(service)
    const records: string[] = []
    this.idCookieRecords.forEach((value: string) => records.push(value))
    return new FduAuthChallenge(this.loginUrl, service, records)
  }

  /** Step 5 — trade the login token for a ticket-bearing URL. */
  private async exchangeTokenForTicket(loginToken: string, service: string): Promise<FduSession> {
    const engineUrl = FduLogin.ID_HOST + '/idp/authCenter/authnEngine'
    const response: HttpResponse = await this.http.postForm(
      engineUrl,
      { 'loginToken': loginToken },
      this.browserHeaders({ 'Referer': FduLogin.ID_HOST + '/ac/' })
    )
    const hops: Record<string, string>[] = response.hopHeaders ?? []
    if (hops.length === 0) this.absorbCookies(response)
    for (const cookie of FduAuthPolicy.cookiesForOrigin(engineUrl, hops, FduAuthPolicy.ID_ORIGIN)) {
      this.absorbCookieHeader(cookie)
    }
    const finalUrl = response.finalUrl ?? CasTicket.finalUrl(engineUrl, hops)
    if (FduAuthPolicy.isServiceLanding(finalUrl, service)) {
      const scopedCookies = await CampusCookies.read(finalUrl)
      const cookies = scopedCookies || FduAuthPolicy.cookieHeader(FduAuthPolicy.cookiesForOrigin(engineUrl, hops,
        FduAuthPolicy.origin(service)))
      if (FduAuthPolicy.isServiceDocument(finalUrl, service, response.data, cookies)) {
        return { targetUrl: finalUrl, cookies: this.cookieHeader(), serviceCookies: cookies }
      }
    }
    const target = CasTicket.fromHtml(response.data, finalUrl, service)
    if (!target) {
      // A server-side redirect or another authentication step must continue in
      // the official browser, rather than leave every campus card unusable.
      throw new FduLoginError(
        FduLoginFailure.ENHANCED_AUTH_REQUIRED,
        '请在官方页面完成校园服务登录',
        'CAS form not found after authnEngine'
      )
    }
    return { targetUrl: target, cookies: this.cookieHeader() }
  }

  /**
   * Full login. On success the ticket URL is returned WITHOUT being fetched:
   * redeeming it is the caller's job, because the ticket must be spent against
   * the service the caller actually wanted, and a ticket is single-use.
   */
  async login(service: string, studentId: string, password: string): Promise<FduSession> {
    if (studentId.length === 0 || password.length === 0) {
      throw new FduLoginError(
        FduLoginFailure.CREDENTIALS_INVALID,
        '学号和密码不能为空',
        ''
      )
    }

    this.cookies.clear()
    this.idCookieRecords.clear()
    this.loginUrl = ''
    const epoch = CampusCookies.generation()
    try {
      const params: Record<string, string> = await this.walkToLogin(service)
      FduLogin.requireEpoch(epoch)
      const lck: string = params['lck']
      const entityId: string = params['entityId']
      const chainCode: string = await this.fetchAuthChainCode(lck, entityId)
      FduLogin.requireEpoch(epoch)
      const spki: Uint8Array = await this.fetchPublicKey()
      FduLogin.requireEpoch(epoch)
      const encrypted: string = await this.encryptPassword(spki, password)
      FduLogin.requireEpoch(epoch)
      const token: string = await this.authExecute(lck, entityId, chainCode, studentId, encrypted)
      FduLogin.requireEpoch(epoch)
      return await this.exchangeTokenForTicket(token, service)
    } catch (e) {
      if (e instanceof FduLoginError && this.loginUrl.length > 0 &&
        (e.failure === FduLoginFailure.ENHANCED_AUTH_REQUIRED || e.failure === FduLoginFailure.CAPTCHA_REQUIRED)) {
        const records: string[] = []
        this.idCookieRecords.forEach((value: string) => records.push(value))
        e.challenge = new FduAuthChallenge(this.loginUrl, service, records)
      }
      throw e as Error
    }
  }

  private static requireEpoch(epoch: number): void {
    if (epoch !== CampusCookies.generation()) throw new Error('登录已取消，请重新登录')
  }

  /**
   * Probe as far as the handshake can go without valid credentials.
   *
   * This exists so the protocol itself can be regression-tested on a device
   * with no real account: it walks the chain, fetches the key, asks for the
   * auth chain and submits a deliberately wrong password. A well-formed
   * request draws the server's own CREDENTIALS message; a malformed one draws
   * a generic protocol error. That difference is the whole test.
   */
  async probeHandshake(
    service: string,
    fakeStudentId: string,
    fakePassword: string
  ): Promise<FduLoginError> {
    try {
      await this.login(service, fakeStudentId, fakePassword)
      throw new Error('a fake credential was accepted — the probe is meaningless')
    } catch (e) {
      if (e instanceof FduLoginError) {
        return e
      }
      throw e instanceof HttpError
        ? new FduLoginError(FduLoginFailure.PROTOCOL_ERROR, '网络请求失败', String(e))
        : e as Error
    }
  }

  /** Cookies accumulated so far — used by callers that share this session. */
  getCookies(): string {
    return this.cookieHeader()
  }
}
