import { NetworkProxy } from '../common/NetworkProxy'
import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { BrowserLink } from '../common/BrowserLink'
import { CampusCookies } from '../common/CampusCookies'
import { ForumRoute } from '../common/ForumRoute'
import { ForumRouteHints, ForumRouteContext } from '../common/ForumRouteHints'
import { Constant } from '../common/Constant'
import { ForumImage } from '../model/ForumImage'
import { ForumImageDiagnostics } from '../model/ForumImageDiagnostics'
import { FduAuthPolicy } from '../model/FduAuth'
import { HttpError } from './HttpUtil'

/** Binary image reads use the same scoped WebVPN cookie jar as campus reads.
 * Public image hosts never receive the forum JWT or campus credentials.
 */
export class ForumImageTransfer {
  private static proxyUntil: Map<string, number> = new Map<string, number>()
  private static routeContext: string = ''
  private request: http.HttpRequest | null = null
  private rejectPending: ((error: Error | HttpError) => void) | null = null
  private cancelled: boolean = false
  private imageRead: number = 0
  private static readonly HEADER_BUDGET: number = 8000
  private static readonly IDLE_BUDGET: number = 20000
  private static readonly TOTAL_BUDGET: number = 120000
  private static readonly MAX_BYTES: number = 96 * 1024 * 1024

