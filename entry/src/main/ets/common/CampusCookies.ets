import { webview } from '@kit.ArkWeb'
import { BusinessError } from '@kit.BasicServicesKit'
import { FduAuthPolicy } from '../model/FduAuth'
import { CampusCookieSnapshot } from '../model/CampusCookieSnapshot'
import { CampusSessionStore } from './CampusSessionStore'

/** Browser is the domain/path-aware cookie jar shared by CAS and campus APIs. */
export class CampusCookies {
  private static enabled: boolean = false
  private static epoch: number = 0
  private static writes: Promise<void> = Promise.resolve()
  private static owner: string = ''
  private static restoring: Promise<void> | null = null
  private static persisting: Promise<void> | null = null
  private static savedSnapshot: string = ''
  private static restoreDetails: string = 'cookieRestore=not-started'

  static diagnostics(): string { return CampusCookies.restoreDetails }

  static resume(): void {
    CampusCookies.enabled = true
    if (CampusCookies.restoreDetails === 'cookieRestore=cleared') {
      CampusCookies.restoreDetails = 'cookieRestore=not-run; jarEnabled=true; priorSnapshot=cleared'
    }
  }
  static suspend(): void {
    CampusCookies.enabled = false
    CampusCookies.owner = ''; CampusCookies.savedSnapshot = ''; CampusCookies.epoch++
    CampusCookies.restoreDetails = 'cookieRestore=cleared'
    // Ordered after an in-flight save, before another account can import.
    CampusCookies.writes = CampusCookies.writes.catch(() => {}).then(() => CampusSessionStore.clear()).catch(() => {})
  }
  static generation(): number { return CampusCookies.epoch }

  static bind(owner: string): void { CampusCookies.owner = owner }

  /** Called before publishing the restored account or starting campus reads. */
  static async restore(owner: string): Promise<void> {
    CampusCookies.owner = owner; CampusCookies.enabled = true
    const epoch = CampusCookies.epoch
    const task = CampusCookies.writes.catch(() => {}).then(async (): Promise<void> => {
      let loaded: number = 0
      let presentCount: number = -1
      let rejected: number = 0
      let imported: number = 0
      let importFailed: number = 0
      let importCode: number = 0
      let idCandidates: number = -1
      let outcome: string = 'complete'
      try {
        const saved = await CampusSessionStore.load(owner)
        if (epoch !== CampusCookies.epoch || CampusCookies.owner !== owner || !CampusCookies.enabled) return
        loaded = saved.length
        if (saved.length === 0) return
        const current = await webview.WebCookieManager.fetchAllCookies(false)
        const present = new Set<string>()
        idCandidates = 0
        for (const cookie of current) if (CampusCookieSnapshot.valid(cookie)) {
          present.add(CampusCookieSnapshot.key(cookie))
          if (FduAuthPolicy.isIdUrl(CampusCookieSnapshot.origin(cookie))) idCandidates++
        }
        presentCount = present.size
        for (const cookie of saved) {
          if (epoch !== CampusCookies.epoch || CampusCookies.owner !== owner || !CampusCookies.enabled) return
          if (!CampusCookieSnapshot.valid(cookie)) { rejected++; continue }
          if (present.has(CampusCookieSnapshot.key(cookie))) continue
          try {
            await webview.WebCookieManager.configCookie(CampusCookieSnapshot.origin(cookie) + cookie.path,
              CampusCookieSnapshot.header(cookie), false, true)
            imported++
            if (FduAuthPolicy.isIdUrl(CampusCookieSnapshot.origin(cookie))) idCandidates++
          } catch (error) {
            // One legacy/unimportable record must not suppress unrelated ID
            // and service sessions. Explicit verification still requires every
            // necessary Cookie through importVerification below.
            importFailed++
            if (importCode === 0) {
              const code = (error as BusinessError).code
              importCode = typeof code === 'number' && Number.isFinite(code) ? code : 0
            }
            outcome = 'partial-import'
          }
        }
      } catch (e) {
        outcome = 'import-failed'
        // A locked/unavailable secure store must not erase working browser SSO.
      } finally {
        if (epoch === CampusCookies.epoch && CampusCookies.owner === owner && CampusCookies.enabled) {
          const store = typeof CampusSessionStore.diagnostics === 'function' ? CampusSessionStore.diagnostics() : ''
          CampusCookies.restoreDetails = 'cookieRestore=' + outcome + '; savedCount=' + String(loaded) +
            '; presentCount=' + (presentCount < 0 ? 'unknown' : String(presentCount)) + '; filteredCount=' + String(rejected) +
            '; importedCount=' + String(imported) + '; idCandidateCount=' + (idCandidates < 0 ? 'unknown' : String(idCandidates)) + (store ? '; ' + store : '')
          CampusCookies.restoreDetails += '; importFailedCount=' + String(importFailed) + '; importCode=' + String(importCode)
        }
      }
    })
    CampusCookies.writes = task; CampusCookies.restoring = task
    try { await task } finally { if (CampusCookies.restoring === task) CampusCookies.restoring = null }
  }

