import { CourseReviewGroup, CourseReviewSummary } from '../model/CourseReview'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'

class CourseSummaryEntry {
  value: CourseReviewSummary = new CourseReviewSummary()
  at: number = 0
}

/** Two readers, a replaceable viewport queue and bounded summary-only cache.
 * Leaving a viewport drops queued work; already-started reads remain coalesced. */
export class CourseReviewSummaryLoader {
  private scope: string = ''
  private revision: number = 0
  private running: number = 0
  private enabled: boolean = false
  private queue: CourseReviewGroup[] = []
  private pending: Set<number> = new Set<number>()
  private cache: Map<number, CourseSummaryEntry> = new Map<number, CourseSummaryEntry>()
  private failed: Set<number> = new Set<number>()
  private read: (id: number) => Promise<CourseReviewGroup>
  private publish: (id: number, summary: CourseReviewSummary) => void
  constructor(read: (id: number) => Promise<CourseReviewGroup>, publish: (id: number, summary: CourseReviewSummary) => void) {
    this.read = read; this.publish = publish
  }
  reset(): void {
    this.revision++; this.queue = []; this.cache.clear(); this.failed.clear(); this.pending.clear()
  }
  pause(): void { this.enabled = false; this.queue = [] }
  remember(group: CourseReviewGroup): boolean {
    const value = group.summary.ready ? group.summary : CourseReviewSummary.from(group)
    if (!value.ready) return false
    const entry = new CourseSummaryEntry(); entry.value = value; entry.at = Date.now()
    this.cache.delete(group.id); this.cache.set(group.id, entry); this.failed.delete(group.id)
    while (this.cache.size > 128) this.cache.delete(this.cache.keys().next().value as number)
    this.publish(group.id, value)
    return true
  }
  update(rows: CourseReviewGroup[], first: number, last: number, scope: string): void {
    if (this.scope !== scope) { this.reset(); this.scope = scope }
    this.enabled = true; this.queue = []
    // At most eight cards, including a small look-ahead. No directory-wide fan-out.
    const start: number = Math.max(0, first)
    const end: number = Math.min(rows.length, Math.max(start + 4, Math.min(last + 3, start + 8)))
    for (let index: number = start; index < end; index++) {
      const row = rows[index]
      if (row.summary.ready) continue
      const cached = this.cache.get(row.id)
      if (cached !== undefined && Date.now() - cached.at < 300000) this.publish(row.id, cached.value)
      else if (!this.pending.has(row.id) && !this.failed.has(row.id)) this.queue.push(row)
    }
    this.pump()
  }
  private pump(): void {
    while (this.enabled && this.running < 2 && this.queue.length > 0) {
      const row = this.queue.shift() as CourseReviewGroup
      if (this.pending.has(row.id)) continue
      const revision: number = this.revision
      this.running++; this.pending.add(row.id)
      this.read(row.id).then((group: CourseReviewGroup) => {
        if (revision !== this.revision) return
        if (group.id !== row.id) { this.failure(row, new Error('Course review identifier mismatch')); return }
        if (!this.remember(group)) this.failure(row, new Error('Course review summary is incomplete'))
      }).catch((error: Object) => {
        if (revision === this.revision) this.failure(row, error)
      }).finally(() => {
        this.running--
        if (revision === this.revision) this.pending.delete(row.id)
        this.pump()
      })
    }
  }
  private failure(row: CourseReviewGroup, error: Object): void {
    this.failed.add(row.id)
    const value = new CourseReviewSummary(); value.count = row.summary.count; value.error = ErrorDiagnostics.message(error)
    this.publish(row.id, value)
  }
}
