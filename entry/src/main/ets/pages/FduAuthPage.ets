import { FloatingActionButton } from '../components/FloatingActionButton'
import { FduAuthPresentation } from '../common/FduAuthPresentation'
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
import { FduAuthReadiness, FduAuthDomSample, FduAuthReadinessProbe, FduAuthReadinessCallbacks } from '../common/FduAuthReadiness'
import { RequestDiagnostics } from '../model/RequestDiagnostics'

class FduAuthPageFailure extends Error {
  diagnostics: string
  constructor(message: string, diagnostics: string) {
    super(message)
    this.name = 'FduAuthPageFailure'
    this.diagnostics = diagnostics
  }
}

/** Official university page handles SMS, captcha and any later authentication methods. */
@Component
export struct FduAuthContent {
  presentation: FduAuthPresentation | undefined = undefined
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink('ui_material_revision') @Watch('appearanceChanged') materialRevision: number = 0
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
  private settled: boolean = false
  private collecting: boolean = false
  private leaving: boolean = false
  private fillTimer: number = -1
  private fillAttempts: number = 0
  private filled: boolean = false
  private readiness: FduAuthReadinessProbe | null = null
  private readinessEpoch: number = 0
  private domSample: FduAuthDomSample | null = null
  private navigationEpoch: number = 0
  private mainEndpoint: string = ''
  private progress: number = 0
  private loadStarted: number = 0
  private webFailures: string[] = []

  aboutToAppear(): void {
    if (this.presentation === undefined) Appearance.setBarAppearance('')
    if (this.presentation !== undefined) {
      this.presentation.deactivate = () => { this.deactivate() }
      this.presentation.settle = () => { this.settleVerification() }
    }
    const current = FduWebAuth.current()
    this.request = current !== null && (this.presentation === undefined || this.presentation.requestId === current.id) ? current : null
    if (this.request !== null) {
      this.navigator = new FduAuthNavigator(new NativeFduAuthBrowser(this.controller), this.request.challenge.loginUrl,
        CampusService.entryUrl(this.request.challenge.serviceUrl))
    }
  }

  aboutToDisappear(): void {
    if (this.presentation === undefined) Appearance.setBarAppearance('')
    if (this.fillTimer >= 0) clearTimeout(this.fillTimer)
    this.readiness?.cancel()
    this.navigationEpoch++
    this.stopLoading()
    this.navigator?.cancel()
    this.leaving = true
    if (this.presentation === undefined) this.settleVerification()
  }

  private settleVerification(): void {
    if (this.settled) return
    this.settled = true
    if (this.request !== null) {
      // The sheet invokes this only after native onDisappear. Compatibility
      // routes use their own component disappearance as before.
      if (this.completedCookies.length > 0) {
        FduWebAuth.complete(this.request.id, this.completedCookies)
      } else {
        FduWebAuth.cancel(this.request.id)
      }
    }
  }

  /** Stop late Web work immediately, without changing layout during native exit. */
  private deactivate(): void {
    this.leaving = true
    this.navigationEpoch++
    if (this.fillTimer >= 0) clearTimeout(this.fillTimer)
    if (this.loadTimer >= 0) clearTimeout(this.loadTimer)
    this.readiness?.cancel()
    this.navigator?.cancel()
  }

  private closeVerification(): void {
    if (this.presentation !== undefined) this.presentation.close()
    else router.back()
  }

  private appearanceChanged(): void { this.presentation?.refreshAppearance() }

  private async openLogin(): Promise<void> {
    if (this.presentation?.isCurrent() === false || this.leaving) return
    const request = this.request
    if (request === null) {
      this.showError(AppLanguage.text($r('app.string.ui_verification_has_ended_return_to_login_and_try_a'), this.languageRevision))
      return
    }
    this.attached = true
    this.startLoading(true)
    // A UA customization failure must not prevent the official page from loading.
    try {
      this.controller.setCustomUserAgent(FduAuthWebPage.mobileUserAgent(this.controller.getUserAgent()))
    } catch (e) {
      // The login URL already selects the official mobile page.
    }
    try {
      this.navigator?.onControllerAttached()
      await this.navigator?.prepare(() => FduWebAuth.prepare(request))
    } catch (e) {
      if (!this.leaving) this.showError(AppLanguage.text($r('app.string.ui_could_not_initialize_verification_tap_retry'), this.languageRevision), e as Object)
    }
  }

