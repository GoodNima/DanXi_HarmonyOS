import { CourseReviewSummary } from '../model/CourseReview'

/** Only aggregate fields cross back to the UI; review bodies stay in the worker. */
export class CourseReviewPreviewCourse {
  id: number = 0
  loaded: boolean = false
  count: number = 0
  rankCount: number = 0
  rankTotal: number = 0
}
export class CourseReviewPreview {
  id: number = 0
  name: string = ''
  reviewCount: number | undefined = undefined
  courses: CourseReviewPreviewCourse[] = []
  summary: CourseReviewSummary = new CourseReviewSummary()
}

/** Pure counterpart to parseGroup/parseReviews. No storage, resources or network. */
export class CourseReviewPreviewParser {
  static parse(body: string, reviewsOnly: boolean): string {
    const raw = JSON.parse(body) as Object
    const value = new CourseReviewPreview()
    if (reviewsOnly) {
      if (!Array.isArray(raw)) throw new Error('Invalid course review response')
      const course = new CourseReviewPreviewCourse()
      CourseReviewPreviewParser.reviews(course, raw as Object[])
      value.courses.push(course)
    } else {
      const group = CourseReviewPreviewParser.record(raw)
      value.id = CourseReviewPreviewParser.integer(group['id'])
      value.name = typeof group['name'] === 'string' ? group['name'] as string : ''
      if (value.id <= 0 || !value.name) throw new Error('Invalid course review group')
      const count = group['review_count']
      if (typeof count === 'number' && Number.isSafeInteger(count) && count >= 0) value.reviewCount = count
      const courses = group['course_list'] ?? group['courseList']
      if (!Array.isArray(courses)) throw new Error('Invalid course review courses')
      for (const course of courses as Object[]) value.courses.push(CourseReviewPreviewParser.course(CourseReviewPreviewParser.record(course)))
      if (value.courses.length === 0 && value.reviewCount === undefined) value.reviewCount = 0
    }
    CourseReviewPreviewParser.summarize(value)
    return JSON.stringify(value)
  }
  static summarize(value: CourseReviewPreview): void {
    let loaded: boolean = value.courses.length > 0
    let count: number = 0
    let rankCount: number = 0
    let rankTotal: number = 0
    for (const course of value.courses) {
      if (!course.loaded) loaded = false
      count += course.count; rankCount += course.rankCount; rankTotal += course.rankTotal
    }
    const summary = new CourseReviewSummary()
    summary.count = loaded ? count : value.reviewCount
    summary.ready = summary.count === 0 || loaded
    if (summary.ready && rankCount > 0) summary.level = Math.floor(rankTotal / rankCount)
    value.summary = summary
  }
  private static course(raw: Record<string, Object>): CourseReviewPreviewCourse {
    const value = new CourseReviewPreviewCourse()
    value.id = CourseReviewPreviewParser.integer(raw['id'])
    if (value.id <= 0) throw new Error('Invalid course review course identifier')
    const reviews = raw['review_list'] ?? raw['reviewList']
    if (Array.isArray(reviews)) CourseReviewPreviewParser.reviews(value, reviews as Object[])
    return value
  }
  private static reviews(value: CourseReviewPreviewCourse, reviews: Object[]): void {
    for (const item of reviews) {
      const review = CourseReviewPreviewParser.record(item)
      if (CourseReviewPreviewParser.integer(review['id']) <= 0) throw new Error('Invalid course review identifier')
      let overall: number = 0
      if (review['rank'] !== undefined && review['rank'] !== null) {
        const rank = CourseReviewPreviewParser.record(review['rank'])
        const number = rank['overall']
        if (typeof number === 'number' && Number.isInteger(number) && number >= 1 && number <= 5) overall = number
      }
      // Nested course identities were validated by the full parser too. They do
      // not contribute a second time to this course's aggregate.
      if (review['course'] !== undefined && review['course'] !== null) CourseReviewPreviewParser.course(CourseReviewPreviewParser.record(review['course']))
      if (review['deleted'] !== true) {
        value.count++
        if (overall > 0) { value.rankCount++; value.rankTotal += overall }
      }
    }
    value.loaded = true
  }
  private static record(value: Object): Record<string, Object> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid course review object')
    return value as Record<string, Object>
  }
  private static integer(value: Object | undefined): number { return typeof value === 'number' && Number.isSafeInteger(value) ? value : 0 }
}
