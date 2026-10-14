/** Native fast scrolling suppresses clicks. Settle at the committed position
 * on a fresh single-pointer Down so the same native tap can be accepted.
 * Do not synthesize clicks, consume events, or replace the platform fling. */
export function settleScrollTouch(scroller: Scroller, event: TouchEvent): void {
  if (event.type !== TouchType.Down || event.touches.length !== 1) return
  try {
    const offset: OffsetResult = scroller.currentOffset()
    if (Number.isFinite(offset.xOffset) && Number.isFinite(offset.yOffset)) {
      scroller.scrollTo({ xOffset: offset.xOffset, yOffset: offset.yOffset, animation: false })
    }
  } catch (e) {}
}
