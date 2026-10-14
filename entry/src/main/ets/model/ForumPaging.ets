import { ForumFloor } from './Forum'

/** Keep existing callers' three-row reserve; feeds can request a larger lead. */
export function shouldPrefetch(end: number, count: number, reserve: number = 3): boolean {
  return end >= 0 && end >= Math.max(0, count - 1 - Math.max(0, reserve))
}

/** Offset follows server rows; duplicate boundaries must not duplicate cards. */
export class ForumFloorFeed {
  floors: ForumFloor[] = []
  offset: number = 0
  hasMore: boolean = true

  append(raw: ForumFloor[], pageSize: number): void {
    this.offset += raw.length
    const known: Set<number> = new Set<number>(this.floors.map((floor: ForumFloor) => floor.floorId))
    let added: number = 0
    for (const floor of raw) {
      if (!known.has(floor.floorId)) {
        known.add(floor.floorId)
        this.floors.push(floor)
        added++
      }
    }
    this.hasMore = raw.length >= pageSize && added > 0
  }
}
