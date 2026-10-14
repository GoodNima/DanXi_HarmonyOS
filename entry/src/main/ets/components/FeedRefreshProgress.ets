import { ThemeColors } from '../common/Theme'

/** Keep native Refresh gestures/displacement, with its indicator below the
 * floating header instead of beneath the system status bar. No feed inset or
 * opaque masking layer is needed. */
@Builder
export function EmptyRefreshIndicator() {
  Row().width('100%').height(64)
}

@Component
export struct FeedRefreshProgress {
  @Prop topInset: number = 0
  @Prop @Watch('onMotionChange') pullOffset: number = 0
  @Prop @Watch('onMotionChange') refreshing: boolean = false
  @State private loadingVisible: boolean = false
  private motionVersion: number = 0

  aboutToAppear(): void { this.onMotionChange() }
  aboutToDisappear(): void { this.motionVersion++ }

  onMotionChange(): void {
    this.motionVersion++
    if (this.refreshing || this.pullOffset > 0) this.loadingVisible = true
  }

  private motionOptions(): AnimateParam {
    const version: number = this.motionVersion
    return { duration: 180, curve: Curve.EaseOut, onFinish: () => {
      // enableLoading(false) hides the native spinner, so wait for the fade.
      // An interrupted animation cannot stop a newer pull/refresh/retraction.
      if (version === this.motionVersion && !this.refreshing && this.pullOffset <= 0) {
        this.loadingVisible = false
      }
    } }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // Keep the native node alive during retraction, including requests that
      // finish immediately. Removing it in an if branch cut off the exit fade.
      // Only opacity and transforms animate; Refresh still owns content layout.
      LoadingProgress().width(24).height(24).color(ThemeColors.primary)
        .hitTestBehavior(HitTestMode.None)
        .enableLoading(this.loadingVisible)
        .opacity(this.refreshing ? 1 : Math.min(1, Math.max(0, this.pullOffset / 48)))
        .scale({ x: this.refreshing || this.pullOffset > 0 ? 1 : 0.82,
          y: this.refreshing || this.pullOffset > 0 ? 1 : 0.82 })
        .translate({ y: Math.min(16, Math.max(0, this.pullOffset / 4)) })
        .animation(this.motionOptions())
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
      .translate({ y: this.topInset + 8 })
      .accessibilityLevel('no-hide-descendants')
  }
}
