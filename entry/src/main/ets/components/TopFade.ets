import { TopFadeMetrics } from '../common/TopFadeMetrics'

/** Sample the scene on the outer render node, then mask that same-sized plane.
 * A blur inside the offscreen group samples the group's transparent buffer,
 * producing a grey band instead of the live scene. Round both mask boundaries
 * identically so fractional vp coordinates cannot leave a one-pixel seam.
 * The broad easing mask keeps the feed visible beneath the floating controls
 * and fades naturally past the measured header, without a rectangular edge.
 */
@Component
export struct TopFade {
  @Prop extent: number = 120
  @Prop trailingEdge: number = TopFadeMetrics.TRAILING_EDGE
  @StorageLink('app_dark_mode') private darkMode: boolean = false

  @Builder
  FadePlane() {
    Stack({ alignContent: Alignment.Top }) {
      Column().width('100%').height('100%')
        .linearGradient({ direction: GradientDirection.Bottom, colors: TopFadeMetrics.colors(this.extent, this.trailingEdge) })
        .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
        .pixelRound({ start: PixelRoundCalcPolicy.FORCE_FLOOR, top: PixelRoundCalcPolicy.FORCE_FLOOR,
          end: PixelRoundCalcPolicy.FORCE_CEIL, bottom: PixelRoundCalcPolicy.FORCE_CEIL })
        .hitTestBehavior(HitTestMode.None)
    }.width('100%').height(TopFadeMetrics.height(this.extent, this.trailingEdge))
      .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
      // Omit SystemAdaptiveOptions as recommended by API 26: the native default
      // retains system adaptation. This header uses a backdrop, not a separate
      // ImmersiveMaterial quality override or a second painted scrim.
      .backgroundEffect({ radius: TopFadeMetrics.BLUR_RADIUS, brightness: 1, saturation: 1, color: $r('app.color.top_fade'),
        inactiveColor: $r('app.color.top_fade'), policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE })
      .pixelRound({ start: PixelRoundCalcPolicy.FORCE_FLOOR, top: PixelRoundCalcPolicy.FORCE_FLOOR,
        end: PixelRoundCalcPolicy.FORCE_CEIL, bottom: PixelRoundCalcPolicy.FORCE_CEIL })
      // None excludes only this node. The mask leaf also needs None; leaving
      // either render node Default lets an invisible fade consume feed taps.
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // A theme-qualified scene must get a fresh backdrop node. Updating only
      // resources can otherwise retain the old offscreen capture on the GPU.
      // Status-bar / material revisions without a color-mode change must not
      // destroy every header's live backdrop during navigation or verification.
      ForEach([this.darkMode], (dark: boolean) => {
        this.FadePlane()
      }, (dark: boolean): string => dark ? 'top-fade-dark' : 'top-fade-light')
      // A real pointer target blocks obscured feed controls even during inertia.
      Column().width('100%').height(TopFadeMetrics.height(this.extent, this.trailingEdge))
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => { event.stopPropagation() })
        .onClick(() => {})
        .id('top-fade-touch-shield')
    }.width('100%').height(TopFadeMetrics.height(this.extent, this.trailingEdge))
      .hitTestBehavior(HitTestMode.Transparent)
      .accessibilityLevel('no')
  }
}
