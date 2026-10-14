import { UIContext, ComponentContent, display } from '@kit.ArkUI'
import { SheetTransitionGuard } from './SheetTransitionGuard'
import { AppLanguage } from './AppLanguage'
import { adaptiveMaterial, nativeFloatingBackground } from './AdaptiveMaterial'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { DiagnosticReport, DiagnosticReports } from '../model/DiagnosticReport'
import { DiagnosticPanelParams, buildDiagnosticPanel } from '../components/DiagnosticPanel'

/** One native sheet owns its content until the closing animation completes. */
class DiagnosticSheetSession {
  transition: SheetTransitionGuard = new SheetTransitionGuard()
  context: UIContext
  params: DiagnosticPanelParams = new DiagnosticPanelParams()
  content: ComponentContent<DiagnosticPanelParams> | null = null
  active: boolean = true
  closing: boolean = false

  constructor(context: UIContext, report: DiagnosticReport) {
    this.context = context
    this.params.diagnosticId = report.id
    try { this.params.maxHeight = Math.max(160, Math.min(620, context.px2vp(display.getDefaultDisplaySync().height) * 0.7 - 100)) }
    catch (error) {}
    this.params.isActive = (): boolean => this.active
    this.params.close = () => { this.close() }
    this.params.refreshAppearance = () => { this.refreshAppearance() }
    this.content = new ComponentContent(context, wrapBuilder(buildDiagnosticPanel), this.params)
  }

  options(): SheetOptions {
    const revision: number = AppStorage.get<number>('ui_material_revision') ?? 0
    return this.transition.options(true, { height: SheetSize.FIT_CONTENT, preferType: SheetType.BOTTOM, showClose: true, dragBar: true,
      title: { title: $r('app.string.diagnostics_read') },
      backgroundColor: nativeFloatingBackground(revision), systemMaterial: adaptiveMaterial(revision),
      onWillDismiss: (action: DismissSheetAction) => { this.closing = true; this.active = false; action.dismiss() },
      onWillDisappear: () => { this.active = false }, onDisappear: () => { this.release() } })
  }
  refreshAppearance(): void {
    if (!this.active || this.content === null) return
    this.content.updateConfiguration()
    this.context.updateBindSheet(this.content, this.options(), true).catch(() => {})
  }
  close(): void {
    if (this.closing || this.content === null) return
    this.closing = true; this.active = false
    this.transition.beginClose()
    this.context.closeBindSheet(this.content).catch(() => { this.release() })
  }
  release(): void {
    this.active = false
    const content = this.content
    this.content = null
    if (content !== null) content.dispose()
    DiagnosticNavigation.released(this)
  }
}

export class DiagnosticNavigation {
  private static session: DiagnosticSheetSession | null = null
  static released(session: DiagnosticSheetSession): void {
    if (DiagnosticNavigation.session === session) DiagnosticNavigation.session = null
  }
  private static show(context: UIContext, report: DiagnosticReport): void {
    if (DiagnosticReports.get(report.id) === null) return
    const current: DiagnosticSheetSession | null = DiagnosticNavigation.session
    if (current !== null) {
      if (!current.active || current.closing) {
        current.transition.open(() => { DiagnosticNavigation.show(context, report) }, () => context)
      }
      return
    }
    try {
      const session: DiagnosticSheetSession = new DiagnosticSheetSession(context, report)
      DiagnosticNavigation.session = session
      if (session.content === null) { session.release(); return }
      context.openBindSheet(session.content, session.options()).catch(() => {
        session.release()
        context.getPromptAction().showToast({ message: AppLanguage.text($r('app.string.diagnostics_open_failed')) })
      })
    } catch (error) {
      if (DiagnosticNavigation.session !== null) DiagnosticNavigation.session.release()
      context.getPromptAction().showToast({ message: AppLanguage.text($r('app.string.diagnostics_open_failed')) })
    }
  }
  static brief(message: string, summary: string = ''): string {
    const brief: string = ErrorDiagnostics.brief(message, summary)
    if (brief === '网络连接失败，请检查网络后重新加载。') return AppLanguage.text($r('app.string.diagnostics_network_brief')) || brief
    if (brief === '暂时无法完成操作，请稍后重试。') return AppLanguage.text($r('app.string.diagnostics_generic_brief')) || brief
    return brief
  }
  static open(context: UIContext, message: string, logs: string = '', summary: string = ''): void {
    const route = context.getRouter()
    const report = DiagnosticReports.capture(message, logs, route.getState().path || '', DiagnosticNavigation.brief(message, summary))
    DiagnosticNavigation.show(context, report)
  }

  /** Transient action failures use a compact native prompt with a highlighted diagnostic action. */
  static feedback(context: UIContext, error: Object, summary: string = ''): void {
    const message: string = typeof error === 'string' ? error : ErrorDiagnostics.message(error, summary)
    const route = context.getRouter()
    const brief: string = DiagnosticNavigation.brief(message, summary)
    const report = DiagnosticReports.capture(message, '', route.getState().path || '', brief)
    context.getPromptAction().showDialog({ message: brief, buttons: [
      { text: AppLanguage.text($r('app.string.settings_cancel')), color: $r('app.color.theme_text_secondary') },
      { text: AppLanguage.text($r('app.string.diagnostics_read')), color: $r('app.color.theme_primary') }
    ] }).then((result) => {
      if (result.index === 1 && DiagnosticReports.get(report.id) !== null) {
        DiagnosticNavigation.show(context, report)
      }
    }).catch(() => {})
  }
}
