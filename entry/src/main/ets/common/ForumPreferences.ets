import { PreferencesUtil } from '../util/PreferencesUtil'

/** Local forum preferences remain separate from the server's folded/notify config. */
export class ForumPreferences {
  static readonly USER_ID: string = 'forum_user_id'
  static readonly HIDDEN_TAGS: string = 'forum_hidden_tags'
  static readonly HISTORY: string = 'forum_view_history'
  static readonly BACKGROUND: string = 'forum_background'
  static readonly SUMMARY: string = 'forum_summary_enabled'
  static readonly SORT: string = 'forum_sort_order'
  static readonly CLEAN: string = 'forum_clean_mode'
  static readonly ACTIVITIES: string = 'forum_activities_enabled'
  static readonly TAG_SUGGESTIONS: string = 'forum_tag_suggestions_enabled'
  private static pending: Promise<void> = Promise.resolve()

  static parseTags(value: string): string[] {
    try {
      const rows = JSON.parse(value) as string[]
      if (!Array.isArray(rows)) return []
      const out: string[] = []
      for (const row of rows) {
        if (typeof row !== 'string') continue
        const name = row.trim().slice(0, 128)
        if (name.length > 0 && !out.includes(name)) out.push(name)
        if (out.length >= 128) break
      }
      return out
    } catch (e) { return [] }
  }
  static parseHistory(value: string): number[] {
    try {
      const rows = JSON.parse(value) as number[]
      if (!Array.isArray(rows)) return []
      const out: number[] = []
      for (const id of rows) {
        if (Number.isSafeInteger(id) && id > 0 && !out.includes(id)) out.push(id)
        if (out.length >= 500) break
      }
      return out
    } catch (e) { return [] }
  }
  static async init(): Promise<void> {
    const prefs = PreferencesUtil.getInstance()
    AppStorage.setOrCreate<string>(ForumPreferences.HIDDEN_TAGS,
      JSON.stringify(ForumPreferences.parseTags(await prefs.getString(ForumPreferences.HIDDEN_TAGS, '[]'))))
    AppStorage.setOrCreate<string>(ForumPreferences.HISTORY,
      JSON.stringify(ForumPreferences.parseHistory(await prefs.getString(ForumPreferences.HISTORY, '[]'))))
    AppStorage.setOrCreate<string>(ForumPreferences.BACKGROUND, await prefs.getString(ForumPreferences.BACKGROUND, ''))
    AppStorage.setOrCreate<boolean>(ForumPreferences.SUMMARY, await prefs.getBoolean(ForumPreferences.SUMMARY, true))
    AppStorage.setOrCreate<boolean>(ForumPreferences.CLEAN, await prefs.getBoolean(ForumPreferences.CLEAN, false))
    AppStorage.setOrCreate<boolean>(ForumPreferences.ACTIVITIES, await prefs.getBoolean(ForumPreferences.ACTIVITIES, true))
    AppStorage.setOrCreate<boolean>(ForumPreferences.TAG_SUGGESTIONS, await prefs.getBoolean(ForumPreferences.TAG_SUGGESTIONS, false))
    const sort = await prefs.getString(ForumPreferences.SORT, 'time_updated')
    AppStorage.setOrCreate<string>(ForumPreferences.SORT, sort === 'time_created' ? sort : 'time_updated')
  }
  static hiddenTags(): string[] { return ForumPreferences.parseTags(AppStorage.get<string>(ForumPreferences.HIDDEN_TAGS) ?? '[]') }
  static history(): number[] { return ForumPreferences.parseHistory(AppStorage.get<string>(ForumPreferences.HISTORY) ?? '[]') }
  /** Exact upstream CleanModeFilter.DELETE_EMOJI; text/profanity filtering is disabled upstream. */
  static clean(content: string, enabled: boolean): string {
    if (!enabled) return content
    let result = content
    for (const emoji of ['😅', '😄', '😋', '🥰', '🤭', '😊', '😍', '😇', '🤗', '😁', '🤤', '😡', '🥵', '🤓']) {
      result = result.split(emoji).join(' ')
    }
    return result
  }
  static async setTags(tags: string[]): Promise<void> {
    await ForumPreferences.write(ForumPreferences.HIDDEN_TAGS, JSON.stringify(ForumPreferences.parseTags(JSON.stringify(tags))))
    AppStorage.setOrCreate<number>('forum_feed_refresh', Date.now())
  }
  static recordVisit(id: number): Promise<void> {
    if (!Number.isSafeInteger(id) || id <= 0) return Promise.resolve()
    const task = ForumPreferences.pending.catch(() => {}).then(async (): Promise<void> => {
      const ids = [id].concat(ForumPreferences.history().filter((old: number) => old !== id)).slice(0, 500)
      const json = JSON.stringify(ids)
      await PreferencesUtil.getInstance().putString(ForumPreferences.HISTORY, json)
      AppStorage.setOrCreate<string>(ForumPreferences.HISTORY, json)
    })
    ForumPreferences.pending = task
    return task
  }
  static clearHistory(): Promise<void> { return ForumPreferences.write(ForumPreferences.HISTORY, '[]') }
  static write(key: string, value: string): Promise<void> {
    const task = ForumPreferences.pending.catch(() => {}).then(async (): Promise<void> => {
      await PreferencesUtil.getInstance().putString(key, value)
      AppStorage.setOrCreate<string>(key, value)
    })
    ForumPreferences.pending = task
    return task
  }
}
