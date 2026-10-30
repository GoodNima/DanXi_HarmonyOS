import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { HttpError, HttpResponse, HttpUtil } from '../util/HttpUtil'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { Constant } from './Constant'
import { AnnouncementSnapshot, AnnouncementConfigParser } from '../model/AnnouncementConfigData'

class AnnouncementCache { source: string = ''; text: string = ''; updatedAt: number = 0 }

/** One public source/flight shared by forum activities and campus celebrations. */
export class AnnouncementConfig {
  static readonly URL: string = 'https://danxi-static.fduhole.com/tmp_wait_for_json_editor.toml'
  static readonly KEY_REVISION: string = 'announcement_config_revision'
  private static readonly CACHE: string = 'announcement_public_config_v1'
  private static readonly READ_BUDGET_MS: number = 25000
  private static readonly FIRST_READ_MS: number = 15000
  private static snapshot: AnnouncementSnapshot = new AnnouncementSnapshot()
  private static restored: boolean = false
  private static pending: Promise<AnnouncementSnapshot> | null = null
  private static checkedAt: number = 0
  private static cacheWrites: Promise<void> = Promise.resolve()

  static peek(): AnnouncementSnapshot { return AnnouncementConfig.snapshot }
  static async load(force: boolean = false): Promise<AnnouncementSnapshot> {
    if (AnnouncementConfig.pending !== null) return AnnouncementConfig.pending
    // A transient failure must not occupy the successful five-minute cache window.
    // Retry on a later consumer entry, with a short cooldown and the same single flight.
    const ttl: number = AnnouncementConfig.snapshot.error ? 30000 : 5 * 60000
    const age: number = Date.now() - AnnouncementConfig.checkedAt
    if (!force && AnnouncementConfig.checkedAt > 0 && age >= 0 && age < ttl) return AnnouncementConfig.snapshot
    const pending = AnnouncementConfig.refresh()
    AnnouncementConfig.pending = pending
    try { return await pending } finally { if (AnnouncementConfig.pending === pending) AnnouncementConfig.pending = null }
  }

  private static async refresh(): Promise<AnnouncementSnapshot> {
    const loading = AnnouncementConfig.copySnapshot()
    loading.loading = true
    loading.error = ''
    AnnouncementConfig.publish(loading)
    if (!AnnouncementConfig.restored) {
      AnnouncementConfig.restored = true
      try {
        const stored = JSON.parse(await PreferencesUtil.getInstance().getString(AnnouncementConfig.CACHE, '{}')) as AnnouncementCache
        const age: number = Date.now() - stored.updatedAt
        if (stored.source === AnnouncementConfig.URL && Number.isFinite(age) && age >= 0 && age <= 7 * 86400000) {
          const parsed = AnnouncementConfigParser.parse(stored.text)
          parsed.cachedAt = stored.updatedAt
          parsed.loading = true
          AnnouncementConfig.publish(parsed)
        }
      } catch (e) {}
    }
    try {
      const response = await AnnouncementConfig.read()
      const parsed = AnnouncementConfigParser.parse(response.data)
      parsed.cachedAt = Date.now()
      parsed.checkedAt = parsed.cachedAt
      AnnouncementConfig.checkedAt = parsed.checkedAt
      const cache = new AnnouncementCache()
      cache.source = AnnouncementConfig.URL; cache.text = response.data; cache.updatedAt = parsed.cachedAt
      // Optional disk persistence must not keep genuine network data loading.
      // Preserve write order while later explicit refreshes can proceed.
      AnnouncementConfig.cacheWrites = AnnouncementConfig.cacheWrites.catch(() => {}).then(async (): Promise<void> => {
        try { await PreferencesUtil.getInstance().putString(AnnouncementConfig.CACHE, JSON.stringify(cache)) }
        catch (e) { console.warn('AnnouncementConfig: public cache write failed') }
      })
      AnnouncementConfig.publish(parsed)
    } catch (e) {
      const old = AnnouncementConfig.snapshot
      const next = new AnnouncementSnapshot()
      // Expired banners must disappear even if the app remains running for days.
      if (old.cachedAt > 0 && Date.now() - old.cachedAt <= 7 * 86400000) {
        next.banners = old.banners; next.celebrations = old.celebrations; next.notices = old.notices; next.cachedAt = old.cachedAt
      }
      next.error = ErrorDiagnostics.message(e as Object)
      next.checkedAt = Date.now()
      AnnouncementConfig.checkedAt = next.checkedAt
      AnnouncementConfig.publish(next)
    }
    return AnnouncementConfig.snapshot
  }

  private static async read(): Promise<HttpResponse> {
    // Public, repeatable GET only. Keep this recovery out of authenticated APIs
    // and writes, and leave genuine HTTP, TLS and configuration errors intact.
    const headers: Record<string, string> = {
      'Accept': 'text/plain, application/toml, */*',
      'User-Agent': Constant.USER_AGENT,
      'Cache-Control': 'no-cache',
    }
    const started: number = Date.now()
    let previous: HttpError
    try {
      return await HttpUtil.getInstance().get(AnnouncementConfig.URL, undefined, headers, AnnouncementConfig.FIRST_READ_MS)
    } catch (e) {
      if (!(e instanceof HttpError) || !e.isNetworkFailure() || e.authenticationRecovery ||
        ![0, 2300005, 2300006, 2300007, 2300028, 2300052, 2300055, 2300056, 2300999].includes(e.code)) throw e as Error
      previous = e
    }
    const remaining: number = AnnouncementConfig.READ_BUDGET_MS - (Date.now() - started)
    if (remaining <= 0) throw previous
    try {
      return await HttpUtil.getInstance().get(AnnouncementConfig.URL, undefined, headers, remaining, true)
    } catch (e) {
      if (e instanceof HttpError) {
        e.diagnostics = ('Announcement config read: attempt=2; totalBudgetMs=' + String(AnnouncementConfig.READ_BUDGET_MS) +
          '; elapsedMs=' + String(Date.now() - started) + '\nPrevious attempt\n' + previous.diagnostics +
          '\nCurrent attempt\n' + e.diagnostics).slice(0, 12000)
      }
      throw e as Error
    }
  }

  private static copySnapshot(): AnnouncementSnapshot {
    const old = AnnouncementConfig.snapshot
    const copy = new AnnouncementSnapshot()
    copy.banners = old.banners.slice()
    copy.celebrations = old.celebrations.slice()
    copy.notices = old.notices.slice()
    copy.cachedAt = old.cachedAt
    copy.checkedAt = old.checkedAt
    copy.error = old.error
    return copy
  }
  private static publish(snapshot: AnnouncementSnapshot): void {
    AnnouncementConfig.snapshot = snapshot
    AppStorage.setOrCreate<number>(AnnouncementConfig.KEY_REVISION, (AppStorage.get<number>(AnnouncementConfig.KEY_REVISION) ?? 0) + 1)
  }
}
