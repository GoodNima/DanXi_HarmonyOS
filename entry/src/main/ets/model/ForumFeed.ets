import { ForumHole } from './Forum'

/** Keep pagination independent of the caution-content display filter. */
export class ForumFeed {
  holes: ForumHole[] = []
  cursor: number = Date.now()
  hasMore: boolean = true

  append(raw: ForumHole[], pageSize: number, order: string = 'time_updated'): void {
    if (raw.length === 0) {
      this.hasMore = false
      return
    }
    const last: ForumHole = raw[raw.length - 1]
    const next: number = Date.parse(order === 'time_created' ? last.timeCreated : last.timeUpdated || last.timeCreated)
    // A non-advancing cursor must not repeatedly request the same page.
    this.hasMore = raw.length >= pageSize && Number.isFinite(next) && next < this.cursor
    if (Number.isFinite(next)) this.cursor = next
    const known: Set<number> = new Set<number>(this.holes.map((hole: ForumHole) => hole.holeId))
    for (const hole of raw) {
      if (!known.has(hole.holeId)) {
        known.add(hole.holeId)
        this.holes.push(hole)
      }
    }
  }
}
