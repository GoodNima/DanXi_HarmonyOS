import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { HttpUtil } from '../util/HttpUtil'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { Constant } from './Constant'
import { AnnouncementSnapshot, AnnouncementConfigParser } from '../model/AnnouncementConfigData'

class AnnouncementCache { source: string = ''; text: string = ''; updatedAt: number = 0 }

/** One public source/flight shared by forum activities and campus celebrations. */
export class AnnouncementConfig {
  static readonly URL: string = 'https://danxi-static.fduhole.com/tmp_wait_for_json_editor.toml'
  static readonly KEY_REVISION: string = 'announcement_config_revision'
  private static readonly CACHE: string = 'announcement_public_config_v1'
  private static snapshot: AnnouncementSnapshot = new AnnouncementSnapshot()
  private static restored: boolean = false
  private static pending: Promise<AnnouncementSnapshot> | null = null
  private static checkedAt: number = 0

  static peek(): AnnouncementSnapshot { return AnnouncementConfig.snapshot }
  static async load(force: boolean = false): Promise<AnnouncementSnapshot> {
    if (AnnouncementConfig.pending !== null) return AnnouncementConfig.pending
    if (!force && AnnouncementConfig.checkedAt > 0 && Date.now() - AnnouncementConfig.checkedAt < 5 * 60000) return AnnouncementConfig.snapshot
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
    AnnouncementConfig.checkedAt = Date.now()
    try {
      // HttpUtil's host-specific token provider sends no campus/forum JWT here.
      const headers: Record<string, string> = {
        'Accept': 'text/plain, application/toml, */*',
        'User-Agent': Constant.USER_AGENT,
      }
      const response = await HttpUtil.getInstance().get(AnnouncementConfig.URL, undefined, headers, 8000)
      const parsed = AnnouncementConfigParser.parse(response.data)
      parsed.cachedAt = Date.now()
      parsed.checkedAt = parsed.cachedAt
      const cache = new AnnouncementCache()
      cache.source = AnnouncementConfig.URL; cache.text = response.data; cache.updatedAt = parsed.cachedAt
      // A cache-write failure cannot erase a successfully fetched public config.
      // The current process can still display it; a later cold start will retry.
      try { await PreferencesUtil.getInstance().putString(AnnouncementConfig.CACHE, JSON.stringify(cache)) }
      catch (e) { console.warn('AnnouncementConfig: public cache write failed') }
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
      AnnouncementConfig.publish(next)
    }
    return AnnouncementConfig.snapshot
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
