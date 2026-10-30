import { ReadableText } from '../common/ReadableText'
import { webview } from '@kit.ArkWeb'
import { LibraryAccountSession } from '../repository/LibraryAccountRepository'
import { ThemeColors } from '../common/Theme'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { ErrorNotice } from './ErrorNotice'
import { FloatingActionButton } from './FloatingActionButton'
import { FduAuthWebPage } from '../common/FduAuthWebPage'

/** Explicit, bounded browser continuation. Automatic reads never open it. */
@Component
export struct LibraryVerification {
  @StorageLink('app_dark_mode') darkMode: boolean = false
  onVerified: () => void = () => {}
  onClose: () => void = () => {}
  private controller: webview.WebviewController = new webview.WebviewController()
  private timer: number = -1
  private owner: string = ''
  private active: boolean = false
  private attemptedUrl: string = ''
  @State private pending: boolean = false
  @State private error: string = ''
  private retry(): void {
    if (!this.active || this.pending) return
    this.error = ''; this.attemptedUrl = ''
    try {
      // A callback code is single-use; preserve an unfinished MFA page but
      // start a fresh library transaction after a failed callback exchange.
      if (/^https:\/\/opac\.fudan\.edu\.cn\/#\/redirect\?/.test(this.controller.getUrl())) this.controller.loadUrl(LibraryAccountSession.PAGE)
      else this.controller.refresh()
    } catch (error) { this.error = ErrorDiagnostics.message(error as Object) }
  }
  aboutToAppear(): void { this.active = true; this.owner = LibraryAccountSession.owner(); this.timer = setInterval(() => { this.check() }, 700) }
  aboutToDisappear(): void { this.active = false; if (this.timer >= 0) clearInterval(this.timer); this.timer = -1 }
  private async check(): Promise<void> {
    if (!this.active || this.pending) return
    let url: string = ''; try { url = this.controller.getUrl() } catch (e) { return }
    if (!/^https:\/\/opac\.fudan\.edu\.cn\/#\/redirect\?/.test(url) || !/[?&]code=/.test(url) || url === this.attemptedUrl) return
    this.attemptedUrl = url
    this.pending = true
    try { await LibraryAccountSession.accept(url, this.owner); if (this.active) this.onVerified() }
    catch (e) { if (this.active) this.error = ErrorDiagnostics.message(e as Object) }
    finally { this.pending = false }
  }
  build() {
    Column({ space: 8 }) {
      Row() {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 44,
          onAction: () => { this.onClose() } }).width(44)
        Text($r('app.string.ui_fudan_verification')).fontSize(20).fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
        FloatingActionButton({ label: $r('app.string.ui_retry'), icon: 'refresh', zeroContentPadding: true,
          controlHeight: 44, actionEnabled: !this.pending, controlId: 'library-verification-refresh',
          onAction: () => { this.retry() } }).width(44)
      }.width('100%').padding({ left: 12, right: 12, top: 4 })
      Text(ReadableText.resource($r('app.string.library_verify_hint'))).fontSize(13).lineHeight(21).textAlign(TextAlign.Center)
        .fontColor(ThemeColors.textSecondary).width('100%').padding({ left: 20, right: 20 }).lineBreakStrategy(LineBreakStrategy.GREEDY)
      if (this.error) ErrorNotice({ message: this.error, controlId: 'library-verification-diagnostics' }).padding({ left: 20, right: 20 })
      Web({ src: LibraryAccountSession.PAGE, controller: this.controller })
        .darkMode(this.darkMode ? WebDarkMode.On : WebDarkMode.Off)
        .forceDarkAccess(true)
        .backgroundColor($r('app.color.verification_web_background'))
        .runJavaScriptOnDocumentStart([
          { script: FduAuthWebPage.IMAGE_COLORS_SCRIPT, scriptRules: ['https://*.fudan.edu.cn', 'https://fdulib.a-lsp.com'] },
          { script: FduAuthWebPage.PLAIN_BACKGROUND_SCRIPT, scriptRules: ['https://id.fudan.edu.cn'] }
        ])
        .javaScriptAccess(true).domStorageAccess(true).width('100%').layoutWeight(1).onPageEnd(() => { this.check() })
    }.width('100%').height('100%')
  }
}
