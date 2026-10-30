import { UIContext, ComponentContent } from '@kit.ArkUI'
import { FduAuthContent } from '../pages/FduAuthPage'
import { FduAuthPresentation } from './FduAuthPresentation'
import { FduWebAuth, FduWebAuthRequest } from './FduWebAuth'
import { SheetTransitionGuard } from './SheetTransitionGuard'
import { adaptiveMaterial, nativeFloatingBackground } from './AdaptiveMaterial'

@Builder
function buildVerification(params: FduAuthPresentation) {
  FduAuthContent({ presentation: params })
}

/** Keep one native content node alive until its own dismissal has completed. */
class FduAuthSheetSession {
  readonly id: number
  readonly context: UIContext
  readonly params: FduAuthPresentation = new FduAuthPresentation()
  readonly transition: SheetTransitionGuard = new SheetTransitionGuard()
  content: ComponentContent<FduAuthPresentation> | null = null
  active: boolean = true
  closing: boolean = false

  constructor(context: UIContext, request: FduWebAuthRequest) {
    this.id = request.id
    this.context = context
    this.params.requestId = request.id
    this.params.close = () => { this.close() }
    this.params.isCurrent = (): boolean => this.active && FduWebAuth.current()?.id === this.id
    this.params.refreshAppearance = () => { this.refreshAppearance() }
    this.content = new ComponentContent(context, wrapBuilder(buildVerification), this.params)
  }

  options(): SheetOptions {
    const revision: number = AppStorage.get<number>('ui_material_revision') ?? 0
    return this.transition.options(true, { height: '94%', preferType: SheetType.BOTTOM, showClose: false, dragBar: true,
      backgroundColor: nativeFloatingBackground(revision), systemMaterial: adaptiveMaterial(revision),
      onWillDismiss: (action: DismissSheetAction) => { this.deactivate(); action.dismiss() },
      onWillDisappear: () => { this.deactivate() }, onDisappear: () => { this.release() } })
  }

  private deactivate(): void {
    this.closing = true
    this.active = false
    this.params.deactivate()
  }

  refreshAppearance(): void {
    if (!this.active || this.content === null) return
    this.content.updateConfiguration()
    this.context.updateBindSheet(this.content, this.options(), true).catch(() => {})
  }

  close(): void {
    if (this.closing || this.content === null) return
    this.deactivate()
    this.transition.beginClose()
    try {
      this.context.closeBindSheet(this.content).catch(() => { this.release('身份验证页面关闭失败，请重试') })
    } catch (error) { this.release('身份验证页面关闭失败，请重试') }
  }

  release(failureMessage: string = ''): void {
    this.deactivate()
    const content = this.content
    this.content = null
    FduAuthSheet.released(this)
    if (failureMessage) FduWebAuth.cancel(this.id, failureMessage)
    // Component disappearance can precede native animation completion. Only
    // this sheet's onDisappear may publish the Web result to its caller.
    this.params.settle()
    if (content !== null) content.dispose()
    if (FduWebAuth.current()?.id === this.id) FduWebAuth.cancel(this.id)
  }
}

export class FduAuthSheet {
  private static context: UIContext | null = null
  private static session: FduAuthSheetSession | null = null

  static attach(context: UIContext): void {
    FduAuthSheet.context = context
    FduWebAuth.bindPresentation((request: FduWebAuthRequest): Promise<void> => FduAuthSheet.show(request),
      (id: number): void => { if (FduAuthSheet.session?.id === id) FduAuthSheet.session.close() })
  }

  static detach(): void {
    FduWebAuth.unbindPresentation()
    const session = FduAuthSheet.session
    if (session !== null) session.release()
    FduAuthSheet.context = null
  }

  static released(session: FduAuthSheetSession): void {
    if (FduAuthSheet.session === session) FduAuthSheet.session = null
  }

  private static show(request: FduWebAuthRequest): Promise<void> {
    const context = FduAuthSheet.context
    if (context === null || FduWebAuth.current()?.id !== request.id) {
      return Promise.reject(new Error('身份验证窗口已关闭，请重试'))
    }
    const current = FduAuthSheet.session
    if (current !== null) {
      if (current.id === request.id && current.active) return Promise.resolve()
      if (current.closing) {
        return new Promise<void>((resolve, reject) => {
          current.transition.open(() => { FduAuthSheet.show(request).then(resolve, reject) }, () => context)
        })
      }
      return Promise.reject(new Error('已有身份验证正在进行'))
    }
    try {
      const session = new FduAuthSheetSession(context, request)
      FduAuthSheet.session = session
      if (session.content === null) { session.release('无法打开身份验证页面，请重试'); return Promise.reject(new Error('无法打开身份验证页面，请重试')) }
      return context.openBindSheet(session.content, session.options()).catch((error: Error) => {
        session.release('无法打开身份验证页面，请重试')
        throw error
      })
    } catch (error) {
      if (FduAuthSheet.session?.id === request.id) FduAuthSheet.session.release('无法打开身份验证页面，请重试')
      return Promise.reject(error as Error)
    }
  }
}
