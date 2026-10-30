import { webview } from '@kit.ArkWeb'
import { UIContext } from '@kit.ArkUI'
import { BookingBrowserTransport } from '../common/BookingBrowserTransport'
import { HttpUtil, HttpError } from '../util/HttpUtil'
import { RequestDiagnostics } from '../model/RequestDiagnostics'
import { CampusCookies } from '../common/CampusCookies'
import { FduAuthPolicy } from '../model/FduAuth'

/** Warm an empty ArkWeb with the page; only an actual HTTP 412 starts its
 * official safety check. Collect JSON only from the exact requested endpoint. */
@Component
export struct BookingBrowserSession {
  private controller: webview.WebviewController = new webview.WebviewController()
  @State private loadingUrl: string = ''
  @State private webMounted: boolean = false
  @State private webGeneration: number = 0
  private lease: number = 0
  private active: boolean = false
  private controllerAttached: boolean = false
  private timer: number = -1
  private start: number = 0
  private epoch: number = 0
  private headers: Record<string, string> = {}
  private resolve: ((body: string) => void) | undefined = undefined
  private reject: ((error: Error) => void) | undefined = undefined
  private revision: number = 0
  private loadIssued: boolean = false
  private downloadAttempted: boolean = false
  private begins: number = 0
  private progress: number = 0
  private webWidth: number = -1
  private webHeight: number = -1
  private pages: number = 0
  private lastHttp: number = 0
  private bodyKind: string = 'pending'
  aboutToAppear(): void {
    this.active = true; this.webMounted = true
    const context: UIContext = this.getUIContext()
    this.lease = BookingBrowserTransport.bind((url: string, headers: Record<string, string>): Promise<string> =>
      new Promise<string>((resolve, reject) => {
        context.runScopedTask(() => { this.read(url, headers).then(resolve, reject) })
      }))
  }
  aboutToDisappear(): void {
    this.active = false; this.revision++; this.finish('', new Error('Booking browser read cancelled'))
    BookingBrowserTransport.unbind(this.lease); this.webMounted = false; this.loadingUrl = ''; this.replaceBrowser()
  }
  private replaceBrowser(): void {
    this.controllerAttached = false; this.controller = new webview.WebviewController()
    this.webGeneration++
  }
  private read(url: string, headers: Record<string, string>): Promise<string> {
    if (!this.active) return Promise.reject(new Error('Booking browser is inactive'))
    this.start = Date.now(); this.epoch = CampusCookies.generation(); this.headers = headers; this.revision++
    this.loadIssued = false; this.downloadAttempted = false; this.begins = 0; this.progress = 0
    this.pages = 0; this.lastHttp = 0; this.bodyKind = 'pending'
    const revision: number = this.revision
    return new Promise<string>((resolve, reject) => {
      this.resolve = resolve; this.reject = reject; this.loadingUrl = url
      this.timer = setTimeout(() => {
        if (revision !== this.revision) return
        const detail: string = ' (timeoutSource=browser-deadline; attached=' + this.controllerAttached + '; loadIssued=' + this.loadIssued + '; begins=' + this.begins + '; progress=' + this.progress + '; pages=' + this.pages + '; http=' + this.lastHttp + '; document=' + this.bodyKind + '; webWidth=' + this.webWidth + '; webHeight=' + this.webHeight + ')'
        const error = this.controllerAttached ? new HttpError(-1, 2300028,
          '场馆网站的安全检查读取超时，请稍后重新加载。 Browser check timeout' + detail, '') : new HttpError(-1, 0,
          '场馆安全检查组件暂未就绪，请重新加载。 Booking browser controller unavailable' + detail, '', 'booking-web-attach')
        if (!this.controllerAttached) error.name = 'BookingBrowserNotReadyError'
        this.finish('', error as Error)
      }, 20000)
      if (this.controllerAttached) this.open()
    })
  }
  private open(): void {
    if (!this.active || !this.resolve || !this.controllerAttached || this.loadIssued) return
    const headers: webview.WebHeader[] = []
    for (const key of ['Accept', 'Referer', 'sign-key']) if (this.headers[key]) headers.push({ headerKey: key, headerValue: this.headers[key] })
    try {
      this.controller.setCustomUserAgent(HttpUtil.BROWSER_UA); this.controller.loadUrl(this.loadingUrl, headers)
      this.loadIssued = true
      RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', this.loadingUrl, 0, 0,
        Date.now() - this.start, 'booking-web-load-issued')
    }
    catch (e) { this.finish('', e as Error) }
  }
  private async loaded(url: string): Promise<void> {
    if (this.active && this.resolve) {
      this.pages++
      RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', url, this.lastHttp, 0, Date.now() - this.start, 'booking-web-page-end')
    }
    if (!this.active || !this.resolve || url.split('#')[0] !== this.loadingUrl) return
    const revision: number = this.revision
    try {
      const raw: string = await this.controller.runJavaScript('document.body.innerText')
      if (!this.active || revision !== this.revision || !this.resolve) return
      let body: string = raw
      try { const decoded = JSON.parse(raw) as string; if (typeof decoded === 'string') body = decoded } catch (e) {}
      this.bodyKind = body.trim().startsWith('{') ? 'json' : body.trim() ? 'non-json' : 'empty'
      if (this.bodyKind !== 'json') return // The official safety script is still running.
      JSON.parse(body) as Object
      this.finish(body)
    } catch (e) { if (revision === this.revision) this.finish('', e as Error) }
  }
  private ownsRead(revision: number, epoch: number): boolean {
    return this.active && this.resolve !== undefined && revision === this.revision &&
      epoch === this.epoch && epoch === CampusCookies.generation()
  }
  private async downloaded(url: string): Promise<void> {
    if (!this.active || !this.resolve || this.downloadAttempted || url !== this.loadingUrl ||
      !BookingBrowserTransport.allowed(url)) return
    this.downloadAttempted = true
    const revision: number = this.revision, epoch: number = this.epoch
    if (!this.ownsRead(revision, epoch)) return
    const remaining: number = 20000 - (Date.now() - this.start)
    if (remaining <= 0) return // The existing browser deadline still owns this read.
    const headers: Record<string, string> = { 'User-Agent': HttpUtil.BROWSER_UA, 'Authorization': '' }
    for (const key of ['Accept', 'Referer', 'sign-key']) if (this.headers[key]) headers[key] = this.headers[key]
    this.bodyKind = 'download'
    RequestDiagnostics.record(epoch, CampusCookies.generation(), 'GET', url, 0, 0,
      Date.now() - this.start, 'booking-web-download-read')
    try {
      // ArkWeb may deliver the API's JSON as a download rather than a document.
      // Re-read only this pending GET through the shared browser Cookie jar;
      // never forward the previous Cookie, credentials or the download target.
      const response = await HttpUtil.getInstance().get(url, undefined, headers, Math.min(15000, remaining), false, false)
      if (!this.ownsRead(revision, epoch)) return
      const body: string = response.data
      let valid: boolean = false
      try { JSON.parse(body) as Object; valid = body.trim().startsWith('{') } catch (e) {}
      if (!valid) {
        const error = new HttpError(-1, 0, '场馆网站返回了无法识别的数据，请重新加载。 Booking download response is not JSON', '')
        error.name = 'BookingBrowserProtocolError'
        this.finish('', error as Error)
        return
      }
      this.bodyKind = 'json'; this.finish(body)
    } catch (e) { if (this.ownsRead(revision, epoch)) this.finish('', e as Error) }
  }
  private finish(body: string, error?: Error): void {
    if (!this.resolve) return
    const resolve = this.resolve, reject = this.reject, url = this.loadingUrl
    this.resolve = undefined; this.reject = undefined
    if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1
    const diagnostics = RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', url,
      error instanceof HttpError ? error.statusCode : error === undefined ? 200 : -1,
      error instanceof HttpError ? error.code : 0, Date.now() - this.start, 'browser-safety-check')
    if (error instanceof HttpError && diagnostics) error.diagnostics = error.diagnostics ? error.diagnostics + '\n' + diagnostics : diagnostics
    if (error === undefined) resolve(body); else if (reject !== undefined) reject(error)
  }
  build() {
    Stack() {
    if (this.webMounted) ForEach([this.webGeneration], (generation: number) => {
      Web({ src: '', controller: this.controller })
      .javaScriptAccess(true).domStorageAccess(true)
      .width('100%').height('100%').opacity(0).hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      .onAreaChange((_old: Area, area: Area) => {
        if (generation !== this.webGeneration) return
        this.webWidth = Math.round(Number(area.width)); this.webHeight = Math.round(Number(area.height))
      })
      .onControllerAttached(() => {
        if (generation !== this.webGeneration || !this.active || this.controllerAttached) return
        this.controllerAttached = true
        if (this.resolve) this.open()
      })
      .onPageBegin((event) => {
        if (generation !== this.webGeneration || !this.active || !this.resolve || event.url.split('#')[0] !== this.loadingUrl) return
        this.begins++
        RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', this.loadingUrl, 0, 0,
          Date.now() - this.start, 'booking-web-page-begin')
      })
      .onProgressChange((event) => {
        if (generation === this.webGeneration && this.active && this.resolve) this.progress = Math.max(this.progress, event.newProgress)
      })
      .onPageEnd((event) => {
        if (generation === this.webGeneration && event.url && event.url !== 'about:blank') this.loaded(event.url)
      })
      .onDownloadStart((event) => { if (generation === this.webGeneration) this.downloaded(event.url) })
      .onHttpErrorReceive((event) => {
        if (generation !== this.webGeneration || !this.resolve || !event.request.isMainFrame() || event.request.getRequestUrl().split('#')[0] !== this.loadingUrl) return
        this.lastHttp = event.response.getResponseCode()
        RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', event.request.getRequestUrl(), this.lastHttp, 0,
          Date.now() - this.start, 'booking-web-http-error')
        // HTTP 412 is the reason for this official safety-check Web. Other
        // service failures must retain their actual status instead of becoming MFA.
        if (this.lastHttp !== 412) this.finish('', new HttpError(this.lastHttp, 0,
          '场馆网站暂时无法读取数据，请稍后重新加载。 HTTP ' + this.lastHttp, '') as Error)
      })
      .onErrorReceive((event) => {
        if (generation !== this.webGeneration || !this.resolve || !event.request.isMainFrame() || event.request.getRequestUrl().split('#')[0] !== this.loadingUrl) return
        const code: number = event.error.getErrorCode()
        RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', event.request.getRequestUrl(), -1, event.error.getErrorCode(),
          Date.now() - this.start, 'booking-web-load-error')
        this.finish('', new HttpError(-1, code,
          '场馆网站的安全检查页面加载失败，请检查网络后重新加载。 WebViewError (code=' + code + ')', '') as Error)
      })
      .onLoadIntercept((event) => {
        if (generation !== this.webGeneration || !this.active) return true
        if (!event.data.isMainFrame()) return false
        const url: string = event.data.getRequestUrl()
        if (!url || url === 'about:blank') return false
        if (!this.resolve) return true
        if (BookingBrowserTransport.allowed(url)) return false
        if (FduAuthPolicy.isIdUrl(url) || FduAuthPolicy.isWebVpnLoginUrl(url)) {
          this.finish('', new HttpError(-2, 412, '场馆预约需要继续身份验证，请点击继续验证。', '') as Error)
        } else {
          const error = new HttpError(-1, 0, '场馆网站返回了无法识别的页面跳转，请重新加载。 Booking browser unexpected navigation', '')
          error.name = 'BookingBrowserProtocolError'
          this.finish('', error as Error)
        }
        return true
      })
    }, (generation: number): string => String(generation))
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }
}
