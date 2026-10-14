import { ThemeColors } from '../common/Theme'

/** A permanent overlay node: asynchronous reads never insert a list row or
 * displace the content. Retain the native spinner through its exit fade. */
@Component
export struct CenterLoadingProgress {
  @Prop @Watch('changed') busy: boolean = false
  @State private running: boolean = false
  private revision: number = 0

  aboutToAppear(): void { this.changed() }
  aboutToDisappear(): void { this.revision++ }
  changed(): void {
    this.revision++
    if (this.busy) this.running = true
  }
  private motion(): AnimateParam {
    const revision: number = this.revision
    return { duration: 180, curve: Curve.EaseOut, onFinish: () => {
      if (revision === this.revision && !this.busy) this.running = false
    } }
  }
  build() {
    Stack() {
      LoadingProgress().width(36).height(36).color(ThemeColors.primary)
        .enableLoading(this.running).opacity(this.busy ? 1 : 0)
        .animation(this.motion()).hitTestBehavior(HitTestMode.None)
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }
}
