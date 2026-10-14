/** Fade the sampled backdrop gradually through the lower header into the feed.
 * A smoothstep profile has no sudden slope at either end. This is an alpha
 * mask over a single live sample, not another painted or blurred surface. */
export class TopFadeMetrics {
  static readonly TRAILING_EDGE: number = 16
  static readonly BLUR_RADIUS: number = 18
  static header(extent: number): number { return Number.isFinite(extent) && extent > 0 ? Math.max(40, extent) : 120 }
  static trailing(edge: number = TopFadeMetrics.TRAILING_EDGE): number {
    return Number.isFinite(edge) && edge > 0 ? Math.max(16, edge) : TopFadeMetrics.TRAILING_EDGE
  }
  static height(extent: number, trailingEdge: number = TopFadeMetrics.TRAILING_EDGE): number {
    return TopFadeMetrics.header(extent) + TopFadeMetrics.trailing(trailingEdge)
  }
  static start(extent: number, trailingEdge: number = TopFadeMetrics.TRAILING_EDGE): number {
    return TopFadeMetrics.header(extent) * 0.625 / TopFadeMetrics.height(extent, trailingEdge)
  }
  static opacity(progress: number): number {
    const value: number = Math.min(1, Math.max(0, progress))
    return 1 - value * value * (3 - 2 * value)
  }
  static colors(extent: number, trailingEdge: number = TopFadeMetrics.TRAILING_EDGE): [ResourceColor, number][] {
    const start: number = TopFadeMetrics.start(extent, trailingEdge)
    const colors: [ResourceColor, number][] = [['#FFFFFFFF', 0], ['#FFFFFFFF', start]]
    // Preserve the upper controls and greeting before easing through the lower
    // header. Eight short segments prevent a visible final sampling edge.
    for (let index: number = 1; index <= 8; index++) {
      const progress: number = index / 8
      const alpha: string = Math.round(255 * TopFadeMetrics.opacity(progress)).toString(16).padStart(2, '0')
      colors.push(['#' + alpha + 'FFFFFF', start + (1 - start) * progress])
    }
    return colors
  }
}
