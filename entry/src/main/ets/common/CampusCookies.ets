import { webview } from '@kit.ArkWeb'
import { FduAuthPolicy } from '../model/FduAuth'

/** Browser is the domain/path-aware cookie jar shared by CAS and campus APIs. */
export class CampusCookies {
  private static enabled: boolean = false
  private static epoch: number = 0
  private static writes: Promise<void> = Promise.resolve()

  static resume(): void { CampusCookies.enabled = true }
  static suspend(): void { CampusCookies.enabled = false; CampusCookies.epoch++ }
  static generation(): number { return CampusCookies.epoch }

  static async clearBrowser(): Promise<void> {
    await CampusCookies.writes.catch(() => {})
    await webview.WebCookieManager.clearAllCookies()
  }

  static async read(url: string): Promise<string> {
    if (!CampusCookies.enabled || !FduAuthPolicy.isCampusUrl(url)) return ''
    const epoch = CampusCookies.epoch
    try {
      const cookies = await webview.WebCookieManager.fetchCookie(url)
      return epoch === CampusCookies.epoch && CampusCookies.enabled ? cookies : ''
    } catch (e) { return '' }
  }

  /** CAS session cookies may be scoped to /idp rather than the host root.
   * This only checks local state; the actual request still reads its own path. */
  static async hasIdSession(): Promise<boolean> {
    for (const path of ['/idp/authCenter/authenticate', '/ac-h5/', '/ac/']) {
      if (await CampusCookies.read(FduAuthPolicy.ID_ORIGIN + path)) return true
    }
    return false
  }

  /** Native cookies otherwise flush periodically. Commit completed SSO before
   * returning to the app, so an immediate process exit retains the shared jar.
   * Serialize with imports/logout and never make disk failure a login failure. */
  static async persist(): Promise<void> {
    const epoch = CampusCookies.epoch
    const task = CampusCookies.writes.catch(() => {}).then(async (): Promise<void> => {
      if (epoch !== CampusCookies.epoch || !CampusCookies.enabled) return
      try { await webview.WebCookieManager.saveCookieAsync() } catch (e) {}
    })
    CampusCookies.writes = task
    await task
  }

  static async absorb(startUrl: string, hops: Record<string, string>[], epoch: number): Promise<void> {
    const task = CampusCookies.writes.catch(() => {}).then(() => CampusCookies.absorbOnce(startUrl, hops, epoch))
    CampusCookies.writes = task
    await task
  }

  private static async absorbOnce(startUrl: string, hops: Record<string, string>[], epoch: number): Promise<void> {
    let url = startUrl
    for (const headers of hops) {
      if (epoch !== CampusCookies.epoch || !CampusCookies.enabled) return
      if (FduAuthPolicy.isCampusUrl(url)) {
        for (const raw of FduAuthPolicy.splitSetCookies(headers['set-cookie'] ?? '')) {
          if (epoch !== CampusCookies.epoch) return
          // Keep Domain, Path, HttpOnly, Secure, expiration and deletion semantics.
          // API 14+ explicitly permits rotation of HttpOnly session cookies.
          try { await webview.WebCookieManager.configCookie(url, raw, false, true) } catch (e) {}
        }
      }
      const location = headers['location'] ?? ''
      if (location) url = FduAuthPolicy.resolve(location, url)
    }
  }

}
