import { BusinessError } from '@kit.BasicServicesKit'
import { FduAuthChallenge, FduAuthPolicy } from '../model/FduAuth'
import { CampusCookies } from './CampusCookies'

export class FduAuthCancelledError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'FduAuthCancelledError'
  }
}

export class FduAuthPreparationError extends Error {
  diagnostics: string

  constructor(message: string, diagnostics: string) {
    super(message)
    this.name = 'FduAuthPreparationError'
    this.diagnostics = diagnostics
  }
}

/** Credentials stay in memory, never in route parameters, storage, or log messages. */
export class FduWebAuthRequest {
  id: number
  challenge: FduAuthChallenge
  studentId: string
  password: string
  preparation: Promise<void> | null = null
  preparationPhase: string = 'not-started'
  preparationStarted: number = 0
  cookieCount: number = 0
  completedCookies: number = 0

  constructor(id: number, challenge: FduAuthChallenge, studentId: string, password: string) {
    this.id = id
    this.challenge = challenge
    this.studentId = studentId
    this.password = password
  }
}

/** One continuation at a time; FduRepository serializes service authentication. */
export class FduWebAuth {
  private static readonly PREPARE_TIMEOUT_MS: number = 30000
  private static sequence: number = 0
  private static active: FduWebAuthRequest | null = null
  private static resolvePending: ((cookies: string) => void) | null = null
  private static rejectPending: ((error: Error) => void) | null = null
  private static resetBrowser: boolean = false
  private static pending: Promise<string> | null = null
  private static resetting: Promise<void> | null = null
  private static resetPhase: string = 'not-started'
  private static resetStarted: number = 0
  private static present: ((request: FduWebAuthRequest) => Promise<void>) | null = null
  private static dismiss: ((requestId: number) => void) | null = null

  /** Registered by the live window. Passive repository reads never open UI. */
  static bindPresentation(present: (request: FduWebAuthRequest) => Promise<void>, dismiss: (requestId: number) => void): void {
    FduWebAuth.present = present
    FduWebAuth.dismiss = dismiss
  }

  static unbindPresentation(): void {
    if (FduWebAuth.active !== null) FduWebAuth.cancel(FduWebAuth.active.id)
    FduWebAuth.present = null
    FduWebAuth.dismiss = null
  }

  /** Clear the previous account before HTTP authentication too. Clearing only
   * when the later Web route attaches would erase a newly established CAS SSO. */
  static prepareSession(): Promise<void> {
    if (FduWebAuth.resetting !== null) return FduWebAuth.waitPreparation(FduWebAuth.resetting,
      () => FduWebAuth.resetDiagnostics())
    if (!FduWebAuth.resetBrowser) { CampusCookies.resume(); return Promise.resolve() }
    FduWebAuth.resetStarted = Date.now()
    FduWebAuth.resetPhase = 'waiting-cookie-writes'
    const task = FduWebAuth.resetSession(CampusCookies.generation())
    FduWebAuth.resetting = task
    task.then(() => { if (FduWebAuth.resetting === task) FduWebAuth.resetting = null },
      () => { if (FduWebAuth.resetting === task) FduWebAuth.resetting = null })
    return FduWebAuth.waitPreparation(task, () => FduWebAuth.resetDiagnostics())
  }

  private static async resetSession(generation: number): Promise<void> {
    await CampusCookies.clearBrowser(() => { FduWebAuth.resetPhase = 'clearing-browser' })
    if (generation !== CampusCookies.generation()) throw new FduAuthCancelledError('登录已取消，请重新登录')
    FduWebAuth.resetBrowser = false
    FduWebAuth.resetPhase = 'ready'
    CampusCookies.resume()
  }

  private static resetDiagnostics(): string {
    return 'webAuthPreparation; phase=' + FduWebAuth.resetPhase +
      '; elapsedMs=' + String(Math.max(0, Date.now() - FduWebAuth.resetStarted))
  }

