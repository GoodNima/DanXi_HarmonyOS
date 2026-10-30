import { FduAuthPolicy } from '../model/FduAuth'
import { FduAuthWebPage } from './FduAuthWebPage'
import { webview } from '@kit.ArkWeb'

/** The small controller surface needed to coordinate native Web startup. */
export interface FduAuthBrowser {
  loadUrl(url: string): void
  getUrl(): string
  refresh(): void
}

export class NativeFduAuthBrowser implements FduAuthBrowser {
  private controller: webview.WebviewController

  constructor(controller: webview.WebviewController) {
    this.controller = controller
  }

  loadUrl(url: string): void {
    this.controller.loadUrl(url)
  }

  getUrl(): string {
    return this.controller.getUrl()
  }

  refresh(): void {
    this.controller.refresh()
  }
}

export class FduAuthNavigator {
  private browser: FduAuthBrowser
  private loginUrl: string
  private serviceEntry: string
  private attached: boolean = false
  private prepared: boolean = false
  private started: boolean = false
  private cancelled: boolean = false
  private preparing: Promise<void> | null = null
  private attachCount: number = 0
  private prepareCount: number = 0
  private startCount: number = 0
  private retryCount: number = 0

  constructor(browser: FduAuthBrowser, loginUrl: string, serviceEntry: string = loginUrl) {
    this.browser = browser
    this.loginUrl = FduAuthWebPage.mobileLoginUrl(loginUrl)
    this.serviceEntry = FduAuthPolicy.isCampusUrl(serviceEntry) && !FduAuthPolicy.isIdUrl(serviceEntry) ? serviceEntry : ''
  }

  /** The Web uses an empty src, so no initial document can overwrite loadUrl. */
  onControllerAttached(): void {
    this.attachCount++
    if (this.cancelled) return
    this.attached = true
    this.startIfReady()
  }

  /** Both controller attachment and Cookie import must finish first. */
  async prepare(prepareCookies: () => Promise<void>): Promise<void> {
    if (this.cancelled || this.prepared) return
    if (this.preparing !== null) return this.preparing
    this.preparing = this.prepareOnce(prepareCookies)
    try {
      await this.preparing
    } finally {
      this.preparing = null
    }
  }

  private async prepareOnce(prepareCookies: () => Promise<void>): Promise<void> {
    this.prepareCount++
    await prepareCookies()
    if (this.cancelled) return
    this.prepared = true
    this.startIfReady()
  }

  private startIfReady(): void {
    if (!this.prepared || !this.attached || this.started || this.cancelled) return
    this.started = true
    this.startCount++
    try {
      this.browser.loadUrl(this.loginUrl)
    } catch (e) {
      this.started = false
      throw e as Error
    }
  }

  async retry(prepareCookies: () => Promise<void>): Promise<void> {
    if (this.cancelled || !this.attached) return
    this.retryCount++
    const wasStarted: boolean = this.started
    await this.prepare(prepareCookies)
    if (this.cancelled) return
    if (!this.started) {
      this.startIfReady()
    } else if (wasStarted) {
      // Reload the current verification step when possible. Never refresh about:blank.
      const currentUrl = this.browser.getUrl()
      if (FduAuthPolicy.isIncompleteIdLoginUrl(currentUrl)) {
        if (!this.serviceEntry) throw new Error('身份验证缺少登录上下文，请返回原页面重新验证。')
        this.browser.loadUrl(this.serviceEntry)
      } else if (/[?&](?:ticket|loginToken)=/i.test(currentUrl) || /\/sso\/login(?:[?#]|$)/i.test(currentUrl)) {
        // A service ticket may already have been consumed before a landing-page
        // error. Restart at the service entry to avoid spending it twice.
        this.browser.loadUrl(this.loginUrl)
      } else if (FduAuthPolicy.isCampusUrl(currentUrl)) this.browser.refresh()
      else this.browser.loadUrl(this.loginUrl)
    }
  }

  cancel(): void {
    this.cancelled = true
  }

  /** Safe startup state only; URLs, credentials and Cookie values are excluded. */
  diagnostics(): string {
    return 'navigator: attached=' + this.attached + '; preparing=' + (this.preparing !== null) +
      '; prepared=' + this.prepared + '; started=' + this.started + '; cancelled=' + this.cancelled +
      '; attachCount=' + this.attachCount + '; prepareCount=' + this.prepareCount +
      '; startCount=' + this.startCount + '; retryCount=' + this.retryCount +
      '; initialIdContextIncomplete=' + FduAuthPolicy.isIncompleteIdLoginUrl(this.loginUrl) +
      '; serviceReentryAvailable=' + (this.serviceEntry.length > 0)
  }
}
