import { FloatingActionButton } from '../components/FloatingActionButton'
import { AppLanguage } from '../common/AppLanguage'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { Appearance } from '../common/Appearance'
import { router } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { Constant } from '../common/Constant'
import { FduWebAuth, FduWebAuthRequest } from '../common/FduWebAuth'
import { FduAuthWebPage } from '../common/FduAuthWebPage'
import { FduAuthNavigator, NativeFduAuthBrowser } from '../common/FduAuthNavigator'
import { FduAuthPolicy } from '../model/FduAuth'
import { ThemeColors } from '../common/Theme'
import { CampusService } from '../common/CampusService'
import { ErrorNotice } from '../components/ErrorNotice'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'

/** Official university page handles SMS, captcha and any later authentication methods. */
@Entry
@Component
struct FduAuthPage {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) statusBarInsetPx: number = 0
  @State message: string = AppLanguage.text($r('app.string.ui_complete_verification_on_fudan_s_official_page_y'), this.languageRevision)
  @State failed: boolean = false
  @State diagnosticError: string = ''
  @State refreshing: boolean = false
  @State private pullOffset: number = 0
  @State loading: boolean = true
  @State webHeight: number = 1
  private controller: webview.WebviewController = new webview.WebviewController()
  private navigator: FduAuthNavigator | null = null
  private attached: boolean = false
  private mainFrameFailed: boolean = false
  private loadTimer: number = -1
  private request: FduWebAuthRequest | null = null
  private completedCookies: string = ''
  private collecting: boolean = false
  private leaving: boolean = false
  private fillTimer: number = -1
  private fillAttempts: number = 0
  private filled: boolean = false

  aboutToAppear(): void {
    Appearance.setBarAppearance('light')
    this.request = FduWebAuth.current()
    if (this.request !== null) {
      this.navigator = new FduAuthNavigator(new NativeFduAuthBrowser(this.controller), this.request.challenge.loginUrl)
    }
  }

  aboutToDisappear(): void {
    Appearance.setBarAppearance('')
    if (this.fillTimer >= 0) clearTimeout(this.fillTimer)
    this.stopLoading()
    this.navigator?.cancel()
    this.leaving = true
    if (this.request !== null) {
      // Resume the caller after this route has closed, avoiding competing route changes.
      if (this.completedCookies.length > 0) {
        FduWebAuth.complete(this.request.id, this.completedCookies)
      } else {
        FduWebAuth.cancel(this.request.id)
      }
    }
  }

  private async openLogin(): Promise<void> {
    const request = this.request
    if (request === null) {
      this.showError(AppLanguage.text($r('app.string.ui_verification_has_ended_return_to_login_and_try_a'), this.languageRevision))
      return
    }
    this.attached = true
    this.startLoading()
    // A UA customization failure must not prevent the official page from loading.
    try {
      this.controller.setCustomUserAgent(FduAuthWebPage.mobileUserAgent(this.controller.getUserAgent()))
    } catch (e) {
      // The login URL already selects the official mobile page.
    }
    try {
      await this.navigator?.prepare(() => FduWebAuth.prepare(request))
    } catch (e) {
      if (!this.leaving) this.showError(AppLanguage.text($r('app.string.ui_could_not_initialize_verification_tap_retry'), this.languageRevision), e as Object)
    }
  }

  private async onLoaded(url: string): Promise<void> {
    const request = this.request
    if (request === null || this.leaving) return
    try {
      this.navigator?.onPageEnd(url)
    } catch (e) {
      this.showError(AppLanguage.text($r('app.string.ui_could_not_open_verification_tap_retry'), this.languageRevision), e as Object)
      return
    }
    // The initial blank document is only a startup barrier, never a completed login page.
    if (url === 'about:blank') return
    this.stopLoading()
    if (this.mainFrameFailed) return
    this.failed = false
    this.message = AppLanguage.text($r('app.string.ui_verify_on_fudan_s_official_page_return_is_automa'), this.languageRevision)
    if (FduAuthPolicy.isIdUrl(url)) {
      try {
        await this.controller.runJavaScript(FduAuthWebPage.VIEWPORT_SCRIPT)
        await this.controller.runJavaScript(FduAuthWebPage.PLAIN_BACKGROUND_SCRIPT)
      } catch (e) {
        this.message = AppLanguage.text($r('app.string.ui_verify_on_fudan_s_official_page_pinch_to_zoom'), this.languageRevision)
      }
      this.scheduleFill()
      return
    }
    if (!FduAuthPolicy.isServiceLanding(url, request.challenge.serviceUrl) || this.collecting) return
    this.collecting = true
    try {
      if (request.challenge.serviceUrl === CampusService.LIFE_CODE) {
        const ready = await this.controller.runJavaScript(
          '(function(){var field=document.getElementById("myText");return (field&&field.value)||document.getElementById("btn-agree-ok")?"ready":"pending"})()')
        if (!ready.includes('ready')) {
          this.collecting = false
          this.message = AppLanguage.text($r('app.string.ui_no_login_session_was_received_from_the_campus_se'), this.languageRevision)
          return
        }
      }
      if (request.challenge.serviceUrl.split('?')[0].endsWith('/xsxkCourse/loadKbxx.do')) {
        const ready = await this.controller.runJavaScript(
          '(function(){try{return Array.isArray(JSON.parse(document.body.innerText).results)?"ready":"pending"}catch(e){return "pending"}})()')
        if (!ready.includes('ready')) {
          this.collecting = false
          this.message = AppLanguage.text($r('app.string.ui_the_graduate_system_has_not_returned_a_timetable'), this.languageRevision)
          return
        }
      }
      // Native cookie API includes HttpOnly cookies; document.cookie would lose the session.
      let cookies: string = await webview.WebCookieManager.fetchCookie(url)
      // Preserve the exact landing path first. Epay's home cookie snapshot can
      // omit cookies scoped to /epay/wxpage/ used by the life-code endpoint.
      if (!cookies) cookies = await webview.WebCookieManager.fetchCookie(CampusService.cookieUrl(request.challenge.serviceUrl))
      if (!cookies) cookies = await webview.WebCookieManager.fetchCookie(url)
      if (!cookies) throw new Error('empty session')
      // A same-host portal callback can still be a login/error document. Read
      // it in memory only; auxiliary preference cookies never close WebVPN.
      // ArkWeb wraps a JSON response in a <pre> document. Validate its text;
      // HTML alone or an unfinished zlapp SSO wrapper cannot finish verification.
      const rawDocument = await this.controller.runJavaScript(FduAuthPolicy.zlappJsonTarget(request.challenge.serviceUrl) ?
        'document.body.innerText' : 'document.documentElement.outerHTML')
      let document = rawDocument
      try {
        const decoded = JSON.parse(rawDocument) as string
        if (typeof decoded === 'string') document = decoded
      } catch (error) {}
      if (!FduAuthPolicy.isServiceDocument(url, request.challenge.serviceUrl, document, cookies)) {
        this.collecting = false
        this.message = AppLanguage.text($r('app.string.ui_no_login_session_was_received_from_the_campus_se'), this.languageRevision)
        return
      }
      if (this.leaving) return
      this.completedCookies = cookies
      this.leaving = true
      router.back()
    } catch (e) {
      this.collecting = false
      this.message = AppLanguage.text($r('app.string.ui_no_login_session_was_received_from_the_campus_se'), this.languageRevision)
    }
  }

  private scheduleFill(): void {
    if (!this.request?.password) return
    if (this.filled || this.fillAttempts >= 10 || this.leaving) return
    if (this.fillTimer >= 0) clearTimeout(this.fillTimer)
    this.fillTimer = setTimeout(() => { this.fillLogin() }, 500)
  }

  private async retry(): Promise<void> {
    const request = this.request
    if (request === null || !this.attached || this.navigator === null) {
      this.showError(AppLanguage.text($r('app.string.ui_verification_is_not_ready_yet_retry_later_or_log'), this.languageRevision))
      return
    }
    this.startLoading()
    try {
      await this.navigator.retry(() => FduWebAuth.prepare(request))
    } catch (e) {
      if (!this.leaving) this.showError(AppLanguage.text($r('app.string.ui_could_not_reload_verification_check_your_connect'), this.languageRevision), e as Object)
    }
  }

  private startLoading(): void {
    if (this.loadTimer >= 0) clearTimeout(this.loadTimer)
    this.loading = true
    this.failed = false
    this.mainFrameFailed = false
    this.message = AppLanguage.text($r('app.string.ui_loading_fudan_verification'), this.languageRevision)
    this.loadTimer = setTimeout(() => {
      if (!this.leaving) this.showError(AppLanguage.text($r('app.string.ui_verification_is_loading_slowly_check_your_connec'), this.languageRevision),
        new Error('WebViewTimeout: verification page did not settle within 30000ms'))
    }, 30000)
  }

  private stopLoading(): void {
    if (this.loadTimer >= 0) clearTimeout(this.loadTimer)
    this.loadTimer = -1
    this.loading = false
    this.refreshing = false
  }

  private showError(message: string, error: Object = new Error('Verification unavailable')): void {
    this.stopLoading()
    this.failed = true
    this.message = message
    this.diagnosticError = ErrorDiagnostics.message(error, message)
  }

  private async fillLogin(): Promise<void> {
    const request = this.request
    if (request === null || this.leaving || this.filled) return
    this.fillAttempts++
    const script: string = FduAuthWebPage.fillScript(request.studentId, request.password)
    try {
      const result: string = await this.controller.runJavaScript(script)
      this.filled = result.indexOf('filled') >= 0
    } catch (e) {
      // The page may still be starting its SPA. Retry only for this initial render.
    }
    this.scheduleFill()
  }

  build() {
    Column() {
      Row() {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48, labelColor: '#1A1A2E',
          onAction: () => { router.back() } }).width(48)
        Text(AppLanguage.text($r('app.string.ui_fudan_verification'), this.languageRevision)).fontColor('#1A1A2E').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button(AppLanguage.text($r('app.string.ui_retry'), this.languageRevision)).onClick(() => { this.retry() })
      }.width('100%').padding(12)
      Row({ space: 8 }) {
        if (this.loading) { LoadingProgress().width(20).height(20) }
        if (this.failed) { ErrorNotice({ message: this.diagnosticError, summary: this.message,
          textSize: 14, textColor: '#CC2929', controlId: 'verification-diagnostics' }).layoutWeight(1) }
        else Text(this.message).fontSize(14).layoutWeight(1).fontColor('#5A5A7A')
      }.padding(12).width('100%')
      // Measure the remaining viewport independently of Web's intrinsic height.
      // Keep the same Web node mounted during errors and retries to retain the MFA step.
      Stack() {
        Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        Web({ src: 'about:blank', controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .zoomAccess(true)
          .mixedMode(MixedMode.None)
          .onControllerAttached(() => { this.openLogin() })
          .onPageBegin((event) => {
            if (event.url !== 'about:blank' && !this.leaving) this.startLoading()
            if (FduAuthPolicy.isIdUrl(event.url)) {
              this.controller.runJavaScript(FduAuthWebPage.PLAIN_BACKGROUND_SCRIPT).catch(() => {})
            }
          })
          .onPageEnd((event) => { this.onLoaded(event.url) })
          .onLoadIntercept((event) => {
            const url: string = event.data.getRequestUrl()
            const mobileUrl = FduAuthWebPage.mobileLoginUrl(url)
            if (event.data.isMainFrame() && mobileUrl !== url) {
              this.controller.loadUrl(mobileUrl)
              return true
            }
            // Password forms stay on HTTPS. Only the published graduate course
            // service hosts retain the legacy HTTP exception.
            return url !== 'about:blank' && !FduAuthPolicy.isCampusUrl(url)
          })
          .onErrorReceive((event) => {
            if (event.request.isMainFrame() && !this.leaving) {
              this.mainFrameFailed = true
              this.showError(AppLanguage.text($r('app.string.ui_could_not_load_verification_check_your_connectio'), this.languageRevision),
                new Error('WebViewError (code=' + event.error.getErrorCode() + '): ' + event.error.getErrorInfo()))
            }
          })
          .onHttpErrorReceive((event) => {
            if (event.request.isMainFrame() && !this.leaving) {
              this.mainFrameFailed = true
              this.showError(AppLanguage.text($r('app.string.ui_verification_is_temporarily_unavailable_try_agai'), this.languageRevision),
                new Error('WebViewHttpError: HTTP ' + event.response.getResponseCode() + ' ' + event.response.getReasonMessage()))
            }
          })
          .height(this.webHeight)
          .width('100%')
        }.width('100%').height('100%').onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => { this.retry() })
        FeedRefreshProgress({ pullOffset: this.pullOffset, refreshing: this.refreshing })
      }.width('100%').layoutWeight(1)
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.webHeight = Math.max(1, Number(area.height))
        })
    }.width('100%').height('100%').backgroundColor('#FFFFFF')
      .padding({ top: px2vp(this.statusBarInsetPx) })
  }
}
