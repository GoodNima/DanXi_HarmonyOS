import { router } from '@kit.ArkUI'
import { ImageOpening, ImageReturnTarget } from './RouteParams'
import { ForumImage } from '../model/ForumImage'

/** Source image IDs belong to a route, never to a global page-animation lease. */
export class ForumImageTransition {
  private static sequence: number = 0
  private static targets: Map<string, ImageReturnTarget> = new Map()
  private static sourceInsets: Map<number, number> = new Map()
  /** Only the exact source route stays still while its image is presented.
   * Its status-bar inset must also survive the gallery hiding the system bar. */
  static beginSource(index: number, topPx: number): void { ForumImageTransition.sourceInsets.set(index, topPx) }
  static holdsSource(index: number): boolean { return ForumImageTransition.sourceInsets.has(index) }
  static sourceInset(index: number, current: number): number { return ForumImageTransition.sourceInsets.get(index) ?? current }
  static finishSource(index: number): void { ForumImageTransition.sourceInsets.delete(index) }
  static nextId(): string { return 'forum-image-' + (++ForumImageTransition.sequence) }
  static remember(source: string, opening: ImageOpening): void {
    const key: string = String(router.getState().index) + ':' + ForumImage.original(source)
    ForumImageTransition.targets.set(key, new ImageReturnTarget(ForumImage.original(source), opening))
    // Retain decoded metadata only; do not keep images or whole pages alive.
    if (ForumImageTransition.targets.size > 96) {
      const oldest: string | undefined = ForumImageTransition.targets.keys().next().value
      if (oldest !== undefined) ForumImageTransition.targets.delete(oldest)
    }
  }
  static forget(id: string): void {
    ForumImageTransition.targets.forEach((target: ImageReturnTarget, key: string) => {
      if (target.opening.id === id) ForumImageTransition.targets.delete(key)
    })
  }
  static forGallery(sources: string[]): ImageReturnTarget[] {
    const result: ImageReturnTarget[] = []
    const scope: string = String(router.getState().index) + ':'
    for (const source of sources) {
      const target: ImageReturnTarget | undefined = ForumImageTransition.targets.get(scope + ForumImage.original(source))
      if (target !== undefined) result.push(target)
    }
    return result
  }
}

/** The route's system back action and its floating button share one close. */
export class ForumImageController {
  private action: (() => void) | undefined = undefined
  private enteredAction: (() => void) | undefined = undefined
  private progressAction: ((opacity: number) => void) | undefined = undefined
  bind(action: () => void, enteredAction: () => void, progressAction?: (opacity: number) => void): void {
    this.action = action; this.enteredAction = enteredAction; this.progressAction = progressAction
  }
  release(): void { this.action = undefined; this.enteredAction = undefined; this.progressAction = undefined }
  transition(opacity: number): void { this.progressAction?.(opacity) }
  entered(): void { this.enteredAction?.() }
  back(): boolean {
    if (this.action === undefined) return false
    this.action()
    return true
  }
}
