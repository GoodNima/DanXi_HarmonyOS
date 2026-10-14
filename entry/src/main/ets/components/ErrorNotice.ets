import { ThemeColors } from '../common/Theme'
import { AppLanguage } from '../common/AppLanguage'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { getSymbolIcon } from '../common/DanXiIcons'

@Component
export struct DiagnosticLink {
  @Prop message: string = ''
  @Prop summary: string = ''
  logs: () => string = (): string => ''
  controlId: string = 'error-read-diagnostics'
  color: ResourceColor | undefined = undefined
  controlHeight: number = 36
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 4 }) {
        Text(AppLanguage.text($r('app.string.diagnostics_read'), this.languageRevision)).fontSize(13)
          .fontWeight(FontWeight.Medium).fontColor(this.color ?? ThemeColors.primary)
        SymbolGlyph(getSymbolIcon('forward')).fontSize(12).fontColor([this.color ?? ThemeColors.primary])
      }.alignItems(VerticalAlign.Center)
    }.id(this.controlId).height(this.controlHeight).padding({ left: 0, right: 6 }).backgroundColor(Color.Transparent)
      .stateEffect(false).hoverEffect(HoverEffect.None).borderRadius(8)
      .onTouch((event: TouchEvent) => { event.stopPropagation() })
      .onClick(() => { DiagnosticNavigation.open(this.getUIContext(), this.message, this.logs(), this.summary) })
      .accessibilityText(AppLanguage.text($r('app.string.diagnostics_read'), this.languageRevision))
  }
}

@Component
export struct ErrorNotice {
  @Prop message: string = ''
  @Prop summary: string = ''
  logs: () => string = (): string => ''
  controlId: string = 'error-read-diagnostics'
  textSize: number = 13
  @Prop textColor: ResourceColor = ThemeColors.textSecondary
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0

  build() {
    Column({ space: 2 }) {
      Text(DiagnosticNavigation.brief(this.message, this.summary)).fontSize(this.textSize).lineHeight(this.textSize + 8)
        .fontColor(this.textColor).width('100%')
      DiagnosticLink({ message: this.message, summary: this.summary, logs: this.logs, controlId: this.controlId })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
