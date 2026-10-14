import { webview } from '@kit.ArkWeb'
import { BookingBrowserTransport } from '../common/BookingBrowserTransport'
import { HttpUtil, HttpError } from '../util/HttpUtil'
import { RequestDiagnostics } from '../model/RequestDiagnostics'
import { CampusCookies } from '../common/CampusCookies'

/** Created only after an actual HTTP 412. The official page runs its own safety
 * check in ArkWeb; JSON is collected only from the exact requested endpoint. */
@Component
export struct BookingBrowserSession {
  private controller: webview.WebviewController = new webview.WebviewController()
  @State private loadingUrl: string = ''
  private lease: number = 0
  private active: boolean = false
  private pageReady: boolean = false
  private timer: number = -1
  private start: number = 0
  private epoch: number = 0
  private headers: Record<string, string> = {}
  private resolve: ((body: string) => void) | undefined = undefined
  private reject: ((error: Error) => void) | undefined = undefined
  private revision: number = 0
  private pages: number = 0
  private lastHttp: number = 0
  private bodyKind: string = 'pending'
  aboutToAppear(): void { this.active = true; this.lease = BookingBrowserTransport.bind((url: string, headers: Record<string, string>): Promise<string> => this.read(url, headers)) }
  aboutToDisappear(): void { this.active = false; this.revision++; this.finish('', new Error('Booking browser read cancelled')); BookingBrowserTransport.unbind(this.lease) }
  private read(url: string, headers: Record<string, string>): Promise<string> {
    if (!this.active) return Promise.reject(new Error('Booking browser is inactive'))
    this.start = Date.now(); this.epoch = CampusCookies.generation(); this.headers = headers; this.revision++
    this.pages = 0; this.lastHttp = 0; this.bodyKind = 'pending'
    return new Promise<string>((resolve, reject) => {
      this.resolve = resolve; this.reject = reject; this.loadingUrl = url
      this.timer = setTimeout(() => { this.finish('', new HttpError(-2, 412, '场馆网站的安全检查暂未完成，请点击继续验证或稍后重新加载。 Browser check incomplete (pages=' + this.pages + '; http=' + this.lastHttp + '; document=' + this.bodyKind + ')', '') as Error) }, 20000)
      if (this.pageReady) this.open()
    })
  }
  private open(): void {
    const headers: webview.WebHeader[] = []
    for (const key of ['Accept', 'Referer', 'sign-key']) if (this.headers[key]) headers.push({ headerKey: key, headerValue: this.headers[key] })
    try { this.controller.setCustomUserAgent(HttpUtil.BROWSER_UA); this.controller.loadUrl(this.loadingUrl, headers) }
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
  private finish(body: string, error?: Error): void {
    if (!this.resolve) return
    const resolve = this.resolve, reject = this.reject, url = this.loadingUrl
    this.resolve = undefined; this.reject = undefined
    if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1
    RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', url, error === undefined ? 200 : -1,
      error instanceof HttpError ? error.code : 0, Date.now() - this.start, 'browser-safety-check')
    if (error === undefined) resolve(body); else if (reject !== undefined) reject(error)
  }
  build() {
    if (this.loadingUrl) Web({ src: 'about:blank', controller: this.controller })
      .javaScriptAccess(true).domStorageAccess(true)
      .width('100%').height('100%').opacity(0).hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      .onControllerAttached(() => {
        this.controller.setCustomUserAgent(HttpUtil.BROWSER_UA)
      })
      .onPageEnd((event) => {
        // loadUrl during onControllerAttached can be overwritten by Web's
        // initial src navigation. Start only after that blank document ends.
        if (event.url === 'about:blank' && !this.pageReady) {
          this.pageReady = true
          if (this.resolve) this.open()
        } else this.loaded(event.url)
      })
      .onHttpErrorReceive((event) => {
        if (!this.resolve || !event.request.isMainFrame()) return
        this.lastHttp = event.response.getResponseCode()
        RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', event.request.getRequestUrl(), this.lastHttp, 0,
          Date.now() - this.start, 'booking-web-http-error')
      })
      .onErrorReceive((event) => {
        if (!this.resolve || !event.request.isMainFrame()) return
        RequestDiagnostics.record(this.epoch, CampusCookies.generation(), 'GET', event.request.getRequestUrl(), -1, event.error.getErrorCode(),
          Date.now() - this.start, 'booking-web-load-error')
      })
      .onLoadIntercept((event) => {
        if (!event.data.isMainFrame()) return false
        const url: string = event.data.getRequestUrl()
        if (url === 'about:blank' || BookingBrowserTransport.allowed(url)) return false
        this.finish('', new HttpError(-2, 412, '场馆预约需要继续身份验证，请点击继续验证。', '') as Error); return true
      })
  }
}
