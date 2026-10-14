import { HapticFeedback } from '../common/HapticFeedback'
import { ForumVoteState } from '../model/ForumVoteState'
import { ThemeColors } from '../common/Theme'
import { AppLanguage } from '../common/AppLanguage'

@Component
export struct ForumVoteControls {
  @ObjectLink state: ForumVoteState
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  onVote: (up: boolean) => void = () => {}
  @State private upScale: number = 1
  @State private downScale: number = 1
  private timer: number = -1
  private active: boolean = false

  aboutToAppear(): void { this.active = true }
  aboutToDisappear(): void { this.active = false; if (this.timer >= 0) clearTimeout(this.timer) }
  private vote(up: boolean): void {
    if (!this.active || this.state.pending || this.state.deleted) return
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
    Row({ space: 8 }) {
      Row({ space: 3 }) {
        Image(this.state.liked ? $r('app.media.vote_up_filled') : $r('app.media.vote_up'))
          .width(16).height(16).fillColor(this.state.liked ? ThemeColors.primary : ThemeColors.textSecondary)
          .scale({ x: this.upScale, y: this.upScale })
        Text(String(this.state.like)).fontSize(12).constraintSize({ minWidth: 12 })
          .fontColor(this.state.liked ? ThemeColors.primary : ThemeColors.textSecondary)
      }.height(32).enabled(!this.state.deleted && !this.state.pending)
        .accessibilityText(AppLanguage.text($r('app.string.ui_like'), this.languageRevision) + this.state.like)
        .onClick(() => { this.vote(true) })
      Row({ space: 3 }) {
        Image(this.state.disliked ? $r('app.media.vote_down_filled') : $r('app.media.vote_down'))
          .width(16).height(16).fillColor(this.state.disliked ? ThemeColors.accent : ThemeColors.textSecondary)
          .scale({ x: this.downScale, y: this.downScale })
        Text(String(this.state.dislike)).fontSize(12).constraintSize({ minWidth: 12 })
          .fontColor(this.state.disliked ? ThemeColors.accent : ThemeColors.textSecondary)
      }.height(32).enabled(!this.state.deleted && !this.state.pending)
        .accessibilityText(AppLanguage.text($r('app.string.ui_dislike'), this.languageRevision) + this.state.dislike)
        .onClick(() => { this.vote(false) })
    }.alignItems(VerticalAlign.Center)
  }
}
