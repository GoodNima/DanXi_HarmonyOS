import { ThemeColors } from '../common/Theme'

@Component
export struct SearchClearButton {
  controlId: string = 'search-clear'
  onClear: () => void = () => {}
  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(20).fontColor([ThemeColors.textHint])
    }.width(32).height(32).padding(0).backgroundColor(Color.Transparent).stateEffect(false)
      .id(this.controlId).accessibilityText($r('app.string.ui_clear')).onClick(() => { this.onClear() })
  }
}
