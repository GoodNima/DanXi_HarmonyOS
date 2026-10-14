import { ForumFloor, ForumHole } from './Forum'
import { ForumDetailSource } from './ForumDetail'

export class ForumFloorWindow {
  start: number
  floors: ForumFloor[]
  exact: boolean
  constructor(start: number, floors: ForumFloor[], exact: boolean = true) {
    this.start = start; this.floors = floors; this.exact = exact
  }
}

/** Target windows stay small regardless of thread length. Backend ListModel
 * defaults to id ASC; ranking starts at 1 (models/floor.go Create). Older
 * payloads without ranking use bounded ID probes, never size=0/full bodies. */
export class ForumFloorLocator {
  static readonly PAGE_SIZE: number = 10
  static readonly LATEST_SIZE: number = 80
  private static readonly MAX_OFFSET: number = 1000000

  private static async rows(source: ForumDetailSource, hole: number, offset: number, size: number,
    current: () => boolean): Promise<ForumFloor[]> {
    if (!current()) throw new Error('Obsolete floor location')
    const rows: ForumFloor[] = await source.getFloors(hole, offset, size)
    if (!current()) throw new Error('Obsolete floor location')
    return rows
  }

  static async locate(source: ForumDetailSource, hole: ForumHole, id: number, ranking: number,
    current: () => boolean): Promise<ForumFloorWindow> {
    if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Invalid floor location')
    if (Number.isSafeInteger(ranking) && ranking > 0 && ranking <= ForumFloorLocator.MAX_OFFSET) {
      const start: number = Math.max(0, ranking - 4)
      const rows: ForumFloor[] = await ForumFloorLocator.rows(source, hole.holeId, start, ForumFloorLocator.PAGE_SIZE, current)
      if (rows.some((floor: ForumFloor) => floor.floorId === id)) return new ForumFloorWindow(start, rows)
    }
    let low: number = 0
    let high: number = Math.min(ForumFloorLocator.MAX_OFFSET, Math.max(10, hole.reply + 1))
    // Counts can be stale while a thread is receiving replies. Establish an
    // empty/greater-ID upper boundary before doing the binary search.
    while (high < ForumFloorLocator.MAX_OFFSET) {
      const rows: ForumFloor[] = await ForumFloorLocator.rows(source, hole.holeId, high, 1, current)
      if (rows.length === 0 || rows[0].floorId >= id) break
      low = high + 1; high = Math.min(ForumFloorLocator.MAX_OFFSET, high * 2)
    }
    while (low < high) {
      const mid: number = Math.floor((low + high) / 2)
      const rows: ForumFloor[] = await ForumFloorLocator.rows(source, hole.holeId, mid, 1, current)
      if (rows.length === 0 || rows[0].floorId >= id) high = mid
      else low = mid + 1
    }
    const start: number = Math.max(0, low - 3)
    const rows: ForumFloor[] = await ForumFloorLocator.rows(source, hole.holeId, start, ForumFloorLocator.PAGE_SIZE, current)
    return new ForumFloorWindow(start, rows, rows.some((floor: ForumFloor) => floor.floorId === id))
  }

  static async latest(source: ForumDetailSource, hole: ForumHole, current: () => boolean): Promise<ForumFloorWindow> {
    // Find the end even when reply counts are stale or the final floor was
    // purged. Keep a bounded preceding buffer so reading upwards starts with
    // complete rows instead of immediately reaching a ten-row loading edge.
    const hint: number = Math.max(0, Math.min(ForumFloorLocator.MAX_OFFSET,
      hole.reply - ForumFloorLocator.LATEST_SIZE))
    const tail: ForumFloor[] = await ForumFloorLocator.rows(source, hole.holeId, hint, ForumFloorLocator.LATEST_SIZE, current)
    if (tail.length > 0 && (tail.length < ForumFloorLocator.LATEST_SIZE ||
      (await ForumFloorLocator.rows(source, hole.holeId, hint + tail.length, 1, current)).length === 0)) {
      return new ForumFloorWindow(hint, tail)
    }
    let low: number = 0
    let high: number = Math.min(ForumFloorLocator.MAX_OFFSET, Math.max(10, hole.reply + 1))
    while (high < ForumFloorLocator.MAX_OFFSET) {
      if ((await ForumFloorLocator.rows(source, hole.holeId, high, 1, current)).length === 0) break
      low = high + 1; high = Math.min(ForumFloorLocator.MAX_OFFSET, high * 2)
    }
    while (low < high) {
      const mid: number = Math.floor((low + high) / 2)
      if ((await ForumFloorLocator.rows(source, hole.holeId, mid, 1, current)).length === 0) high = mid
      else low = mid + 1
    }
    const start: number = Math.max(0, low - ForumFloorLocator.LATEST_SIZE)
    return new ForumFloorWindow(start,
      await ForumFloorLocator.rows(source, hole.holeId, start, ForumFloorLocator.LATEST_SIZE, current))
  }
}
