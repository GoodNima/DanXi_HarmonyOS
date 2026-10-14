import { ThemeColors } from './Theme'
import { CourseReview } from '../model/CourseReview'

/** Upstream wordColor order: red, orange, yellow, light green, green.
 * Resource variants keep the same meaning readable in light and dark themes. */
export class ReviewPresentation {
  /** Body changes replace a lazy row; votes remain local and never replace it. */
  static rowKey(review: CourseReview): string {
    const body: string = [review.content, review.title, review.teacher, review.term, review.achievements.join('|'),
      review.created, review.updated, String(review.deleted), String(review.rank.overall), String(review.rank.content),
      String(review.rank.workload), String(review.rank.assessment)].join('\u0000')
    let hash: number = 2166136261
    for (let i: number = 0; i < body.length; i++) hash = Math.imul(hash ^ body.charCodeAt(i), 16777619)
    return String(review.id) + '/' + String(hash >>> 0)
  }
  static ratingColor(value: number): ResourceColor {
    const colors: ResourceColor[] = [$r('app.color.review_level_1'), $r('app.color.review_level_2'),
      $r('app.color.review_level_3'), $r('app.color.review_level_4'), $r('app.color.review_level_5')]
    return Number.isInteger(value) && value >= 1 && value <= 5 ? colors[value - 1] : ThemeColors.textSecondary
  }
}
