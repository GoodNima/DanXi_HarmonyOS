import { ThemeColors } from '../common/Theme'

/** One label, one native button handler. Children are decorative so a tap on
 * the symbol cannot also submit the enclosing action. */
@Component
export struct CampusActionLabel {
  @Prop label: ResourceStr = ''
  @Prop symbol: Resource = $r('sys.symbol.checkmark')
  @Prop color: ResourceColor = ThemeColors.primary
  build() {
    Row({ space: 6 }) {
      SymbolGlyph(this.symbol).fontSize(18).fontColor([this.color])
      Text(this.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.color)
    }.padding({ left: 12, right: 12 }).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).hitTestBehavior(HitTestMode.None)
  }
}
