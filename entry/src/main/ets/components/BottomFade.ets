/** Decorative edge scrim behind floating controls. Content keeps scrolling under
 * it; it never catches touches or participates in accessibility navigation.
 */
@Component
export struct BottomFade {
  @Prop extent: number = 100

  build() {
    Column().width('100%').height(this.extent)
      .linearGradient({ direction: GradientDirection.Bottom,
        colors: [[Color.Transparent, 0], [$r('app.color.bottom_fade_mid'), 0.55],
          [$r('app.color.bottom_fade_edge'), 1]] })
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
