import { ThemeColors } from '../common/Theme'

/** Filled native vector dots, independent of language/font baseline. */
@Component
export struct MoreGlyph {
  @Prop color: ResourceColor = ThemeColors.textPrimary
  build() {
    Row({ space: 4 }) {
      Circle().width(4).height(4).fill(this.color)
      Circle().width(4).height(4).fill(this.color)
      Circle().width(4).height(4).fill(this.color)
    }.width(24).height(24).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