  private async onLoaded(url: string): Promise<void> {
    const request = this.request
    if (request === null || this.leaving) return
    const epoch: number = this.navigationEpoch
    // Empty initial documents are never a completed login page.
    if (!url || url === 'about:blank') return
    if (this.mainFrameFailed) return
    if (FduAuthPolicy.isIdUrl(url)) {
      try {
        await this.controller.runJavaScript(FduAuthWebPage.VIEWPORT_SCRIPT)
        if (!this.currentNavigation(request, epoch)) return
        await this.controller.runJavaScript(FduAuthWebPage.PLAIN_BACKGROUND_SCRIPT)
        if (!this.currentNavigation(request, epoch)) return
      } catch (e) {
        if (!this.currentNavigation(request, epoch)) return
        this.message = AppLanguage.text($r('app.string.ui_verify_on_fudan_s_official_page_pinch_to_zoom'), this.languageRevision)
      }
      if (this.currentNavigation(request, epoch)) this.waitForLoginControls(epoch)
      return
    }
    this.stopLoading()
    this.failed = false
    this.message = AppLanguage.text($r('app.string.ui_complete_verification_on_fudan_s_official_page_y'), this.languageRevision)
    if (!FduAuthPolicy.isServiceLanding(url, request.challenge.serviceUrl) || this.collecting) return
    this.collecting = true
    try {
      if (request.challenge.serviceUrl === CampusService.LIFE_CODE) {
        const ready = await this.controller.runJavaScript(
          '(function(){var field=document.getElementById("myText");return (field&&field.value)||document.getElementById("btn-agree-ok")?"ready":"pending"})()')
        if (!this.currentNavigation(request, epoch)) return
        if (!ready.includes('ready')) {
          this.collecting = false
          this.message = AppLanguage.text($r('app.string.ui_no_login_session_was_received_from_the_campus_se'), this.languageRevision)
          return
        }
      }
      if (request.challenge.serviceUrl.split('?')[0].endsWith('/xsxkCourse/loadKbxx.do')) {
        const ready = await this.controller.runJavaScript(
          '(function(){try{return Array.isArray(JSON.parse(document.body.innerText).results)?"ready":"pending"}catch(e){return "pending"}})()')
        if (!this.currentNavigation(request, epoch)) return
        if (!ready.includes('ready')) {
          this.collecting = false
          this.message = AppLanguage.text($r('app.string.ui_the_graduate_system_has_not_returned_a_timetable'), this.languageRevision)
          return
        }
      }
      // Native cookie API includes HttpOnly cookies; document.cookie would lose the session.
      let cookies: string = await webview.WebCookieManager.fetchCookie(url)
      if (!this.currentNavigation(request, epoch)) return
      // Preserve the exact landing path first. Epay's home cookie snapshot can
      // omit cookies scoped to /epay/wxpage/ used by the life-code endpoint.
      if (!cookies) {
        cookies = await webview.WebCookieManager.fetchCookie(CampusService.cookieUrl(request.challenge.serviceUrl))
        if (!this.currentNavigation(request, epoch)) return
      }
      if (!cookies) {
        cookies = await webview.WebCookieManager.fetchCookie(url)
        if (!this.currentNavigation(request, epoch)) return
      }
      if (!cookies) throw new Error('empty session')
      // A same-host portal callback can still be a login/error document. Read
      // it in memory only; auxiliary preference cookies never close WebVPN.
      // ArkWeb wraps a JSON response in a <pre> document. Validate its text;
      // HTML alone or an unfinished zlapp SSO wrapper cannot finish verification.
      const rawDocument = await this.controller.runJavaScript(FduAuthPolicy.zlappJsonTarget(request.challenge.serviceUrl) ?
        'document.body.innerText' : 'document.documentElement.outerHTML')
      if (!this.currentNavigation(request, epoch)) return
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
      if (!this.currentNavigation(request, epoch)) return
      this.completedCookies = cookies
      this.leaving = true
      this.closeVerification()
    } catch (e) {
      if (!this.currentNavigation(request, epoch)) return
      this.collecting = false
      this.showError(AppLanguage.text($r('app.string.ui_no_login_session_was_received_from_the_campus_se'), this.languageRevision), e as Object)
    }
  }

