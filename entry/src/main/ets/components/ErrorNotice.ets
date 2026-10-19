import { ReadableText } from '../common/ReadableText'
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
  @Prop interactive: boolean = true
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
      .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
      .onTouch((event: TouchEvent) => { if (this.interactive) event.stopPropagation() })
      .onClick(() => { if (this.interactive) DiagnosticNavigation.open(this.getUIContext(), this.message, this.logs(), this.summary) })
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
  textMaxLines: number | undefined = undefined
  diagnosticHeight: number = 36
  @Prop diagnosticInteractive: boolean = true
  @Prop textColor: ResourceColor = ThemeColors.textSecondary
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0

  private authenticationNotice(): boolean {
    return /Authentication required|status=-2|身份验证|身分驗證|身份认证|继续验证|繼續驗證|登录校园|登入校園|校园账号|校園帳號|campus identity|campus account|本人確認|学内アカウント/i.test(this.summary + ' ' + this.message)
  }

  build() {
    Column({ space: 2 }) {
      Text(ReadableText.keepWords(DiagnosticNavigation.brief(this.message, this.summary))).fontSize(this.textSize).lineHeight(this.textSize + 8)
        .fontColor(this.textColor).width('100%')
        .maxLines(this.textMaxLines).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.authenticationNotice() ? TextAlign.Center : TextAlign.Start)
      DiagnosticLink({ message: this.message, summary: this.summary, logs: this.logs, controlId: this.controlId,
        controlHeight: this.diagnosticHeight, interactive: this.diagnosticInteractive })
    }.width('100%').alignItems(this.authenticationNotice() ? HorizontalAlign.Center : HorizontalAlign.Start)
  }
}
