/** DanKe v3 course-group and legacy review payloads, pinned upstream 551a88c. */
export class ReviewRating {
  overall: number = 0
  content: number = 0
  workload: number = 0
  assessment: number = 0
  static fromRaw(raw: Record<string, Object>): ReviewRating {
    const result = new ReviewRating()
    result.overall = ReviewRating.number(raw['overall'])
    const content = ReviewRating.number(raw['content']); const workload = ReviewRating.number(raw['workload'])
    result.content = content > 0 ? 6 - content : 0
    result.workload = workload > 0 ? 6 - workload : 0
    result.assessment = ReviewRating.number(raw['assessment'])
    return result
  }
  valid(): boolean { return [this.overall, this.content, this.workload, this.assessment].every(value => Number.isInteger(value) && value >= 1 && value <= 5) }
  raw(): RawReviewRating {
    const value = new RawReviewRating(); value.overall = this.overall; value.content = 6 - this.content
    value.workload = 6 - this.workload; value.assessment = this.assessment; return value
  }
  static number(value: Object | null | undefined): number { return typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 5 ? value : 0 }
}
export class RawReviewRating { overall: number = 0; content: number = 0; workload: number = 0; assessment: number = 0 }
export class CourseReview {
  id: number = 0
  reviewerId: number = 0
  title: string = ''
  content: string = ''
  created: string = ''
  updated: string = ''
  rank: ReviewRating = new ReviewRating()
  votes: number = 0
  myVote: number = 0
  isMe: boolean = false
  deleted: boolean = false
  modified: number = 0
  courseId: number = 0
  groupId: number = 0
  courseName: string = ''
  courseCode: string = ''
  department: string = ''
  campus: string = ''
  credit: number | undefined = undefined
  achievements: string[] = []
  teacher: string = ''
  term: string = ''
}
export class ReviewCourse {
  id: number = 0
  name: string = ''
  code: string = ''
  department: string = ''
  campus: string = ''
  teacher: string = ''
  year: number = 0
  semester: number = 0
  credit: number | undefined = undefined
  term: string = ''
  reviews: CourseReview[] = []
  reviewsLoaded: boolean = false
}
/** Compact derived values keep full review arrays out of scrolling/render work. */
export class CourseReviewSummary {
  count: number | undefined = undefined
  level: number = 0
  ready: boolean = false
  error: string = ''
  static from(group: CourseReviewGroup): CourseReviewSummary {
    const value = new CourseReviewSummary()
    value.count = group.reviewTotal()
    value.ready = value.count === 0 || (group.courses.length > 0 && group.courses.every(course => course.reviewsLoaded))
    if (value.ready) value.level = group.overall()
    return value
  }
}
export class CourseReviewGroup {
  id: number = 0
  name: string = ''
  code: string = ''
  department: string = ''
  campus: string = ''
  weekHour: number | undefined = undefined
  credits: number[] = []
  courseCount: number | undefined = undefined
  reviewCount: number | undefined = undefined
  courses: ReviewCourse[] = []
  summary: CourseReviewSummary = new CourseReviewSummary()
  creditValues(): number[] {
    const values: number[] = this.credits.concat(this.courses.filter(course => course.credit !== undefined)
      .map(course => course.credit as number)).filter(value => Number.isFinite(value) && value >= 0)
    return Array.from(new Set<number>(values)).sort((left: number, right: number): number => left - right)
  }
  campuses(): string[] {
    return Array.from(new Set<string>([this.campus].concat(this.courses.map(course => course.campus))
      .map(value => value.trim()).filter(value => value.length > 0)))
  }
  filtered(teacher: string, term: string): CourseReview[] {
    return this.courses.filter(course => (!teacher || course.teacher === teacher) && (!term || course.term === term))
      .flatMap(course => course.reviews)
  }
  teachers(): string[] { return Array.from(new Set<string>(this.courses.map(course => course.teacher).filter(value => value.length > 0))) }
  terms(): string[] { return Array.from(new Set<string>(this.courses.map(course => course.term).filter(value => value.length > 0))) }
  reviewTotal(): number | undefined {
    if (this.courses.length > 0 && this.courses.every(course => course.reviewsLoaded)) {
      return this.courses.reduce((sum: number, course: ReviewCourse) => sum + course.reviews.filter(review => !review.deleted).length, 0)
    }
    return this.reviewCount
  }
  average(): number | undefined {
    if (this.courses.length === 0 || !this.courses.every(course => course.reviewsLoaded)) return undefined
    const reviews: CourseReview[] = this.courses.flatMap(course => course.reviews)
      .filter(review => !review.deleted && Number.isFinite(review.rank.overall) && review.rank.overall >= 1 && review.rank.overall <= 5)
    return reviews.length > 0 ? reviews.reduce((sum: number, review: CourseReview) => sum + review.rank.overall, 0) / reviews.length : undefined
  }
  overall(): number {
    const reviews: CourseReview[] = this.courses.flatMap(course => course.reviews).filter(review => !review.deleted && review.rank.overall >= 1 && review.rank.overall <= 5)
    return reviews.length > 0 ? Math.floor(reviews.reduce((sum: number, review: CourseReview) => sum + review.rank.overall, 0) / reviews.length) : 0
  }
}
export class CourseReviewSearch { page: number = 1; pageSize: number = 20; extra: string = ''; items: CourseReviewGroup[] = [] }
export class CourseReviewDraft {
  courseId: number = 0
  title: string = ''
  content: string = ''
  rank: ReviewRating = new ReviewRating()
  valid(): boolean { return Number.isInteger(this.courseId) && this.courseId > 0 && this.title.trim().length > 0 && this.content.trim().length > 0 && this.rank.valid() }
  body(): ReviewBody { const body = new ReviewBody(); body.title = this.title.trim(); body.content = this.content.trim(); body.rank = this.rank.raw(); return body }
}
export class ReviewBody { title: string = ''; content: string = ''; rank: RawReviewRating = new RawReviewRating() }
export class ReviewVoteBody { upvote: boolean = true }
