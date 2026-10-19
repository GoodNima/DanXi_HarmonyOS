import { ReadableText } from '../common/ReadableText'
import { pasteboard, BusinessError } from '@kit.BasicServicesKit'
import { Constant } from '../common/Constant'
import { AppLanguage } from '../common/AppLanguage'
import { AppState } from '../common/AppState'
import { CampusCookies } from '../common/CampusCookies'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { settleScrollTouch } from '../common/ScrollTouch'
import { DiagnosticReport, DiagnosticReports } from '../model/DiagnosticReport'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { FloatingActionButton } from './FloatingActionButton'

export class DiagnosticPanelParams {
  diagnosticId: string = ''
  maxHeight: number = 540
  isActive: () => boolean = (): boolean => true
  close: () => void = () => {}
  refreshAppearance: () => void = () => {}
}

@Builder
export function buildDiagnosticPanel(params: DiagnosticPanelParams) {
  DiagnosticPanel({ params: params })
}

@Component
export struct DiagnosticPanel {
  @Prop params: DiagnosticPanelParams = new DiagnosticPanelParams()
  private touchScroller: Scroller = new Scroller()
  @StorageLink(AppLanguage.KEY_REVISION) @Watch('appearanceChanged') languageRevision: number = 0
  @StorageLink('ui_material_revision') @Watch('appearanceChanged') materialRevision: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') personJson: string = ''
  @StorageLink(AppState.KEY_IS_LOGGED_IN) @Watch('accountChanged') loggedIn: boolean = false
  @State private report: DiagnosticReport | null = null
  @State private copyPending: boolean = false
  @State private copyError: string = ''
  private active: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.report = DiagnosticReports.get(this.params.diagnosticId)
  }
  appearanceChanged(): void { if (this.active) this.params.refreshAppearance() }
  accountChanged(): void {
    if (this.report !== null && this.report.epoch !== CampusCookies.generation()) {
      this.report = null; this.active = false; this.params.close()
    }
  }
  aboutToDisappear(): void { this.active = false; this.report = null }

  private async copy(): Promise<void> {
    if (!this.active || !this.params.isActive() || this.report === null || this.copyPending) return
    const report: DiagnosticReport = this.report
    if (report.epoch !== CampusCookies.generation()) { this.report = null; return }
    this.copyPending = true; this.copyError = ''
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, report.text())
      const property = data.getProperty(); property.shareOption = pasteboard.ShareOption.LOCALDEVICE; data.setProperty(property)
      for (let attempt: number = 0; attempt < 3; attempt++) {
        if (!this.active || !this.params.isActive() || report.epoch !== CampusCookies.generation()) return
        try { await pasteboard.getSystemPasteboard().setData(data); break }
        catch (error) {
          if ((error as BusinessError).code !== 27787277 || attempt === 2) throw error as Error
          await new Promise<void>((resolve) => { setTimeout(resolve, (attempt + 1) * 120) })
        }
      }
      if (this.active && this.params.isActive() && report.epoch === CampusCookies.generation()) {
        this.getUIContext().getPromptAction().showToast({ message: AppLanguage.text($r('app.string.detail_copied'), this.languageRevision) })
      }
    } catch (error) {
      if (this.active && this.params.isActive() && report.epoch === CampusCookies.generation()) this.copyError = ErrorDiagnostics.detail(error as Object)
    } finally { this.copyPending = false }
  }

  @Builder
  Section(title: Resource, value: string, controlId: string) {
    Column({ space: 10 }) {
      Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      Text(value).fontSize(13).lineHeight(22).fontColor(ThemeColors.textPrimary).width('100%')
        .wordBreak(WordBreak.BREAK_ALL).copyOption(CopyOptions.LocalDevice).id(controlId)
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
      .backgroundColor($r('app.color.surface_fallback')).borderRadius(20).id(controlId + '-section')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text(ReadableText.resource($r('app.string.diagnostics_hint'))).fontSize(13).lineHeight(21)
          .fontColor(ThemeColors.textSecondary).layoutWeight(1).lineBreakStrategy(LineBreakStrategy.GREEDY)
        FloatingActionButton({ label: $r('app.string.live_history_diagnostics_copy'), icon: 'copy', controlHeight: 44,
          controlId: 'diagnostics-copy', actionEnabled: this.report !== null && !this.copyPending,
          onAction: () => { this.copy() } }).width(44)
      }.width('100%').alignItems(VerticalAlign.Center)
      Scroll(this.touchScroller) {
        Column({ space: 14 }) {
          if (this.report !== null && this.report.epoch === CampusCookies.generation()) {
            Text(this.report.summary).fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium)
              .fontColor(ThemeColors.textPrimary).width('100%')
            Text(Constant.APP_DIAGNOSTIC_HEADER + '\n' +
              new Date(this.report.createdAt).toISOString()).fontSize(12).lineHeight(19)
              .fontColor(ThemeColors.textSecondary).width('100%')
            this.Section($r('app.string.diagnostics_error'), this.report.error, 'diagnostic-error-text')
            if (this.report.logs) this.Section($r('app.string.diagnostics_logs'), this.report.logs, 'diagnostic-log-text')
            else Text($r('app.string.diagnostics_no_logs')).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).width('100%')
            if (this.copyError) this.Section($r('app.string.diagnostics_copy_failed'), this.copyError, 'diagnostic-copy-error')
          } else {
            Text($r('app.string.diagnostics_expired')).fontSize(14).lineHeight(23).fontColor(ThemeColors.textSecondary).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 8 })
      }.width('100%').constraintSize({ maxHeight: this.params.maxHeight }).scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false }).id('diagnostics-scroll')
        .onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) })
    }.width('100%').alignItems(HorizontalAlign.Start).id('diagnostics-panel')
      .padding({ left: ThemeDimens.cardInset, right: ThemeDimens.cardInset, top: 8,
        bottom: Math.max(16, px2vp(this.bottomPx)) + 8 })
  }
}