  private currentNavigation(request: FduWebAuthRequest, epoch: number): boolean {
    return !this.leaving && this.presentation?.isCurrent() !== false && !this.mainFrameFailed && epoch === this.navigationEpoch &&
      this.request === request && FduWebAuth.current()?.id === request.id
  }

  private waitForLoginControls(epoch: number): void {
    this.readinessEpoch = epoch
    if (this.readiness !== null) { this.readiness.start(); return }
    const callbacks: FduAuthReadinessCallbacks = {
      evaluate: (): Promise<string> => this.controller.runJavaScript(FduAuthReadiness.SCRIPT),
      onSample: (sample: FduAuthDomSample): void => {
        if (!this.leaving && this.readinessEpoch === this.navigationEpoch) this.domSample = sample
      },
      onReady: (_sample: FduAuthDomSample): void => {
        if (this.leaving || this.mainFrameFailed || this.failed || this.readinessEpoch !== this.navigationEpoch) return
        this.stopLoading()
        this.failed = false
        this.message = AppLanguage.text($r('app.string.ui_complete_verification_on_fudan_s_official_page_y'), this.languageRevision)
        this.scheduleFill()
      },
      onTimeout: (sample: FduAuthDomSample): void => {
        if (this.leaving || this.readinessEpoch !== this.navigationEpoch) return
        this.showError(AppLanguage.text($r('app.string.ui_verification_form_not_ready'), this.languageRevision),
          new FduAuthPageFailure('ID page did not render usable verification controls', sample.diagnostics()))
      }
    }
    this.readiness = new FduAuthReadinessProbe(callbacks, 250, 10000)
    this.readiness.start()
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
    this.readiness?.cancel()
    this.startLoading(true)
    try {
      await this.navigator.retry(() => FduWebAuth.prepare(request))
    } catch (e) {
      if (!this.leaving) this.showError(AppLanguage.text($r('app.string.ui_could_not_reload_verification_check_your_connect'), this.languageRevision), e as Object)
    }
  }

  private startLoading(reset: boolean = false): void {
    if (reset) {
      if (this.loadTimer >= 0) clearTimeout(this.loadTimer)
      this.loadTimer = -1
      this.loadStarted = Date.now()
      this.webFailures = []
      this.domSample = null
    }
    if (!this.loadStarted) this.loadStarted = Date.now()
    this.loading = true
    this.failed = false
    this.mainFrameFailed = false
    this.message = AppLanguage.text($r('app.string.ui_loading_fudan_verification'), this.languageRevision)
    if (this.loadTimer >= 0) return
    this.loadTimer = setTimeout(() => {
      if (!this.leaving) this.showError(AppLanguage.text($r('app.string.ui_verification_is_loading_slowly_check_your_connec'), this.languageRevision),
        new Error('WebViewTimeout: verification did not become usable within 15000ms'))
    }, Math.max(0, 15000 - (Date.now() - this.loadStarted)))
  }

  private stopLoading(): void {
    if (this.loadTimer >= 0) clearTimeout(this.loadTimer)
    this.loadTimer = -1
    this.loadStarted = 0
    this.loading = false
    this.refreshing = false
  }

