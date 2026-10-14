import { PreferencesUtil } from '../util/PreferencesUtil'

/** Floor identity survives inserts/deletions; server index allows a small resume window. */
export class ForumReadingPosition {
  owner: number = 0
  holeId: number = 0
  floorId: number = 0
  index: number = 0
  offset: number = 0
  updated: number = 0
}

export class ForumReadingProgress {
  static readonly KEY: string = 'forum_reading_positions'
  private static rows: ForumReadingPosition[] = []
  private static ready: Promise<void> | undefined = undefined
  private static writes: Promise<void> = Promise.resolve()

  static parse(value: string): ForumReadingPosition[] {
    try {
      const rows = JSON.parse(value) as ForumReadingPosition[]
      if (!Array.isArray(rows)) return []
      const valid: ForumReadingPosition[] = []
      const seen: Set<string> = new Set<string>()
      for (const row of rows) {
        if (row === null || typeof row !== 'object' || !Number.isSafeInteger(row.owner) || row.owner < 0 ||
          !Number.isSafeInteger(row.holeId) || row.holeId <= 0 || !Number.isSafeInteger(row.floorId) || row.floorId <= 0 ||
          !Number.isSafeInteger(row.index) || row.index < 0 || row.index > 1000000 ||
          !Number.isFinite(row.offset) || row.offset < 0 || row.offset > 1000000 || !Number.isFinite(row.updated)) continue
        const key: string = row.owner + ':' + row.holeId
        if (!seen.has(key)) { valid.push(row); seen.add(key) }
        if (valid.length >= 300) break
      }
      return valid
    } catch (e) { return [] }
  }

  private static init(): Promise<void> {
    if (ForumReadingProgress.ready === undefined) {
      ForumReadingProgress.ready = PreferencesUtil.getInstance().getString(ForumReadingProgress.KEY, '[]').then((value: string) => {
        ForumReadingProgress.rows = ForumReadingProgress.parse(value)
      })
    }
    return ForumReadingProgress.ready
  }

  static async read(owner: number, holeId: number): Promise<ForumReadingPosition | null> {
    await ForumReadingProgress.init()
    return ForumReadingProgress.rows.find((row: ForumReadingPosition) => row.owner === owner && row.holeId === holeId) ?? null
  }

  static async save(position: ForumReadingPosition): Promise<void> {
    await ForumReadingProgress.init()
    if (ForumReadingProgress.parse(JSON.stringify([position])).length === 0) return
    const old = ForumReadingProgress.rows.find((row: ForumReadingPosition) => row.owner === position.owner && row.holeId === position.holeId)
    if (old !== undefined && old.floorId === position.floorId && old.index === position.index && Math.abs(old.offset - position.offset) < 1) return
    // Publish in memory immediately so a fast back/reopen never waits for disk flush.
    ForumReadingProgress.rows = [position].concat(ForumReadingProgress.rows.filter((row: ForumReadingPosition) =>
      row.owner !== position.owner || row.holeId !== position.holeId)).slice(0, 300)
    const value: string = JSON.stringify(ForumReadingProgress.rows)
    const task = ForumReadingProgress.writes.catch(() => {}).then(() => PreferencesUtil.getInstance().putString(ForumReadingProgress.KEY, value))
    ForumReadingProgress.writes = task
    await task
  }
}
