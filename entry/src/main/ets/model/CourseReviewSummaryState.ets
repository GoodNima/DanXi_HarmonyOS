import { CourseReviewGroup, CourseReviewSummary } from './CourseReview'

/** A row-local snapshot survives repository mutations and lazy-list reuse. */
@Observed
export class CourseReviewSummaryState {
  value: CourseReviewSummary = new CourseReviewSummary()
  courseCount: number | undefined = undefined
  constructor(group: CourseReviewGroup) { this.update(group, group.summary) }
  update(group: CourseReviewGroup, summary: CourseReviewSummary): void {
    if (this.value.count !== summary.count || this.value.level !== summary.level ||
      this.value.ready !== summary.ready || this.value.error !== summary.error) {
      const next = new CourseReviewSummary()
      next.count = summary.count; next.level = summary.level; next.ready = summary.ready; next.error = summary.error
      this.value = next
    }
    this.courseCount = group.courseCount ?? (group.courses.length > 0 ? group.courses.length : undefined)
  }
}
