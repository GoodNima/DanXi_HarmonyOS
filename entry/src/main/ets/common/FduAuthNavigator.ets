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
  private documentReady: boolean = false
  private prepared: boolean = false
  private started: boolean = false
  private cancelled: boolean = false
  private preparing: Promise<void> | null = null

  constructor(browser: FduAuthBrowser, loginUrl: string) {
    this.browser = browser
    this.loginUrl = FduAuthWebPage.mobileLoginUrl(loginUrl)
  }

  /** Both the initial blank document and the Cookie import must finish first. */
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
    await prepareCookies()
    if (this.cancelled) return
    this.prepared = true
    this.startIfReady()
  }

  onPageEnd(url: string): void {
    if (url !== 'about:blank' || this.cancelled) return
    this.documentReady = true
    this.startIfReady()
  }

  private startIfReady(): void {
    if (!this.prepared || !this.documentReady || this.started || this.cancelled) return
    this.browser.loadUrl(this.loginUrl)
    this.started = true
  }

  async retry(prepareCookies: () => Promise<void>): Promise<void> {
    if (this.cancelled) return
    const wasStarted: boolean = this.started
    await this.prepare(prepareCookies)
    if (this.cancelled) return
    if (!this.documentReady) {
      // If the engine never completed its initial document, explicitly restart
      // that document. Its onPageEnd will open the prepared official URL.
      this.browser.loadUrl('about:blank')
      return
    }
    if (!this.started) {
      this.startIfReady()
    } else if (wasStarted) {
      // Reload the current verification step when possible. Never refresh about:blank.
      const currentUrl = this.browser.getUrl()
      if (/[?&](?:ticket|loginToken)=/i.test(currentUrl) || /\/sso\/login(?:[?#]|$)/i.test(currentUrl)) {
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
}
