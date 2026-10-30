import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { CourseReviewGroup } from '../model/CourseReview'

class CatalogRow {
  id: number = 0
  name: string = ''
  code: string = ''
  department: string = ''
  campus: string = ''
  weekHour: number | undefined = undefined
  credits: number[] = []
  courseCount: number | undefined = undefined
}
export class CourseReviewCatalogSnapshot {
  schema: number = 1
  owner: number = 0
  at: number = 0
  hash: string = ''
  rows: CatalogRow[] = []
}

/** Private, replaceable directory metadata. No reviews, votes or identity fields. */
export class CourseReviewCatalogStore {
  private static directory: string = ''
  private static writes: Promise<void> = Promise.resolve()
  private static epoch: number = 0
  private static readonly MAX_BYTES: number = 16 * 1024 * 1024
  private static readonly MAX_AGE: number = 7 * 24 * 60 * 60 * 1000
  static init(directory: string): void { CourseReviewCatalogStore.directory = directory }
  private static path(): string { return CourseReviewCatalogStore.directory + '/danta-course-directory-v1.json' }
  static groups(snapshot: CourseReviewCatalogSnapshot): CourseReviewGroup[] {
    return snapshot.rows.map(row => {
      const group = new CourseReviewGroup()
      group.id = row.id; group.name = row.name; group.code = row.code; group.department = row.department
      group.campus = row.campus; group.weekHour = row.weekHour; group.credits = row.credits.slice()
      group.courseCount = row.courseCount
      return group
    })
  }
  static async load(owner: number): Promise<CourseReviewCatalogSnapshot | null> {
    if (!CourseReviewCatalogStore.directory || !Number.isSafeInteger(owner) || owner <= 0) return null
    const epoch = CourseReviewCatalogStore.epoch
    try {
      const stat = await fs.stat(CourseReviewCatalogStore.path())
      if (stat.size <= 0 || stat.size > CourseReviewCatalogStore.MAX_BYTES) return null
      const value = JSON.parse(await fs.readText(CourseReviewCatalogStore.path())) as CourseReviewCatalogSnapshot
      if (epoch !== CourseReviewCatalogStore.epoch || value === null || value.schema !== 1 || value.owner !== owner ||
        !Number.isFinite(value.at) || value.at > Date.now() + 60000 || Date.now() - value.at > CourseReviewCatalogStore.MAX_AGE ||
        typeof value.hash !== 'string' || value.hash.length > 512 || !Array.isArray(value.rows) || value.rows.length > 100000) return null
      const rows: CatalogRow[] = []; const ids = new Set<number>()
      for (const row of value.rows) {
        if (row === null || !Number.isSafeInteger(row.id) || row.id <= 0 || ids.has(row.id) ||
          typeof row.name !== 'string' || !row.name.trim() || row.name.length > 4096 ||
          typeof row.code !== 'string' || row.code.length > 4096 || typeof row.department !== 'string' || row.department.length > 4096 ||
          typeof row.campus !== 'string' || row.campus.length > 4096 || !Array.isArray(row.credits) || row.credits.length > 100 ||
          row.credits.some(credit => typeof credit !== 'number' || !Number.isFinite(credit) || credit < 0) ||
          (row.weekHour !== undefined && (typeof row.weekHour !== 'number' || !Number.isFinite(row.weekHour))) ||
          (row.courseCount !== undefined && (!Number.isSafeInteger(row.courseCount) || row.courseCount < 0))) return null
        const copy = new CatalogRow()
        copy.id = row.id; copy.name = row.name; copy.code = row.code; copy.department = row.department
        copy.campus = row.campus; copy.weekHour = row.weekHour; copy.credits = row.credits.slice(); copy.courseCount = row.courseCount
        rows.push(copy); ids.add(row.id)
      }
      const snapshot = new CourseReviewCatalogSnapshot()
      snapshot.owner = owner; snapshot.at = value.at; snapshot.hash = value.hash; snapshot.rows = rows
      return snapshot
    } catch (e) { return null }
  }
  static save(owner: number, groups: CourseReviewGroup[], hash: string, current: () => boolean): Promise<void> {
    if (!CourseReviewCatalogStore.directory || !Number.isSafeInteger(owner) || owner <= 0 || !current()) return Promise.resolve()
    const epoch = CourseReviewCatalogStore.epoch
    const task = CourseReviewCatalogStore.writes.catch(() => {}).then(async (): Promise<void> => {
      // Release the resolved directory to its caller before constructing a
      // second, metadata-only representation for disk.
      await new Promise<void>(resolve => { setTimeout(resolve, 0) })
      if (epoch !== CourseReviewCatalogStore.epoch || !current()) return
      const snapshot = new CourseReviewCatalogSnapshot()
      snapshot.owner = owner; snapshot.at = Date.now(); snapshot.hash = hash.slice(0, 512)
      snapshot.rows = groups.map(group => {
        const row = new CatalogRow()
        row.id = group.id; row.name = group.name; row.code = group.code; row.department = group.department
        row.campus = group.campus; row.weekHour = group.weekHour; row.credits = group.creditValues()
        row.courseCount = group.courseCount
        return row
      })
      const bytes = new util.TextEncoder().encodeInto(JSON.stringify(snapshot))
      if (bytes.byteLength > CourseReviewCatalogStore.MAX_BYTES) return
      const target = CourseReviewCatalogStore.path(); const temporary = target + '.tmp'
      const file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
      try {
        let written: number = 0
        while (written < bytes.byteLength) {
          const count = await fs.write(file.fd, bytes.buffer.slice(bytes.byteOffset + written, bytes.byteOffset + bytes.byteLength))
          if (count <= 0) throw new Error('Incomplete course directory cache write')
          written += count
        }
      } finally { await fs.close(file) }
      if (epoch !== CourseReviewCatalogStore.epoch || !current()) { await fs.unlink(temporary); return }
      await fs.rename(temporary, target)
      if (epoch !== CourseReviewCatalogStore.epoch || !current()) { try { await fs.unlink(target) } catch (e) {} }
    })
    CourseReviewCatalogStore.writes = task
    return task
  }
  static clear(): Promise<void> {
    CourseReviewCatalogStore.epoch++
    const task = CourseReviewCatalogStore.writes.catch(() => {}).then(async (): Promise<void> => {
      if (!CourseReviewCatalogStore.directory) return
      for (const path of [CourseReviewCatalogStore.path(), CourseReviewCatalogStore.path() + '.tmp']) {
        try { await fs.unlink(path) } catch (e) {}
      }
    })
    CourseReviewCatalogStore.writes = task; return task
  }
}
