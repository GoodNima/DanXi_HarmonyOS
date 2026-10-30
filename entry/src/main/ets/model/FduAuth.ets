/** Manual authentication continuation, following upstream neo_login_tool.dart. */
export class FduAuthChallenge {
  loginUrl: string
  serviceUrl: string
  idCookies: string[]

  constructor(loginUrl: string, serviceUrl: string, idCookies: string[]) {
    this.loginUrl = loginUrl
    this.serviceUrl = serviceUrl
    this.idCookies = idCookies
  }
}

interface EhallIdentityWire { name?: string }
interface ZlappDataProof { fj_surplus?: Object; fj_used?: Object; roomid?: Object; data?: Object }
interface ZlappEnvelopeProof { d?: ZlappDataProof }

/** URL checks used before importing cookies or filling a university login form. */
export class FduAuthPolicy {
  static readonly ID_ORIGIN: string = 'https://id.fudan.edu.cn'

  static origin(value: string): string {
    // The only HTTP exception is the published graduate course service.
    const graduate = /^http:\/\/(yjsxk\.fudan\.edu\.cn|yjsxk\.fudan\.sh\.cn|yjsxktest\.fudan\.sh\.cn)(?::80)?(?:[/?#]|$)/i.exec(value)
    if (graduate !== null) return 'http://' + graduate[1].toLowerCase()
    const match: RegExpExecArray | null = /^https:\/\/([a-z0-9.-]+)(?::443)?(?:[/?#]|$)/i.exec(value)
    return match === null ? '' : 'https://' + match[1].toLowerCase()
  }

  static isCampusUrl(value: string): boolean {
    const origin: string = FduAuthPolicy.origin(value)
    // The official Fudan OPAC OAuth provider is an exact, pinned exception.
    return origin === 'https://fdulib.a-lsp.com' || origin === 'https://fudan.edu.cn' || origin.endsWith('.fudan.edu.cn') ||
      origin === 'http://yjsxk.fudan.sh.cn' || origin === 'http://yjsxktest.fudan.sh.cn'
  }

  static isIdUrl(value: string): boolean {
    return FduAuthPolicy.origin(value) === FduAuthPolicy.ID_ORIGIN
  }

  /** The ID SPA cannot select an authentication chain without its original
   * context. Other official ID entrypoints build their own context. */
  static isIncompleteIdLoginUrl(value: string): boolean {
    if (!FduAuthPolicy.isIdUrl(value) || !/^https:\/\/id\.fudan\.edu\.cn(?::443)?\/ac(?:-h5)?\/?(?:[?#]|$)/i.test(value)) return false
    const hash: number = value.indexOf('#')
    const route: string = hash < 0 ? '' : value.substring(hash + 1).split('?')[0]
    // Later MFA routes can be driven by their own nonce/session. Do not
    // restart them merely because the initial chain parameters were consumed.
    if (!/^\/?(?:index|login)?\/?$/i.test(route)) return false
    const query: number = hash < 0 ? -1 : value.indexOf('?', hash)
    return query < 0 || !FduAuthPolicy.hasIdContextParams(value.substring(query + 1))
  }

  private static hasIdContextParams(query: string): boolean {
    let lck: boolean = false
    let entityId: boolean = false
    for (const pair of query.split('&')) {
      const eq: number = pair.indexOf('=')
      if (eq < 0) continue
      try {
        const key: string = decodeURIComponent(pair.substring(0, eq))
        if (key !== 'lck' && key !== 'entityId') continue
        const nonempty: boolean = decodeURIComponent(pair.substring(eq + 1).replace(/\+/g, ' ')).trim().length > 0
        if (key === 'lck') lck = nonempty
        if (key === 'entityId') entityId = nonempty
      } catch (error) { return false }
    }
    return lck && entityId
  }

  static isWebVpnLoginUrl(value: string): boolean {
    return /^https:\/\/webvpn\.fudan\.edu\.cn(?::443)?\/(?:login|wengine-vpn\/login)(?:[/?#]|$)/i.test(value)
  }

  static isServiceUrl(value: string, service: string): boolean {
    const origin: string = FduAuthPolicy.origin(value)
    return FduAuthPolicy.isCampusUrl(service) && origin === FduAuthPolicy.origin(service) &&
      origin !== FduAuthPolicy.ID_ORIGIN
  }

  static isServiceLanding(value: string, service: string): boolean {
    if (!FduAuthPolicy.isServiceUrl(value, service)) return false
    const path = value.substring(FduAuthPolicy.origin(value).length).split(/[?#]/)[0]
    const targetPath = service.substring(FduAuthPolicy.origin(service).length).split(/[?#]/)[0]
    const jsonTarget: string = FduAuthPolicy.zlappJsonTarget(service)
    if (jsonTarget && path !== jsonTarget.substring(FduAuthPolicy.origin(jsonTarget).length)) return false
    // WebVPN establishes its own portal session. A proxied upstream page or
    // an unfinished CAS callback is not evidence that the portal is signed in.
    if (FduAuthPolicy.isWebVpnLoginUrl(service) &&
      (/^\/(?:https?|https?-\d+)\//i.test(path) || FduAuthPolicy.isWebVpnLoginUrl(value))) return false
    if (targetPath.endsWith('/wxpage/fudan/zfm/qrcode') && path !== targetPath) return false
    // The graduate selection shell is public and must never complete data-endpoint authentication.
    if (targetPath.endsWith('/xsxkCourse/loadKbxx.do') && path !== targetPath) return false
    if (/^https:\/\/fdtyjw\.fudan\.edu\.cn\//.test(service) && path.toLowerCase() !== targetPath.toLowerCase()) return false
    return !/(?:\/sso\/login|\/cas|cas_security_check|\/api\/sso\/index|\/login(?:2\.action)?|\/reservation\/api\/login\/main)\/?$/i.test(path) &&
      !/[?&](?:ticket|loginToken)=/i.test(value)
  }

  /** The original zlapp services finish at their JSON data endpoint, not an
   * arbitrary same-host HTML page carrying auxiliary cookies. */
  static zlappJsonTarget(service: string): string {
    if (FduAuthPolicy.origin(service) !== 'https://zlapp.fudan.edu.cn') return ''
    let target: string = service.split(/[?#]/)[0]
    if (target.endsWith('/a_fudanzlapp/api/sso/index')) {
      const redirect = /[?&]redirect=([^&#]*)/i.exec(service)
      if (redirect === null) return ''
      try { target = decodeURIComponent(redirect[1]).split(/[?#]/)[0] } catch (error) { return '' }
    }
    return target === 'https://zlapp.fudan.edu.cn/fudanelec/wap/default/info' ||
      target === 'https://zlapp.fudan.edu.cn/fudanbus/wap/default/lists' ? target : ''
  }

  static isLoginDocument(body: string): boolean {
    const titleMatch = /<title[^>]*>([^<]*)<\/title>/i.exec(body)
    const title = (titleMatch?.[1] ?? '').replace(/\s|&nbsp;/gi, '').replace(/[|—–·:：-]/g, '')
    // Match a login title itself, not a notice/help title that mentions authentication.
    const loginTitle = /^(?:复旦(?:大学)?)?(?:统一身份认证|统一认证|身份认证|身份验证)(?:平台|系统|中心|服务)?(?:登录)?$/i.test(title) ||
      /^复旦(?:大学)?(?:统一身份|用户)?登录(?:平台|系统)?$/i.test(title) ||
      /^(?:(?:复旦(?:大学)?|Fudan(?:University)?)?WebVPN(?:登录|Login)|(?:登录|Login)(?:复旦(?:大学)?|Fudan(?:University)?)?WebVPN)$/i.test(title)
    if (loginTitle ||
      // Current ID SPA has an empty title until JavaScript starts. Native HTTP
      // does not execute it, and some devices omit intermediate redirect headers.
      (/<html[\s>]/i.test(body) && /id=["']app["']/i.test(body) &&
        /static\/jsencrypt\.min\.js/i.test(body) && /static\/config\.js/i.test(body) &&
        /js\/chunk-vendors\.[\w]+\.js/i.test(body))) return true
    // Keep proof within the password form. A settings form and a WebVPN link
    // elsewhere in a valid business page must not trigger authentication.
    for (const form of body.match(/<form\b[^>]*>[\s\S]*?<\/form>/gi) ?? []) {
      if (!/<input\b[^>]*\btype\s*=\s*["']?password(?:["'\s>])/i.test(form)) continue
      const opening = /^<form\b[^>]*>/i.exec(form)?.[0] ?? ''
      const action = /\baction\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(opening)
      const target = (action?.[1] ?? action?.[2] ?? action?.[3] ?? '').split(/[?#]/)[0]
      const loginTarget = /(?:^|\/)(?:authserver(?:\/login)?|login(?:\.[a-z0-9]+)?|cas_security_check|j_spring_cas_security_check)\/?$/i.test(target)
      const namedLogin = /\b(?:id|name)\s*=\s*["']?(?:casLoginForm|loginForm|login_form|login-form|fm1)(?:["'\s>])/i.test(opening)
      const legacyUis = /<input\b[^>]*\bname\s*=\s*["']?IDToken1(?:["'\s>])/i.test(form) &&
        /<input\b[^>]*\bname\s*=\s*["']?IDToken2(?:["'\s>])/i.test(form)
      if (loginTarget || namedLogin || legacyUis) return true
    }
    return false
  }

  /** Only a completed service document and session-bearing cookies may close
   * verification. Language, theme and other preference cookies are not SSO. */
  static isServiceDocument(url: string, service: string, body: string, cookies: string): boolean {
    if (!FduAuthPolicy.isServiceLanding(url, service) || !cookies.trim()) return false
    if (FduAuthPolicy.isLoginDocument(body) && !FduAuthPolicy.isLifeCodeDocument(url, body)) return false
    const jsonTarget: string = FduAuthPolicy.zlappJsonTarget(service)
    if (jsonTarget) {
      try {
        const envelope = JSON.parse(body.trim()) as ZlappEnvelopeProof
        const data: ZlappDataProof | undefined = envelope?.d
        if (data === undefined || data === null || typeof data !== 'object' || Array.isArray(data)) return false
        return jsonTarget.endsWith('/fudanbus/wap/default/lists') ? Array.isArray(data.data) :
          data.roomid !== undefined || data.fj_surplus !== undefined || data.fj_used !== undefined
      } catch (error) { return false }
    }
    // Ehall's root is also a public SPA and issues SESS_ID anonymously. Only
    // the original userInfoDSL payload with an actual name proves identity.
    if (FduAuthPolicy.origin(service) === 'https://ehall.fudan.edu.cn') {
      return FduAuthPolicy.hasEhallIdentity(body)
    }
    if (FduAuthPolicy.isWebVpnLoginUrl(service)) {
      // Prefix matching admits vendor host-suffixed ticket names without
      // storing/logging them. Non-session auxiliary cookies cannot finish MFA.
      return FduAuthPolicy.hasWebVpnSession(cookies) &&
        !/<title[^>]*>[^<]*(?:错误|error|unavailable|禁止访问)[^<]*<\/title>/i.test(body)
    }
    return true
  }

  private static hasEhallIdentity(body: string): boolean {
    const marker = /window\s*\.\s*userInfoDSL\s*=\s*\{/.exec(body)
    if (marker === null) return false
    const start = marker.index + marker[0].length - 1
    let depth: number = 0
    let quoted: boolean = false
    let escaped: boolean = false
    for (let index: number = start; index < Math.min(body.length, start + 65536); index++) {
      const value = body.charAt(index)
      if (quoted) {
        if (escaped) escaped = false
        else if (value === '\\') escaped = true
        else if (value === '"') quoted = false
      } else if (value === '"') quoted = true
      else if (value === '{') depth++
      else if (value === '}' && --depth === 0) {
        try {
          const identity = JSON.parse(body.substring(start, index + 1)) as EhallIdentityWire
          const name = typeof identity.name === 'string' ? identity.name.trim() : ''
          return name.length > 0 && name.length <= 100 && !/[\x00-\x1f<>]/.test(name)
        } catch (error) { return false }
      }
    }
    return false
  }

  private static hasWebVpnSession(cookies: string): boolean {
    for (const pair of cookies.split(';')) {
      const eq = pair.indexOf('=')
      if (eq <= 0 || !pair.substring(eq + 1).trim()) continue
      const name = pair.substring(0, eq).trim()
      if (/^(?:show_vpn|vpn_show|lang|language|locale|theme|remember.*|.*csrf.*|.*xsrf.*|.*nonce.*)$/i.test(name)) continue
      if (/session|ticket|token|auth|sid/i.test(name) || /^vpn$/i.test(name)) return true
    }
    return false
  }

  /** The original life-code page can carry an authentication-related title;
   * its QR field or explicit consent screen is service data, not an ID form. */
  static isLifeCodeDocument(url: string, body: string): boolean {
    if (!/^https:\/\/ecard\.fudan\.edu\.cn(?::443)?\/epay\/wxpage\/fudan\/zfm\/qrcode(?:[?#]|$)/i.test(url)) return false
    const field = /<input\b[^>]*\bid\s*=\s*["']myText["'][^>]*>/i.exec(body)
    return (field !== null && /\bvalue\s*=\s*["'][^"']+["']/i.test(field[0])) ||
      /\bid\s*=\s*["']btn-agree-ok["']/i.test(body)
  }

  static splitSetCookies(raw: string): string[] {
    if (!raw) return []
    // A header bridge may join repeated Set-Cookie fields with CRLF/LF.
    // Preserve Expires commas and each value; configCookie accepts one record.
    const records: string[] = []
    for (const line of raw.split(/\r\n|\r|\n/)) {
      for (const piece of line.split(/,\s*(?=[^;,=\s]+=)/)) {
        const record: string = piece.trim()
        if (record) records.push(record)
      }
    }
    return records
  }

  /** Domain cookies can target their source host or a campus parent, never a
   * sibling. Host-only records keep the response URL's original scope. */
  static cookieMatchesUrl(raw: string, target: string): boolean {
    const origin: string = FduAuthPolicy.origin(target)
    if (!origin || /[\r\n]/.test(raw)) return false
    const host: string = origin.replace(/^https?:\/\//, '')
    const attributes: string[] = raw.split(';')
    for (let index: number = 1; index < attributes.length; index++) {
      const attribute: string = attributes[index].trim()
      const eq: number = attribute.indexOf('=')
      if ((eq < 0 ? attribute : attribute.substring(0, eq)).trim().toLowerCase() !== 'domain') continue
      const domain: string = eq < 0 ? '' : attribute.substring(eq + 1).trim().replace(/^\./, '').toLowerCase()
      if (!domain || !/^[a-z0-9.-]+$/.test(domain) || !FduAuthPolicy.isCampusUrl('https://' + domain) ||
        (host !== domain && !host.endsWith('.' + domain))) return false
    }
    return true
  }

  static cookieHeader(rawCookies: string[]): string {
    const values: Map<string, string> = new Map<string, string>()
    for (const raw of rawCookies) {
      for (const chunk of FduAuthPolicy.splitSetCookies(raw)) {
        const pair: string = chunk.split(';')[0].trim()
        const eq: number = pair.indexOf('=')
        if (eq > 0) values.set(pair.substring(0, eq), pair.substring(eq + 1))
      }
    }
    const pairs: string[] = []
    values.forEach((value: string, name: string) => pairs.push(name + '=' + value))
    return pairs.join('; ')
  }

  static resolve(location: string, base: string): string {
    if (location.indexOf('https://') === 0 || location.indexOf('http://') === 0) return location
    if (location.indexOf('//') === 0) return base.split(':')[0] + ':' + location
    if (location.indexOf('/') === 0) return FduAuthPolicy.origin(base) + location
    return base.substring(0, base.lastIndexOf('/') + 1) + location
  }

  /** Preserve the response host while walking redirects; never mix ID and service cookies. */
  static cookiesForOrigin(startUrl: string, hops: Record<string, string>[], origin: string): string[] {
    const cookies: string[] = []
    let current: string = startUrl
    for (const headers of hops) {
      if (FduAuthPolicy.origin(current) === origin) {
        for (const cookie of FduAuthPolicy.splitSetCookies(headers['set-cookie'] ?? '')) {
          if (FduAuthPolicy.cookieMatchesUrl(cookie, current)) cookies.push(cookie)
        }
      }
      const location: string = headers['location'] ?? ''
      if (location.length > 0) current = FduAuthPolicy.resolve(location, current)
    }
    return cookies
  }
}
