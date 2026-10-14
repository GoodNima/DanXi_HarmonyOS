import { HapticFeedback } from '../common/HapticFeedback'
import { ReviewVoteState } from '../model/ReviewVoteState'
import { ThemeColors } from '../common/Theme'
import { AppLanguage } from '../common/AppLanguage'

/** Stable row-local votes: no spinner or review-body replacement. */
@Component
export struct ReviewVoteControls {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @ObjectLink state: ReviewVoteState
  onVote: (up: boolean) => void = () => {}
  @State private upScale: number = 1
  @State private downScale: number = 1
  private timer: number = -1
  private active: boolean = false
  aboutToAppear(): void { this.active = true }
  aboutToDisappear(): void { this.active = false; if (this.timer >= 0) clearTimeout(this.timer) }
  private vote(up: boolean): void {
    if (this.state.pending || this.state.deleted) return
    HapticFeedback.selection()
    this.onVote(up)
    if (this.timer >= 0) clearTimeout(this.timer)
    this.getUIContext().animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
      this.upScale = up ? 1.12 : 1; this.downScale = up ? 1 : 1.12
    })
    this.timer = setTimeout(() => {
      if (this.active) this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
        this.upScale = 1; this.downScale = 1
      })
    }, 100)
  }
  build() {
    Row({ space: 10 }) {
      Row({ space: 8 }) {
        Row() {
          Image(this.state.myVote > 0 ? $r('app.media.vote_up_filled') : $r('app.media.vote_up')).width(22).height(22)
            .fillColor(this.state.myVote > 0 ? ThemeColors.primary : ThemeColors.textSecondary).scale({ x: this.upScale, y: this.upScale })
        }.width(28).height(36).onClick(() => { this.vote(true) }).accessibilityText($r('app.string.ui_like'))
        Row() {
          Image(this.state.myVote < 0 ? $r('app.media.vote_down_filled') : $r('app.media.vote_down')).width(22).height(22)
            .fillColor(this.state.myVote < 0 ? ThemeColors.accent : ThemeColors.textSecondary).scale({ x: this.downScale, y: this.downScale })
        }.width(28).height(36).onClick(() => { this.vote(false) }).accessibilityText($r('app.string.ui_dislike'))
      }.alignItems(VerticalAlign.Center)
      Divider().vertical(true).height(16).strokeWidth(0.6).color($r('app.color.surface_outline'))
      Row({ space: 4 }) {
        Text(AppLanguage.text(this.state.votes < 0 ? $r('app.string.review_net_against') :
          this.state.votes > 0 ? $r('app.string.review_net_support') : $r('app.string.review_net_score'), this.languageRevision))
          .fontSize(12).fontWeight(FontWeight.Medium).maxLines(1)
          .fontColor(this.state.votes < 0 ? ThemeColors.accent : this.state.votes > 0 ? ThemeColors.primary : ThemeColors.textSecondary)
        Text(String(Math.abs(this.state.votes))).fontSize(14).constraintSize({ minWidth: 18 })
          .fontColor(this.state.votes < 0 ? ThemeColors.accent : this.state.votes > 0 ? ThemeColors.primary : ThemeColors.textSecondary)
      }.height(36).alignItems(VerticalAlign.Center)
    }.height(36).alignItems(VerticalAlign.Center)
  }
}
