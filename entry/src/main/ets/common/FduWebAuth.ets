import { router } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { FduAuthChallenge, FduAuthPolicy } from '../model/FduAuth'
import { CampusCookies } from './CampusCookies'

export class FduAuthCancelledError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'FduAuthCancelledError'
  }
}

/** Credentials stay in memory, never in route parameters, storage, or log messages. */
export class FduWebAuthRequest {
  id: number
  challenge: FduAuthChallenge
  studentId: string
  password: string

  constructor(id: number, challenge: FduAuthChallenge, studentId: string, password: string) {
    this.id = id
    this.challenge = challenge
    this.studentId = studentId
    this.password = password
  }
}

/** One continuation at a time; FduRepository serializes service authentication. */
export class FduWebAuth {
  private static sequence: number = 0
  private static active: FduWebAuthRequest | null = null
  private static resolvePending: ((cookies: string) => void) | null = null
  private static rejectPending: ((error: Error) => void) | null = null
  private static resetBrowser: boolean = false
  private static pending: Promise<string> | null = null
  private static resetting: Promise<void> | null = null

  /** Clear the previous account before HTTP authentication too. Clearing only
   * when the later Web route attaches would erase a newly established CAS SSO. */
  static async prepareSession(): Promise<void> {
    if (FduWebAuth.resetting !== null) return FduWebAuth.resetting
    if (!FduWebAuth.resetBrowser) { CampusCookies.resume(); return }
    const generation = CampusCookies.generation()
    const task = CampusCookies.clearBrowser()
    FduWebAuth.resetting = task
    try {
      await task
      if (generation !== CampusCookies.generation()) throw new FduAuthCancelledError('登录已取消，请重新登录')
      FduWebAuth.resetBrowser = false
      CampusCookies.resume()
    } finally {
      if (FduWebAuth.resetting === task) FduWebAuth.resetting = null
    }
  }

  static current(): FduWebAuthRequest | null {
    return FduWebAuth.active
  }

  static authenticate(challenge: FduAuthChallenge, studentId: string, password: string): Promise<string> {
    if ((!FduAuthPolicy.isIdUrl(challenge.loginUrl) &&
      !FduAuthPolicy.isServiceUrl(challenge.loginUrl, challenge.serviceUrl)) ||
      !FduAuthPolicy.isCampusUrl(challenge.serviceUrl)) {
      return Promise.reject(new Error('无法打开复旦身份验证页面，请重新登录'))
    }
    if (FduWebAuth.active !== null) {
      if (FduWebAuth.active.studentId === studentId &&
        FduWebAuth.active.challenge.serviceUrl === challenge.serviceUrl && FduWebAuth.pending !== null) return FduWebAuth.pending
      return Promise.reject(new Error('已有身份验证正在进行'))
    }
    const id: number = ++FduWebAuth.sequence
    FduWebAuth.active = new FduWebAuthRequest(id, challenge, studentId, password)
    const pending = new Promise<string>((resolve, reject) => {
      FduWebAuth.resolvePending = resolve
      FduWebAuth.rejectPending = reject
      try {
        router.pushUrl({ url: 'pages/FduAuthPage' }).catch(() => {
          FduWebAuth.cancel(id, '无法打开身份验证页面，请重试')
        })
      } catch (e) {
        FduWebAuth.cancel(id, '无法打开身份验证页面，请重试')
      }
    })
    // pushUrl may fail synchronously and release before Promise construction
    // returns; do not restore a released request with a stale pending handle.
    if (FduWebAuth.active?.id === id) FduWebAuth.pending = pending
    return pending
  }

  /** Run only after the Web controller is attached, before loading the login URL. */
  static async prepare(request: FduWebAuthRequest): Promise<void> {
    await FduWebAuth.prepareSession()
    if (FduWebAuth.active?.id !== request.id) throw new Error('身份验证已取消')
    for (const raw of request.challenge.idCookies) {
      if (FduWebAuth.active?.id !== request.id) throw new Error('身份验证已取消')
      await webview.WebCookieManager.configCookie(FduAuthPolicy.ID_ORIGIN + '/', raw, false, true)
    }
    if (FduWebAuth.active?.id !== request.id) throw new Error('身份验证已取消')
    CampusCookies.resume()
  }

  static complete(id: number, cookies: string): void {
    if (FduWebAuth.active?.id !== id) return
    if (cookies.trim().length === 0) {
      FduWebAuth.cancel(id, '验证页面没有返回登录会话，请重试')
      return
    }
    const resolve = FduWebAuth.resolvePending
    FduWebAuth.release()
    if (resolve !== null) resolve(cookies)
  }

  static cancel(id: number, message: string = '已取消身份验证'): void {
    if (FduWebAuth.active?.id !== id) return
    const reject = FduWebAuth.rejectPending
    FduWebAuth.release()
    if (reject !== null) reject(new FduAuthCancelledError(message) as Error)
  }

  static reset(): void {
    if (FduWebAuth.active !== null) FduWebAuth.cancel(FduWebAuth.active.id)
    FduWebAuth.resetBrowser = true
    CampusCookies.suspend()
  }

  private static release(): void {
    if (FduWebAuth.active !== null) {
      FduWebAuth.active.password = ''
      FduWebAuth.active.studentId = ''
      FduWebAuth.active.challenge.idCookies = []
    }
    FduWebAuth.active = null
    FduWebAuth.resolvePending = null
    FduWebAuth.rejectPending = null
    FduWebAuth.pending = null
  }
}
