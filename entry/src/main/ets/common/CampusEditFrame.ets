import { FrameCallback } from '@kit.ArkUI'

/** Coalesce pointer moves and edge scrolling into the next native UI frame. */
export class CampusEditFrame extends FrameCallback {
  private action: () => void
  constructor(action: () => void) { super(); this.action = action }
  onFrame(_time: number): void { this.action() }
}