  private showError(message: string, error: Object = new Error('Verification unavailable')): void {
    this.readiness?.cancel()
    this.stopLoading()
    this.failed = true
    this.message = message
    const detail = ErrorDiagnostics.detail(error)
    const associated = ErrorDiagnostics.associated(detail)
    const diagnostics = (this.request === null ? '' : FduWebAuth.preparationDiagnostics(this.request.id)) + '\n' +
      (this.navigator?.diagnostics() ?? 'navigator=unavailable') + '\nweb: endpoint=' + this.mainEndpoint +
      '; progress=' + this.progress + '; mainFrameFailed=' + this.mainFrameFailed +
      (this.domSample === null ? '' : '\n' + this.domSample.diagnostics()) +
      (this.webFailures.length ? '\nWeb resource failures\n' + this.webFailures.join('\n') : '') +
      (associated ? '\n' + associated : '')
    this.diagnosticError = ErrorDiagnostics.message(new FduAuthPageFailure(ErrorDiagnostics.technical(detail), diagnostics), message)
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
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 44,
          labelColor: ThemeColors.textPrimary,
          onAction: () => { this.closeVerification() } }).width(44)
        Text(AppLanguage.text($r('app.string.ui_fudan_verification'), this.languageRevision))
          .fontColor(ThemeColors.textPrimary).fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
          .textAlign(TextAlign.Center)
        FloatingActionButton({ label: $r('app.string.ui_retry'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44,
          controlId: 'verification-refresh', labelColor: ThemeColors.textPrimary,
          onAction: () => { this.retry() } }).width(44)
      }.width('100%').padding(12)
      Row({ space: 8 }) {
        if (this.loading) { LoadingProgress().width(20).height(20) }
        if (this.failed) { ErrorNotice({ message: this.diagnosticError, summary: this.message,
          textSize: 14, textColor: '#CC2929', controlId: 'verification-diagnostics' }).layoutWeight(1) }
        else Text(this.message).fontSize(13).lineHeight(21).layoutWeight(1).textAlign(TextAlign.Center)
          .fontColor(ThemeColors.textSecondary)
      }.padding(12).width('100%')
      // Measure the remaining viewport independently of Web's intrinsic height.
      // Keep the same Web node mounted during errors and retries to retain the MFA step.
      Stack() {
        Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        Web({ src: '', controller: this.controller })
          .darkMode(this.darkMode ? WebDarkMode.On : WebDarkMode.Off)
          .forceDarkAccess(true)
          .backgroundColor($r('app.color.verification_web_background'))
          .runJavaScriptOnDocumentStart([
            { script: FduAuthWebPage.IMAGE_COLORS_SCRIPT, scriptRules: ['https://*.fudan.edu.cn', 'https://fdulib.a-lsp.com'] },
            { script: FduAuthWebPage.PLAIN_BACKGROUND_SCRIPT, scriptRules: ['https://id.fudan.edu.cn'] }
          ])
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .zoomAccess(true)
          .mixedMode(MixedMode.None)
          .onControllerAttached(() => { this.openLogin() })
          .onPageBegin((event) => {
            if (event.url && event.url !== 'about:blank' && !this.leaving) {
              this.navigationEpoch++
              this.collecting = false
              this.readiness?.cancel()
              this.mainEndpoint = RequestDiagnostics.endpoint(event.url)
              this.progress = 0
              this.startLoading()
            }
            if (FduAuthPolicy.isIdUrl(event.url)) {
              this.controller.runJavaScript(FduAuthWebPage.PLAIN_BACKGROUND_SCRIPT).catch(() => {})
            }
          })
          .onPageEnd((event) => { this.onLoaded(event.url) })
          .onProgressChange((event) => { this.progress = event.newProgress })
          .onLoadIntercept((event) => {
            const url: string = event.data.getRequestUrl()
            const mobileUrl = FduAuthWebPage.mobileLoginUrl(url)
            if (event.data.isMainFrame() && mobileUrl !== url) {
              this.controller.loadUrl(mobileUrl)
              return true
            }
            // Password forms stay on HTTPS. Only the published graduate course
            // service hosts retain the legacy HTTP exception.
            return url.length > 0 && url !== 'about:blank' && !FduAuthPolicy.isCampusUrl(url)
          })
          .onErrorReceive((event) => {
            if (!this.leaving) this.webFailures = this.webFailures.concat(
              'code=' + event.error.getErrorCode() + '; main=' + event.request.isMainFrame() +
              '; endpoint=' + RequestDiagnostics.endpoint(event.request.getRequestUrl())).slice(-4)
            if (event.request.isMainFrame() && !this.leaving) {
              this.mainFrameFailed = true
              this.showError(AppLanguage.text($r('app.string.ui_could_not_load_verification_check_your_connectio'), this.languageRevision),
                new Error('WebViewError (code=' + event.error.getErrorCode() + '): ' + event.error.getErrorInfo()))
            }
          })
          .onHttpErrorReceive((event) => {
            if (!this.leaving) this.webFailures = this.webFailures.concat(
              'http=' + event.response.getResponseCode() + '; main=' + event.request.isMainFrame() +
              '; endpoint=' + RequestDiagnostics.endpoint(event.request.getRequestUrl())).slice(-4)
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
    }.width('100%').height('100%').backgroundColor(this.presentation === undefined ? $r('app.color.verification_web_background') : Color.Transparent)
      .padding({ top: this.presentation === undefined ? px2vp(this.statusBarInsetPx) : 4 })
  }
}

/** Compatibility route; live continuations use the native bottom sheet. */
@Entry
@Component
struct FduAuthPage {
  build() { Column() { FduAuthContent() }.width('100%').height('100%') }
}
