import { ReadableText } from '../common/ReadableText'
import { webview } from '@kit.ArkWeb'
import { LibraryAccountSession } from '../repository/LibraryAccountRepository'
import { ThemeColors } from '../common/Theme'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { ErrorNotice } from './ErrorNotice'

/** Explicit, bounded browser continuation. Automatic reads never open it. */
@Component
export struct LibraryVerification {
  onVerified: () => void = () => {}
  private controller: webview.WebviewController = new webview.WebviewController()
  private timer: number = -1
  private owner: string = ''
  private active: boolean = false
  private attemptedUrl: string = ''
  @State private pending: boolean = false
  @State private error: string = ''
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
      Text(ReadableText.resource($r('app.string.library_verify_hint'))).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).width('100%').padding({ left: 20, right: 20, top: 40 }).lineBreakStrategy(LineBreakStrategy.GREEDY)
      if (this.error) ErrorNotice({ message: this.error, controlId: 'library-verification-diagnostics' }).padding({ left: 20, right: 20 })
      Web({ src: LibraryAccountSession.PAGE, controller: this.controller }).javaScriptAccess(true).domStorageAccess(true).width('100%').layoutWeight(1).onPageEnd(() => { this.check() })
    }.width('100%').height('100%')
  }
}
