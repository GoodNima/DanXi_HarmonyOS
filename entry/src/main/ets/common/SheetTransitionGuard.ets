/** A reopen can race the old native exit and its two-way show value.
 * Commit a queued open after that exit; outside, close, back and drag can
 * interrupt entrance immediately through the native dismissal animation.
 */
import { UIContext } from '@kit.ArkUI'

export class SheetTransitionGuard {
  private visible: boolean = false
  private revision: number = 0
  private closing: boolean = false
  private pendingOpen: (() => void) | undefined = undefined
  private pendingContext: (() => UIContext) | undefined = undefined

  open(action: () => void, context: () => UIContext): void {
    if (!this.closing) { action(); return }
    // A native sheet/menu still owns its two-way show value during exit. Keep
    // one reopen request and commit it after that native exit has completed.
    this.pendingOpen = action
    this.pendingContext = context
  }

  /** API-managed sheets request close before the native callback is delivered. */
  beginClose(): void { this.closing = true }

  private lifecycle(visible: boolean, options: BindOptions): void {
    if (visible !== this.visible) {
      this.visible = visible
      this.revision++
    }
    const revision: number = this.revision
    const onAppear: (() => void) | undefined = options.onAppear
    const onWillDisappear: (() => void) | undefined = options.onWillDisappear
    const onDisappear: (() => void) | undefined = options.onDisappear
    options.onAppear = () => {
      if (!this.visible || this.closing || revision !== this.revision) return
      if (onAppear !== undefined) onAppear()
    }
    options.onWillDisappear = () => {
      if (revision !== this.revision && !(!this.visible && revision + 1 === this.revision)) return
      this.closing = true
      if (onWillDisappear !== undefined) onWillDisappear()
    }
    options.onDisappear = () => {
      if (revision !== this.revision && !(!this.visible && revision + 1 === this.revision)) return
      if (onDisappear !== undefined) onDisappear()
      this.closing = false
      this.visible = false
      this.revision++
      const reopen: (() => void) | undefined = this.pendingOpen
      const context: (() => UIContext) | undefined = this.pendingContext
      this.pendingOpen = undefined
      this.pendingContext = undefined
      if (reopen !== undefined && context !== undefined) {
        context().postFrameCallback({ onFrame: () => { reopen() }, onIdle: () => {} })
      }
    }
  }

  menuOptions(visible: boolean, options: MenuOptions): MenuOptions {
    this.lifecycle(visible, options)
    return options
  }

  options(visible: boolean, options: SheetOptions): SheetOptions {
    this.lifecycle(visible, options)
    const revision: number = this.revision
    const onWillDismiss: ((action: DismissSheetAction) => void) | undefined = options.onWillDismiss
    // Each bindSheet evaluation supplies a fresh, typed options object.
    options.onWillDismiss = (action: DismissSheetAction) => {
      if (this.closing || (revision !== this.revision && !(!this.visible && revision + 1 === this.revision))) return
      if (revision === this.revision) this.closing = true
      if (onWillDismiss !== undefined) onWillDismiss(action)
      else action.dismiss()
    }
    return options
  }
}