  static preparationDiagnostics(requestId: number): string {
    const request = FduWebAuth.active
    if (request === null || request.id !== requestId) return 'webAuthPreparation; phase=inactive'
    return 'webAuthPreparation; phase=' + request.preparationPhase + '; cookieCount=' + String(request.cookieCount) +
      '; completedCookies=' + String(request.completedCookies) +
      '; elapsedMs=' + String(request.preparationStarted ? Math.max(0, Date.now() - request.preparationStarted) : 0) +
      (request.preparationPhase === 'preparing-session' ? '\n' + FduWebAuth.resetDiagnostics() : '')
  }

  /** Bound the caller's wait only. The native operation stays in its serial
   * chain until settlement, so a late write cannot overtake logout clearing. */
  private static waitPreparation(task: Promise<void>, diagnostics: () => string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const timer: number = setTimeout(() => {
        reject(new FduAuthPreparationError('身份验证初始化超时，请重试。', diagnostics() + '; timeout=true'))
      }, FduWebAuth.PREPARE_TIMEOUT_MS)
      task.then(() => { clearTimeout(timer); resolve() }, (error: Error) => {
        clearTimeout(timer)
        if (error instanceof FduAuthCancelledError || error instanceof FduAuthPreparationError) { reject(error); return }
        const code = (error as BusinessError).code
        reject(new FduAuthPreparationError('身份验证初始化失败，请重试。', diagnostics() +
          '; nativeCode=' + String(typeof code === 'number' && Number.isFinite(code) ? code : 0)))
      })
    })
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
    const request = FduWebAuth.active
    const pending = new Promise<string>((resolve, reject) => {
      FduWebAuth.resolvePending = resolve
      FduWebAuth.rejectPending = reject
      try {
        if (FduWebAuth.present === null) throw new Error('Authentication window is not ready')
        FduWebAuth.present(request).catch(() => {
          FduWebAuth.cancel(id, '无法打开身份验证页面，请重试')
        })
      } catch (e) {
        FduWebAuth.cancel(id, '无法打开身份验证页面，请重试')
      }
    })
    // Presentation may fail synchronously and release before Promise construction
    // returns; do not restore a released request with a stale pending handle.
    if (FduWebAuth.active?.id === id) FduWebAuth.pending = pending
    return pending
  }

  /** Run only after the Web controller is attached, before loading the login URL. */
  static prepare(request: FduWebAuthRequest): Promise<void> {
    if (request.preparation === null) {
      request.preparationStarted = Date.now()
      request.preparationPhase = 'preparing-session'
      request.cookieCount = request.challenge.idCookies.length
      request.completedCookies = 0
      const task = FduWebAuth.prepareOnce(request)
      request.preparation = task
      task.then(() => {}, () => { if (request.preparation === task) request.preparation = null })
    }
    return FduWebAuth.waitPreparation(request.preparation, () => FduWebAuth.preparationDiagnostics(request.id))
  }

  private static async prepareOnce(request: FduWebAuthRequest): Promise<void> {
    await FduWebAuth.prepareSession()
    if (FduWebAuth.active?.id !== request.id) throw new FduAuthCancelledError('身份验证已取消')
    request.preparationPhase = 'preparing-cookies'
    const epoch = CampusCookies.generation()
    const records: string[] = request.challenge.idCookies.slice()
    try {
      await CampusCookies.importVerification(records, epoch, () => FduWebAuth.active?.id === request.id,
        (count: number) => { request.completedCookies = count })
    } finally {
      records.fill('')
    }
    if (FduWebAuth.active?.id !== request.id || epoch !== CampusCookies.generation()) {
      throw new FduAuthCancelledError('身份验证已取消')
    }
    request.preparationPhase = 'ready'
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
    const requestId: number = FduWebAuth.active?.id ?? 0
    if (FduWebAuth.active !== null) {
      FduWebAuth.active.password = ''
      FduWebAuth.active.studentId = ''
      FduWebAuth.active.challenge.idCookies = []
    }
    FduWebAuth.active = null
    FduWebAuth.resolvePending = null
    FduWebAuth.rejectPending = null
    FduWebAuth.pending = null
    if (requestId !== 0 && FduWebAuth.dismiss !== null) FduWebAuth.dismiss(requestId)
  }
}
