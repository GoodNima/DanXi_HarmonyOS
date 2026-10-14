import { AppLanguage } from '../common/AppLanguage'
import { ReviewPresentation } from '../common/ReviewPresentation'
import { ThemeColors } from '../common/Theme'
import { CourseReviewSummary } from '../model/CourseReview'
import { CourseReviewSummaryState } from '../model/CourseReviewSummaryState'
import { DiagnosticLink } from './ErrorNotice'

/** Only changed text crosses over; labels, layout and the course card stay put. */
@Component
export struct CourseReviewSummaryView {
  @ObjectLink state: CourseReviewSummaryState
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('app_dark_mode') dark: boolean = false
  courseId: number = 0
  private text(value: Resource, ...args: (string | number)[]): string {
    return AppLanguage.text(value, this.languageRevision, ...args)
  }
  private ratingText(value: CourseReviewSummary): string {
    if (value.ready && value.level > 0) {
      return this.text($r('app.string.utility_rating_overall_words')).split(';')[value.level - 1] ?? ''
    }
    return this.text(value.ready ? $r('app.string.review_no_ratings') : value.error ?
      $r('app.string.review_summary_failed') : $r('app.string.review_summary_loading'))
  }
  private ratingKey(value: CourseReviewSummary): string {
    return (value.ready ? 'ready/' + value.level : value.error ? 'failed' : 'loading') + '/' + this.languageRevision
  }
  build() {
    Row({ space: 16 }) {
      Column({ space: 5 }) {
        Text(this.text($r('app.string.review_average_rating'))).fontSize(12).fontColor(ThemeColors.textSecondary)
        Stack({ alignContent: Alignment.Start }) {
          ForEach([this.state.value], (value: CourseReviewSummary) => {
            Text(this.ratingText(value)).fontSize(value.ready && value.level > 0 ? 22 : 14).lineHeight(30)
              .fontWeight(value.ready && value.level > 0 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(value.ready && value.level > 0 ? ReviewPresentation.ratingColor(value.level) : ThemeColors.textSecondary)
              .width('100%').textAlign(TextAlign.Start).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
          }, (value: CourseReviewSummary): string => this.ratingKey(value))
        }.width('100%').height(30).id('course-summary-rating-' + this.courseId)
        if (this.state.value.error) {
          DiagnosticLink({ message: this.state.value.error, summary: this.text($r('app.string.review_summary_failed')),
            controlId: 'review-summary-diagnostics' })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 5 }) {
        Stack({ alignContent: Alignment.End }) {
          ForEach([this.state.value], (value: CourseReviewSummary) => {
            Text(value.count !== undefined ? this.text($r('app.string.utility_review_count'), value.count as number) :
              this.text($r('app.string.review_count_unavailable'))).fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium)
              .fontColor(value.count !== undefined ? (this.dark ? ThemeColors.primaryLight : ThemeColors.primary) : ThemeColors.textSecondary)
              .width('100%').textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
          }, (value: CourseReviewSummary): string => String(value.count) + '/' + this.languageRevision)
        }.width('100%').height(24).id('course-summary-count-' + this.courseId)
        if (this.state.courseCount !== undefined) {
          Stack({ alignContent: Alignment.End }) {
            ForEach([this.state.courseCount], (count: number) => {
              Text(this.text($r('app.string.utility_course_count'), count)).fontSize(12).lineHeight(18)
                .fontColor(ThemeColors.textSecondary).width('100%').textAlign(TextAlign.End)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
            }, (count: number): string => String(count) + '/' + this.languageRevision)
          }.width('100%').height(18)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.End)
    }.width('100%').alignItems(VerticalAlign.Center).padding({ top: 2, bottom: 2 })
      .id('course-summary-' + this.courseId)
  }
}
