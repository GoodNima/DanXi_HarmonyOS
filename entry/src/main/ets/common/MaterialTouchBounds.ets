import { FrameNode, UIContext } from '@kit.ArkUI'

export interface MaterialBounds {
  x: number
  y: number
  width: number
  height: number
  radius: number
}

/** All values are in the material owner's local vp coordinate system. */
export function containsMaterialPoint(bounds: MaterialBounds, x: number, y: number): boolean {
  if (!Number.isFinite(x) || !Number.isFinite(y) || bounds.width <= 0 || bounds.height <= 0) return false
  const localX: number = x - bounds.x
  const localY: number = y - bounds.y
  if (localX < 0 || localY < 0 || localX > bounds.width || localY > bounds.height) return false
  const radius: number = Math.min(Math.max(0, bounds.radius), bounds.width / 2, bounds.height / 2)
  const centerX: number = Math.max(radius, Math.min(bounds.width - radius, localX))
  const centerY: number = Math.max(radius, Math.min(bounds.height - radius, localY))
  return (localX - centerX) * (localX - centerX) + (localY - centerY) * (localY - centerY) <= radius * radius
}

/** A move outside cancels just the point-light feedback for this press. It must
 * not reappear when the same finger moves back or when a second finger lands.
 * The native host still owns clicks, scrolling, selection and pressure.
 */
export class MaterialTouchGuard {
  private pointerId: number = -1
  private canceled: boolean = false
  private feedback: boolean = true

  down(id: number, inside: boolean): boolean {
    if (this.pointerId >= 0) return this.feedback
    this.pointerId = id
    this.canceled = !inside
    this.feedback = inside
    return this.feedback
  }

  move(id: number, inside: boolean): boolean {
    if (this.pointerId !== id) return this.feedback
    if (!inside) this.canceled = true
    this.feedback = !this.canceled
    return this.feedback
  }

  up(id: number): boolean {
    if (this.pointerId !== id) return this.feedback
    this.pointerId = -1
    // Normal releases retain native fade-out. An escaped press stays cleared
    // until a new Down, so its last native point cannot flash back on release.
    this.feedback = !this.canceled
    return this.feedback
  }

  cancel(): boolean {
    this.pointerId = -1
    this.canceled = true
    this.feedback = false
    return false
  }
}

/** Read the actual native floating TabBar, without estimating breakpoint widths
 * or mixing a touch's local coordinates with window/screen safe-area offsets.
 * Never descend into page contents: they may contain their own floating bars.
 */
export function nativeTabBarBounds(context: UIContext, id: string): MaterialBounds | null {
  try {
    const tabs: FrameNode | null = context.getFrameNodeById(id)
    if (tabs === null || tabs.getUniqueId() <= 0) return null
    let child: FrameNode | null = tabs.getFirstChild()
    while (child !== null) {
      if (child.getUniqueId() > 0 && child.getNodeType() === 'TabBar') {
        const size = child.getMeasuredSize()
        const position = child.getPositionToParent()
        const width: number = context.px2vp(size.width)
        const height: number = context.px2vp(size.height)
        const x: number = Number(position.x)
        const y: number = Number(position.y)
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) ||
          !Number.isFinite(height) || width <= 0 || height <= 0) return null
        return { x: x, y: y, width: width,
          height: height, radius: height / 2 }
      }
      child = child.getNextSibling()
    }
  } catch (e) {}
  return null
}