  static async clearBrowser(onClearing?: () => void): Promise<void> {
    const task = CampusCookies.writes.catch(() => {}).then(async (): Promise<void> => {
      if (onClearing !== undefined) onClearing()
      await webview.WebCookieManager.clearAllCookies()
    })
    CampusCookies.writes = task
    await task
  }

  /** Keep uncancellable verification writes ahead of logout clearing, even if
   * the page stops waiting. Never import the next Cookie after its request ends. */
  static async importVerification(records: string[], epoch: number, isActive: () => boolean,
    onCompleted: (count: number) => void): Promise<void> {
    const task = CampusCookies.writes.catch(() => {}).then(async (): Promise<void> => {
      for (let index: number = 0; index < records.length; index++) {
        if (epoch !== CampusCookies.epoch || !CampusCookies.enabled || !isActive()) return
        if (!FduAuthPolicy.cookieMatchesUrl(records[index], FduAuthPolicy.ID_ORIGIN)) {
          throw new Error('身份验证 Cookie 范围无效，请重新验证。')
        }
        await webview.WebCookieManager.configCookie(FduAuthPolicy.ID_ORIGIN + '/', records[index], false, true)
        if (epoch !== CampusCookies.epoch || !isActive()) return
        onCompleted(index + 1)
      }
    })
    CampusCookies.writes = task
    await task
  }

  static async read(url: string): Promise<string> {
    // Forum/public requests do not use this jar or its restoration barrier.
    if (!FduAuthPolicy.isCampusUrl(url)) return ''
    if (CampusCookies.restoring !== null) await CampusCookies.restoring
    if (!CampusCookies.enabled) return ''
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
    // Join only while this exact flush remains the write tail. A later import
    // must still receive its own following durable snapshot before returning.
    if (CampusCookies.persisting !== null && CampusCookies.writes === CampusCookies.persisting) return CampusCookies.persisting
    const epoch = CampusCookies.epoch
    const owner = CampusCookies.owner
    const task = CampusCookies.writes.catch(() => {}).then(async (): Promise<void> => {
      if (epoch !== CampusCookies.epoch || !CampusCookies.enabled) return
      try { await webview.WebCookieManager.saveCookieAsync() } catch (e) {}
      if (!owner) return
      try {
        const cookies = (await webview.WebCookieManager.fetchAllCookies(false)).filter(
          (cookie: webview.WebHttpCookie): boolean => CampusCookieSnapshot.valid(cookie))
        if (epoch !== CampusCookies.epoch || CampusCookies.owner !== owner || !CampusCookies.enabled) return
        const snapshot = JSON.stringify(cookies)
        if (snapshot === CampusCookies.savedSnapshot) return
        await CampusSessionStore.save(owner, cookies)
        if (epoch === CampusCookies.epoch && CampusCookies.owner === owner) CampusCookies.savedSnapshot = snapshot
      } catch (e) {}
    })
    CampusCookies.writes = task; CampusCookies.persisting = task
    try { await task } finally { if (CampusCookies.persisting === task) CampusCookies.persisting = null }
  }

  static async absorb(startUrl: string, hops: Record<string, string>[], epoch: number): Promise<void> {
    if (epoch !== CampusCookies.epoch || !CampusCookies.enabled || !CampusCookies.hasCampusCookies(startUrl, hops)) return
    const task = CampusCookies.writes.catch(() => {}).then(() => CampusCookies.absorbOnce(startUrl, hops, epoch))
    CampusCookies.writes = task
    await task
  }

  private static hasCampusCookies(startUrl: string, hops: Record<string, string>[]): boolean {
    // A non-campus entry may redirect through CAS and back. Match each
    // response's actual URL, using the same walk as cookie import below.
    let url = startUrl
    for (const headers of hops) {
      if (FduAuthPolicy.isCampusUrl(url) && FduAuthPolicy.splitSetCookies(headers['set-cookie'] ?? '')
        .some((raw: string): boolean => raw.trim().length > 0)) return true
      const location = headers['location'] ?? ''
      if (location) url = FduAuthPolicy.resolve(location, url)
    }
    return false
  }

  private static async absorbOnce(startUrl: string, hops: Record<string, string>[], epoch: number): Promise<void> {
    let url = startUrl
    for (const headers of hops) {
      if (epoch !== CampusCookies.epoch || !CampusCookies.enabled) return
      if (FduAuthPolicy.isCampusUrl(url)) {
        for (const raw of FduAuthPolicy.splitSetCookies(headers['set-cookie'] ?? '')) {
          if (epoch !== CampusCookies.epoch) return
          if (!FduAuthPolicy.cookieMatchesUrl(raw, url)) continue
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
