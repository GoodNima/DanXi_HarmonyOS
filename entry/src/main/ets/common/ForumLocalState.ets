import { PreferencesUtil } from '../util/PreferencesUtil'

/** Local hide mirrors upstream hiddenHole. It never deletes a server post. */
export class ForumLocalState {
  static readonly KEY: string = 'forum_hidden_holes'
  private static pending: Promise<void> = Promise.resolve()
  static async restore(): Promise<void> {
    const value = await PreferencesUtil.getInstance().getString(ForumLocalState.KEY, '[]')
    let ids: number[] = []
    try {
      const json = JSON.parse(value) as number[]
      if (Array.isArray(json)) ids = json.filter((id: number) => Number.isSafeInteger(id) && id > 0)
    } catch (e) {}
    AppStorage.setOrCreate<number[]>(ForumLocalState.KEY, ids)
  }
  static hide(id: number): Promise<void> {
    if (!Number.isSafeInteger(id) || id <= 0) return Promise.reject(new Error('Invalid hole ID'))
    const task = ForumLocalState.pending.then(() => ForumLocalState.writeHidden(id))
    ForumLocalState.pending = task.catch(() => {})
    return task
  }
  private static async writeHidden(id: number): Promise<void> {
    const ids = (AppStorage.get<number[]>(ForumLocalState.KEY) ?? []).slice()
    if (!ids.includes(id)) ids.push(id)
    await PreferencesUtil.getInstance().putString(ForumLocalState.KEY, JSON.stringify(ids))
    AppStorage.setOrCreate<number[]>(ForumLocalState.KEY, ids)
    AppStorage.setOrCreate<number>('forum_feed_refresh', Date.now())
  }
  static hidden(id: number): boolean { return (AppStorage.get<number[]>(ForumLocalState.KEY) ?? []).includes(id) }
  static clear(): Promise<void> {
    const task = ForumLocalState.pending.then(() => ForumLocalState.clearSaved())
    ForumLocalState.pending = task.catch(() => {})
    return task
  }
  private static async clearSaved(): Promise<void> {
    await PreferencesUtil.getInstance().putString(ForumLocalState.KEY, '[]')
    AppStorage.setOrCreate<number[]>(ForumLocalState.KEY, [])
    AppStorage.setOrCreate<number>('forum_feed_refresh', Date.now())
  }
}