  async download(source: string, path: string): Promise<void> {
    const address: string = BrowserLink.normalize(source)
    if (!address) throw new Error('图片地址无效')
    if (this.cancelled) throw new Error('已取消下载')
    this.imageRead = ForumImageDiagnostics.nextRead()
    const proxy: string = ForumRoute.proxyUrl(address)
    const proxyAllowed: boolean = !!proxy && AppStorage.get<boolean>(Constant.KEY_USE_WEBVPN) !== false
    const cookies: string = proxyAllowed ? await CampusCookies.read(proxy) : ''
    if (this.cancelled) throw new Error('已取消下载')
    const epoch: number = CampusCookies.generation()
    const origin: string = address.match(/^https?:\/\/[^/?#]+/)?.[0] ?? address
    const context: ForumRouteContext = ForumRouteHints.context()
    const routeContext: string = ForumImageTransfer.contextKey(context, epoch)
    if (routeContext !== ForumImageTransfer.routeContext) {
      ForumImageTransfer.routeContext = routeContext; ForumImageTransfer.proxyUntil.clear()
    }
    const direct: boolean | undefined = proxyAllowed ? await ForumRouteHints.read(origin, context) : undefined
    if (this.cancelled || epoch !== CampusCookies.generation()) throw new Error('已取消下载')
    const rememberedProxy: boolean = !!cookies && (direct === false ||
      (direct === undefined && (ForumImageTransfer.proxyUntil.get(origin) ?? 0) > Date.now()))
    const quickFallback: boolean = !rememberedProxy && direct === undefined && !!cookies
    try {
      await this.read(rememberedProxy ? proxy : address, path, rememberedProxy ? cookies : '',
        quickFallback, false, 1, epoch)
      this.remember(origin, context, epoch, !rememberedProxy)
    } catch (e) {
      if (!this.cancelled && epoch === CampusCookies.generation() && e instanceof HttpError && e.code === 2300060 && e.isNetworkFailure()) {
        // A reused native TLS session can fail before receiving any headers.
        // Revalidate once on a new connection to the SAME origin. This never
        // relaxes certificate checks, changes trust roots or downgrades HTTPS.
        await this.read(rememberedProxy ? proxy : address, path, rememberedProxy ? cookies : '', false, true, 2, epoch)
        this.remember(origin, context, epoch, !rememberedProxy)
        return
      }
      const proxyExpired: boolean = rememberedProxy && e instanceof HttpError && e.statusCode === -2
      if (this.cancelled || epoch !== CampusCookies.generation() ||
        (!proxyExpired && !ForumImageTransfer.isConnectionFailure(e))) throw e as Error
      ForumRouteHints.forget(origin, context)
      if (routeContext === ForumImageTransfer.routeContext) ForumImageTransfer.proxyUntil.delete(origin)
      // Reuse only an image origin's verified route. A stale VPN cookie is
      // not a reason to require login for an otherwise public image read.
      if (rememberedProxy) {
        await this.read(address, path, '', false, true, 2, epoch)
        this.remember(origin, context, epoch, true)
      } else if (proxyAllowed && cookies) {
        try {
          await this.read(proxy, path, cookies, false, true, 2, epoch)
          this.remember(origin, context, epoch, false)
        } catch (proxyError) {
          // The short first-response budget is only an early route hint. If
          // the existing proxy cannot serve the image, keep one full-budget
          // direct read before reporting a failure; never launch campus SSO.
          const expired: boolean = proxyError instanceof HttpError && proxyError.statusCode === -2
          if (this.cancelled || epoch !== CampusCookies.generation() ||
            (!expired && !ForumImageTransfer.isConnectionFailure(proxyError))) throw proxyError as Error
          if (!quickFallback) throw e as Error
          await this.read(address, path, '', false, true, 3, epoch)
          this.remember(origin, context, epoch, true)
        }
      } else if (ForumImageTransfer.isTransientFailure(e)) {
        await this.read(address, path, '', false, true, 2, epoch)
        this.remember(origin, context, epoch, true)
      } else throw e as Error
    }
  }

  private remember(origin: string, context: ForumRouteContext, epoch: number, direct: boolean): void {
    if (this.cancelled || epoch !== CampusCookies.generation() ||
      ForumImageTransfer.contextKey(context, epoch) !== ForumImageTransfer.contextKey(ForumRouteHints.context(), epoch)) return
    // Keep the former short in-process fallback when network metadata is
    // unavailable; only the validated context helper may persist a hint.
    if (direct) ForumImageTransfer.proxyUntil.delete(origin)
    else ForumImageTransfer.proxyUntil.set(origin, Date.now() + 60000)
    ForumRouteHints.remember(origin, context, direct)
  }

  private static contextKey(context: ForumRouteContext, epoch: number): string {
    return JSON.stringify([epoch, context.generation, context.networkId, context.proxyAddress, context.available])
  }

  private static isConnectionFailure(error: Object): boolean {
    return error instanceof HttpError && error.isNetworkFailure() &&
      [0, 2300005, 2300006, 2300007, 2300018, 2300028, 2300052, 2300055, 2300056].includes(error.code)
  }

  private static isTransientFailure(error: Object): boolean {
    return error instanceof HttpError && error.isNetworkFailure() &&
      [2300007, 2300018, 2300028, 2300052, 2300055, 2300056].includes(error.code)
  }

  private async read(address: string, path: string, scopedCookies: string, quickFallback: boolean,
    fresh: boolean, attempt: number, epoch: number): Promise<void> {
    if (this.cancelled) throw new Error('已取消下载')
    const file: fs.File = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
    const request: http.HttpRequest = http.createHttp()
    this.request = request
    let completed: boolean = false
    let deadline: number = -1
    let firstResponse: number = -1
    let idle: number = -1
    const diagnostic = ForumImageDiagnostics.begin(epoch, address, this.imageRead, attempt, fresh, address.startsWith(ForumRoute.VPN_ORIGIN + '/'))
    try {
      if (this.cancelled || epoch !== CampusCookies.generation()) throw new Error('已取消下载')
      const cookies: string = scopedCookies || await CampusCookies.read(address)
      if (this.cancelled || epoch !== CampusCookies.generation()) throw new Error('已取消下载')
      const headers: Record<string, string> = {
        'Accept': 'image/*,application/octet-stream;q=0.9,*/*;q=0.5',
        'User-Agent': Constant.USER_AGENT
      }
      if (cookies) headers['Cookie'] = cookies
      await new Promise<void>((resolve, reject) => {
        let status: number = 0
        let ended: boolean = false
        let stopped: boolean = false
        let bytes: number = 0
        let contentType: string = ''
        let lastActivity: number = Date.now()
        const prefix: number[] = []
        const phase = (): string => diagnostic.headerMs < 0 && bytes === 0 ? 'await-response-headers' :
          ended ? 'await-stream-status' : bytes > 0 ? 'receive-body' : 'await-response-body'
        const fail = (error: Error | HttpError): void => {
          if (stopped) return
          stopped = true
          diagnostic.phase = this.cancelled ? 'cancelled' :
            error instanceof HttpError && error.statusCode >= 300 ? 'http-error' : phase()
          diagnostic.status = error instanceof HttpError ? error.statusCode : status || -1
          diagnostic.code = error instanceof HttpError ? error.code : 0
          reject(error)
        }
        this.rejectPending = fail
        const timeout = (source: string): void => {
          if (stopped) return
          diagnostic.timeoutSource = source
          fail(new HttpError(-1, 2300028, '图片加载超时，请重新加载。 Operation timeout (code 2300028; phase=' + phase() + ')', '', phase()))
          try { request.destroy() } catch (e) {}
        }
        // Keep a finite total bound, but allow a healthy, progressing large
        // original to exceed the former 20s native/35s whole-transfer cutoff.
        deadline = setTimeout(() => { timeout('total-budget') }, ForumImageTransfer.TOTAL_BUDGET)
        firstResponse = setTimeout(() => { timeout('header-budget') }, quickFallback ? 1500 : ForumImageTransfer.HEADER_BUDGET)
        const watchIdle = (): void => {
          if (stopped) return
          const remaining: number = ForumImageTransfer.IDLE_BUDGET - (Date.now() - lastActivity)
          if (remaining <= 0) timeout('body-idle')
          else idle = setTimeout(watchIdle, remaining)
        }
        const connected = (): void => {
          lastActivity = Date.now()
          if (firstResponse >= 0) { clearTimeout(firstResponse); firstResponse = -1 }
          if (idle < 0) idle = setTimeout(watchIdle, ForumImageTransfer.IDLE_BUDGET)
        }
        const finish = (): void => {
          if (stopped || !ended || status === 0) return
          if (status !== 200 || bytes === 0) { fail(new Error('图片加载失败，请重试。')); return }
          // Some image responses carry a mistaken textual Content-Type. The
          // actual raster signature is authoritative, not the MIME hint.
          if (!ForumImage.isImageHeader(prefix)) {
            const html: boolean = /text\/html|application\/xhtml\+xml/i.test(contentType)
            const loginDocument: boolean = html && address.startsWith(ForumRoute.VPN_ORIGIN + '/') &&
              FduAuthPolicy.isLoginDocument(util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(prefix)))
            const declaredType: string = contentType.split(';')[0].trim().toLowerCase()
            const safeType: string = /^[a-z0-9.+-]{1,48}\/[a-z0-9.+-]{1,48}$/.test(declaredType) ? declaredType : 'unknown'
            fail(new HttpError(loginDocument ? -2 : status, 0, '图片服务未返回有效图片，请重试。', '', '', false,
              'stage=image-content; ' + (loginDocument ? 'proof=login-document' : 'ImageContentProtocolError') +
              '; sampleBytes=' + String(prefix.length) + '; declaredType=' + safeType + '; imageHeader=false'))
            return
          }
          if (diagnostic.expectedBytes >= 0 && bytes !== diagnostic.expectedBytes) {
            fail(new HttpError(-1, 2300018, '图片未完整接收，请重新加载。', '', 'receive-body')); return
          }
          stopped = true
          diagnostic.status = status; diagnostic.phase = 'complete'
          resolve()
        }
        request.on('headersReceive', (raw: Object) => {
          if (stopped) return
          connected()
          if (diagnostic.headerMs < 0) diagnostic.headerMs = Date.now() - diagnostic.at
          const values = raw as Record<string, string>
          let encoded: boolean = false
          contentType = ''
          diagnostic.expectedBytes = -1
          for (const key of Object.keys(values)) {
            if (key.toLowerCase() === 'content-type') contentType = String(values[key])
            // Compressed HTTP bodies are decoded by the native stack; the wire
            // Content-Length then differs from the bytes delivered to this file.
            if (key.toLowerCase() === 'content-length' && /^\d+$/.test(String(values[key]))) diagnostic.expectedBytes = Number(values[key])
            if (key.toLowerCase() === 'content-encoding' && /\b(?:gzip|br|deflate)\b/i.test(String(values[key]))) encoded = true
          }
          if (encoded) diagnostic.expectedBytes = -1
        })
        request.on('dataReceive', (data: ArrayBuffer) => {
          if (stopped) return
          if (data.byteLength === 0) return
          if (this.cancelled || epoch !== CampusCookies.generation()) { fail(new Error('已取消下载')); return }
          connected()
          try {
            if (bytes + data.byteLength > ForumImageTransfer.MAX_BYTES) { fail(new Error('图片超出缓存大小限制')); return }
            const view: Uint8Array = new Uint8Array(data)
            // Binary images retain the existing small magic sample. Only a
            // declared textual error response may need enough of its actual
            // login form to distinguish it from maintenance/JSON failures.
            const sampleLimit: number = /text\/html|application\/(?:json|xhtml\+xml)/i.test(contentType) ? 8192 : 512
            const prefixCount: number = Math.min(view.length, sampleLimit - prefix.length)
            for (let i: number = 0; i < prefixCount; i++) prefix.push(view[i])
            let offset: number = 0
            while (offset < data.byteLength) {
              const written: number = fs.writeSync(file.fd, data.slice(offset))
              if (written <= 0) throw new Error('无法写入图片文件')
              offset += written
            }
            bytes += data.byteLength
            diagnostic.receivedBytes = bytes
            if (data.byteLength > 0 && diagnostic.firstByteMs < 0) diagnostic.firstByteMs = Date.now() - diagnostic.at
          } catch (e) { fail(new Error('无法保存图片，请检查剩余存储空间。')) }
        })
        request.on('dataEnd', () => { ended = true; finish() })
        request.requestInStream(address, NetworkProxy.apply({ method: http.RequestMethod.GET, header: headers,
          connectTimeout: ForumImageTransfer.HEADER_BUDGET, readTimeout: ForumImageTransfer.TOTAL_BUDGET,
          usingCache: false, reuseConnections: !fresh, inactivityMs: 5000, maxRedirects: 5 }))
          .then((code: number) => {
            if (stopped) return
            connected()
            status = code
            diagnostic.status = code
            if (code !== 200) fail(new HttpError(code, 0, code === 404 || code === 410 ?
              '图片服务未找到该图片，可能已删除或地址失效（HTTP ' + code + '）。' :
              '图片加载失败（HTTP ' + code + '），请重试。', ''))
            else finish()
          }).catch((e: BusinessError) => {
            if (stopped) return
            const code: number = e.code ?? 0
            if (code === 2300028) diagnostic.timeoutSource = 'native'
            fail(new HttpError(-1, code, '图片加载失败，请重新加载。 ' +
              (code === 2300028 ? 'Operation timeout' : 'Image transport failed') +
              ' (code ' + code + '; phase=' + phase() + ')', '', phase()))
          })
      })
      completed = true
    } finally {
      if (deadline >= 0) clearTimeout(deadline)
      if (firstResponse >= 0) clearTimeout(firstResponse)
      if (idle >= 0) clearTimeout(idle)
      this.rejectPending = null
      this.request = null
      try { request.destroy() } catch (e) {}
      ForumImageDiagnostics.finish(diagnostic, CampusCookies.generation())
      try { await fs.close(file) }
      finally { if (!completed) { try { await fs.unlink(path) } catch (e) {} } }
    }
  }

  cancel(): void {
    this.cancelled = true
    this.rejectPending?.(new Error('已取消下载'))
    try { this.request?.destroy() } catch (e) {}
  }
}
