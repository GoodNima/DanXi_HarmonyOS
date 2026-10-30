import { CourseReviewGroup, CourseReviewSummary } from '../model/CourseReview'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'

/** A bounded viewport queue keeps prefetch active during native scrolling.
 * Compact results are committed one row per turn, including after scroll stop. */
export class CourseReviewSummaryLoader {
  private scope: string = ''
  private revision: number = 0
  private running: number = 0
  private enabled: boolean = false
  private scrolling: boolean = false
  private queue: CourseReviewGroup[] = []
  private pending: Set<number> = new Set<number>()
  private cache: Map<number, CourseReviewSummary> = new Map<number, CourseReviewSummary>()
  private failed: Set<number> = new Set<number>()
  private rows: CourseReviewGroup[] = []
  private first: number = 0
  private last: number = 3
  private viewport: Map<number, CourseReviewGroup> = new Map<number, CourseReviewGroup>()
  private publications: Map<number, CourseReviewSummary> = new Map<number, CourseReviewSummary>()
  private published: Map<number, CourseReviewSummary> = new Map<number, CourseReviewSummary>()
  private publishedCourseCounts: Map<number, number | undefined> = new Map<number, number | undefined>()
  private viewportTimer: number = -1
  private publishTimer: number = -1
  private pumpTimer: number = -1
  private viewportAt: number = -80
  private readAt: number = -80
  private publishedAt: number = -80
  private read: (id: number) => Promise<CourseReviewGroup>
  private publish: (id: number, summary: CourseReviewSummary) => void
  constructor(read: (id: number) => Promise<CourseReviewGroup>, publish: (id: number, summary: CourseReviewSummary) => void) {
    this.read = read; this.publish = publish
  }
  reset(): void {
    this.clearTimers()
    this.revision++; this.queue = []; this.rows = []; this.viewport.clear()
    this.cache.clear(); this.failed.clear(); this.pending.clear(); this.publications.clear(); this.published.clear(); this.publishedCourseCounts.clear()
  }
  pause(): void {
    this.enabled = false; this.scrolling = false; this.queue = []; this.rows = []
    this.viewport.clear(); this.publications.clear(); this.clearTimers()
  }
  setScrolling(scrolling: boolean): void {
    this.scrolling = scrolling
    // Changing cadence never flushes all completed rows in the scroll callback.
    if (this.publishTimer !== -1) { clearTimeout(this.publishTimer); this.publishTimer = -1 }
    this.schedulePublication()
  }
  remember(group: CourseReviewGroup): boolean {
    const value = group.summary.ready ? group.summary : CourseReviewSummary.from(group)
    if (!value.ready) return false
    this.cache.delete(group.id); this.cache.set(group.id, value); this.failed.delete(group.id)
    this.trimCache()
    this.enqueuePublication(group.id, value)
    return true
  }
  update(rows: CourseReviewGroup[], first: number, last: number, scope: string): void {
    if (this.scope !== scope) { this.reset(); this.scope = scope }
    this.enabled = true; this.rows = rows; this.first = first; this.last = last; this.queue = []
    // onScrollIndex can fire every frame. Reconcile only the latest window,
    // while retaining one active reader and a small forward prefetch window.
    const delay: number = this.scrolling ? Math.max(0, 80 - (Date.now() - this.viewportAt)) : 0
    if (delay === 0) {
      if (this.viewportTimer !== -1) { clearTimeout(this.viewportTimer); this.viewportTimer = -1 }
      this.reconcile()
    } else if (this.viewportTimer === -1) {
      this.viewportTimer = setTimeout(() => { this.viewportTimer = -1; this.reconcile() }, delay)
    }
  }
  private reconcile(): void {
    if (!this.enabled) return
    this.viewportAt = Date.now(); this.queue = []; this.viewport.clear()
    // At most eight cards, including a small look-ahead. No directory-wide fan-out.
    const start: number = Math.max(0, this.first)
    const end: number = this.windowEnd()
    for (let index: number = start; index < end; index++) {
      const row = this.rows[index]; this.viewport.set(row.id, row)
      const cached = this.cache.get(row.id)
      if (cached !== undefined) this.enqueuePublication(row.id, cached)
      else if (row.summary.ready) this.enqueuePublication(row.id, row.summary)
      else if (!this.pending.has(row.id) && !this.failed.has(row.id)) this.queue.push(row)
    }
    for (const id of this.publications.keys()) if (!this.viewport.has(id)) this.publications.delete(id)
    this.pump()
  }
  private pump(): void {
    const limit: number = this.scrolling ? 1 : 2
    while (this.enabled && this.running < limit && this.queue.length > 0) {
      if (this.scrolling && Date.now() - this.readAt < 80) {
        this.schedulePump(80 - (Date.now() - this.readAt)); return
      }
      const row = this.queue.shift() as CourseReviewGroup
      if (this.pending.has(row.id)) continue
      const revision: number = this.revision
      this.running++; this.pending.add(row.id); this.readAt = Date.now()
      this.read(row.id).then((group: CourseReviewGroup) => {
        if (revision !== this.revision) return
        if (group.id !== row.id) { this.failure(row, new Error('Course review identifier mismatch')); return }
        if (!this.remember(group)) this.failure(row, new Error('Course review summary is incomplete'))
      }).catch((error: Object) => {
        if (revision === this.revision) this.failure(row, error)
      }).finally(() => {
        this.running--
        if (revision === this.revision) this.pending.delete(row.id)
        // Yield even for a memory-cache hit instead of chaining microtasks
        // across a whole viewport on the UI thread.
        this.schedulePump(0)
      })
    }
  }
  private failure(row: CourseReviewGroup, error: Object): void {
    this.failed.add(row.id)
    const value = new CourseReviewSummary(); value.count = row.summary.count; value.error = ErrorDiagnostics.message(error)
    value.ready = row.summary.ready; value.level = row.summary.level
    this.cache.delete(row.id); this.cache.set(row.id, value)
    this.trimCache(); this.enqueuePublication(row.id, value)
  }
  private windowEnd(): number {
    const start: number = Math.max(0, this.first)
    return Math.min(this.rows.length, Math.max(start + 4, Math.min(this.last + 3, start + 8)))
  }
  private inLatestWindow(id: number): boolean {
    for (let index: number = Math.max(0, this.first); index < this.windowEnd(); index++) {
      if (this.rows[index].id === id) return true
    }
    return false
  }
  private enqueuePublication(id: number, value: CourseReviewSummary): void {
    if (!this.enabled || !this.inLatestWindow(id)) return
    const previous = this.published.get(id)
    if (previous !== undefined && previous.count === value.count && previous.level === value.level &&
      previous.ready === value.ready && previous.error === value.error && this.publishedCourseCounts.get(id) === this.latestCourseCount(id)) return
    this.publications.set(id, value); this.schedulePublication()
  }
  private schedulePublication(): void {
    if (!this.enabled || this.publishTimer !== -1 || this.publications.size === 0) return
    const interval: number = this.scrolling ? 80 : 32
    const delay: number = Math.max(1, interval - (Date.now() - this.publishedAt))
    this.publishTimer = setTimeout(() => {
      this.publishTimer = -1
      if (!this.enabled) return
      for (const id of this.publications.keys()) {
        if (!this.inLatestWindow(id)) { this.publications.delete(id); continue }
        const value = this.publications.get(id) as CourseReviewSummary
        this.publications.delete(id); this.published.set(id, value); this.publishedCourseCounts.set(id, this.latestCourseCount(id))
        while (this.published.size > 128) {
          const oldest = this.published.keys().next().value as number
          this.published.delete(oldest); this.publishedCourseCounts.delete(oldest)
        }
        this.publishedAt = Date.now()
        this.publish(id, value); break
      }
      this.schedulePublication()
    }, delay)
  }
  private schedulePump(delay: number): void {
    if (!this.enabled || this.pumpTimer !== -1) return
    this.pumpTimer = setTimeout(() => { this.pumpTimer = -1; this.pump() }, Math.max(0, delay))
  }
  private latestCourseCount(id: number): number | undefined {
    for (let index: number = Math.max(0, this.first); index < this.windowEnd(); index++) {
      const row = this.rows[index]
      if (row.id === id) return row.courseCount ?? (row.courses.length > 0 ? row.courses.length : undefined)
    }
    return undefined
  }
  private trimCache(): void {
    while (this.cache.size > 128) {
      const id = this.cache.keys().next().value as number
      this.cache.delete(id); this.published.delete(id); this.publishedCourseCounts.delete(id)
    }
  }
  private clearTimers(): void {
    if (this.viewportTimer !== -1) clearTimeout(this.viewportTimer)
    if (this.publishTimer !== -1) clearTimeout(this.publishTimer)
    if (this.pumpTimer !== -1) clearTimeout(this.pumpTimer)
    this.viewportTimer = -1; this.publishTimer = -1; this.pumpTimer = -1
  }
}
