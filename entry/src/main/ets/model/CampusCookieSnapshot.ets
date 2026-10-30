import { webview } from '@kit.ArkWeb'
import { FduAuthPolicy } from './FduAuth'

/** Keep the browser's scope and lifetime, including cookies without Expires.
 * Only campus authentication/service cookies belong in the account snapshot. */
export class CampusCookieSnapshot {
  static valid(cookie: webview.WebHttpCookie, now: number = Date.now()): boolean {
    if (cookie === null || typeof cookie !== 'object' ||
      typeof cookie.name !== 'string' || typeof cookie.value !== 'string' ||
      typeof cookie.domain !== 'string' || typeof cookie.path !== 'string' ||
      typeof cookie.expiresDate !== 'string' || typeof cookie.isSessionCookie !== 'boolean' ||
      typeof cookie.isHttpOnly !== 'boolean' || typeof cookie.isSecure !== 'boolean') return false
    if (!/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/.test(cookie.name) || /[\r\n;\x00]/.test(cookie.value) ||
      !/^\/[^;\r\n\x00]*$/.test(cookie.path) || !/^\.?[a-z0-9.-]+$/i.test(cookie.domain)) return false
    const origin = CampusCookieSnapshot.origin(cookie)
    if (!FduAuthPolicy.isCampusUrl(origin)) return false
    if (cookie.name.startsWith('__Host-') && (cookie.domain.startsWith('.') || cookie.path !== '/' || !cookie.isSecure)) return false
    if (cookie.name.startsWith('__Secure-') && !cookie.isSecure) return false
    if (cookie.samesitePolicy !== webview.WebHttpCookieSameSitePolicy.NONE &&
      cookie.samesitePolicy !== webview.WebHttpCookieSameSitePolicy.LAX &&
      cookie.samesitePolicy !== webview.WebHttpCookieSameSitePolicy.STRICT) return false
    return cookie.isSessionCookie || (Number.isFinite(Date.parse(cookie.expiresDate)) && Date.parse(cookie.expiresDate) > now)
  }

  static key(cookie: webview.WebHttpCookie): string {
    return cookie.domain.toLowerCase() + '\n' + cookie.path + '\n' + cookie.name
  }

  static origin(cookie: webview.WebHttpCookie): string {
    const host = cookie.domain.replace(/^\./, '').toLowerCase()
    return (/^(?:yjsxk|yjsxktest)\.fudan\.sh\.cn$/.test(host) && !cookie.isSecure ? 'http://' : 'https://') + host
  }

  static header(cookie: webview.WebHttpCookie): string {
    let raw = cookie.name + '=' + cookie.value + '; Path=' + cookie.path
    // No Domain preserves a host-only cookie. A leading dot denotes the
    // browser's domain cookie; do not widen it to a different campus host.
    if (cookie.domain.startsWith('.')) raw += '; Domain=' + cookie.domain
    if (!cookie.isSessionCookie) raw += '; Expires=' + new Date(cookie.expiresDate).toUTCString()
    if (cookie.isSecure) raw += '; Secure'
    if (cookie.isHttpOnly) raw += '; HttpOnly'
    if (cookie.samesitePolicy === webview.WebHttpCookieSameSitePolicy.STRICT) raw += '; SameSite=Strict'
    else if (cookie.samesitePolicy === webview.WebHttpCookieSameSitePolicy.LAX) raw += '; SameSite=Lax'
    else if (cookie.isSecure) raw += '; SameSite=None'
    return raw
  }
}
