import { ColorMetrics } from '@kit.ArkUI'

interface ForumAuthorTone {
  family: string
  primary: Resource
  overlay?: Resource
  mix: number
}

class ForumAuthorColorCache {
  resourceKey: string = ''
  color: string = ''
}

/** Shared iOS/Android family order; HarmonyOS resources and native blending. */
export class ForumAuthorPalette {
  private static readonly TONES: ForumAuthorTone[] = [
    { family: 'red', primary: $r('sys.color.ohos_id_color_warning'), mix: 0 },
    { family: 'pink', primary: $r('sys.color.ohos_id_color_palette7'), mix: 0 },
    { family: 'purple', primary: $r('sys.color.ohos_id_color_palette6'), overlay: $r('sys.color.ohos_id_color_palette7'), mix: 0.22 },
    { family: 'deep-purple', primary: $r('sys.color.ohos_id_color_palette6'), overlay: $r('sys.color.ohos_id_color_palette1'), mix: 0.22 },
    { family: 'indigo', primary: $r('sys.color.ohos_id_color_palette1'), mix: 0 },
    { family: 'blue', primary: $r('sys.color.ohos_id_color_emphasize'), mix: 0 },
    { family: 'light-blue', primary: $r('sys.color.ohos_id_color_palette2'), mix: 0 },
    { family: 'cyan', primary: $r('sys.color.ohos_id_color_palette2'), overlay: $r('sys.color.ohos_id_color_palette3'), mix: 0.65 },
    { family: 'teal', primary: $r('sys.color.ohos_id_color_palette3'), overlay: $r('sys.color.ohos_id_color_palette4'), mix: 0.20 },
    { family: 'green', primary: $r('sys.color.ohos_id_color_palette4'), mix: 0 },
    { family: 'light-green', primary: $r('sys.color.ohos_id_color_palette4'), overlay: $r('sys.color.ohos_id_color_palette5'), mix: 0.50 },
    { family: 'lime', primary: $r('sys.color.ohos_id_color_palette5'), mix: 0 },
    { family: 'yellow', primary: $r('sys.color.ohos_id_color_palette11'), mix: 0 },
    { family: 'amber', primary: $r('sys.color.ohos_id_color_palette10'), mix: 0 },
    { family: 'orange', primary: $r('sys.color.ohos_id_color_palette9'), mix: 0 },
    { family: 'deep-orange', primary: $r('sys.color.ohos_id_color_palette9'), overlay: $r('sys.color.ohos_id_color_warning'), mix: 0.28 },
    { family: 'brown', primary: $r('sys.color.ohos_id_color_palette9'), overlay: $r('app.color.forum_author_neutral'), mix: 0.64 },
    { family: 'blue-grey', primary: $r('sys.color.ohos_id_color_palette2'), overlay: $r('app.color.forum_author_neutral'), mix: 0.74 },
    { family: 'grey', primary: $r('app.color.forum_author_neutral'), mix: 0 }
  ]
  private static readonly SURFACES: Resource[] = [$r('app.color.surface_fallback'), $r('app.color.quote_surface')]
  private static readonly resources: Map<Resource, ColorMetrics> = new Map<Resource, ColorMetrics>()
  // At most 19 families per appearance, never one retained entry per author.
  private static readonly colors: Map<number, ForumAuthorColorCache> = new Map<number, ForumAuthorColorCache>()

  private static index(name: string): number {
    if (!name || name.startsWith('*')) return 0
    // The SDK has no author-name hashing API. Keep an order-sensitive app hash.
    let hash: number = 2166136261
    for (let i: number = 0; i < name.length; i++) hash = Math.imul(hash ^ name.charCodeAt(i), 16777619)
    hash ^= hash >>> 16
    return (hash >>> 0) % ForumAuthorPalette.TONES.length
  }

  static family(name: string): string { return ForumAuthorPalette.TONES[ForumAuthorPalette.index(name)].family }

  private static nativeColor(resource: Resource): ColorMetrics {
    const cached: ColorMetrics | undefined = ForumAuthorPalette.resources.get(resource)
    if (cached !== undefined) return cached
    const color: ColorMetrics = ColorMetrics.resourceColor(resource)
    // API 26 keeps resolved resources synchronized with native color mode.
    // Without that capability, resolve afresh rather than retain a stale value.
    const refreshing: ColorMetrics | undefined = color.autoRefresh?.(true)
    if (refreshing !== undefined) ForumAuthorPalette.resources.set(resource, refreshing)
    return refreshing ?? color
  }

  private static hex(color: ColorMetrics): string {
    return '#' + Math.round(color.red).toString(16).padStart(2, '0') +
      Math.round(color.green).toString(16).padStart(2, '0') + Math.round(color.blue).toString(16).padStart(2, '0')
  }

  private static linear(value: number): number {
    const channel: number = value / 255
    return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  private static luminance(color: ColorMetrics): number {
    return ForumAuthorPalette.linear(color.red) * 0.2126 + ForumAuthorPalette.linear(color.green) * 0.7152 +
      ForumAuthorPalette.linear(color.blue) * 0.0722
  }

  private static readable(color: ColorMetrics, backgrounds: number[]): boolean {
    const light: number = ForumAuthorPalette.luminance(color)
    return backgrounds.every((background: number) => (Math.max(light, background) + 0.05) /
      (Math.min(light, background) + 0.05) >= 4.5)
  }

  static color(name: string, dark: boolean): string {
    const index: number = ForumAuthorPalette.index(name)
    const tone: ForumAuthorTone = ForumAuthorPalette.TONES[index]
    const primary: ColorMetrics = ForumAuthorPalette.nativeColor(tone.primary)
    const overlay: ColorMetrics | undefined = tone.overlay === undefined ? undefined : ForumAuthorPalette.nativeColor(tone.overlay)
    const surfaces: ColorMetrics[] = ForumAuthorPalette.SURFACES.map((resource: Resource) => ForumAuthorPalette.nativeColor(resource))
    // One native value read per resource on the hot path, rather than three channel reads.
    const resourceKey: string = primary.color + (overlay === undefined ? '' : overlay.color) +
      surfaces.map((surface: ColorMetrics) => surface.color).join('')
    const slot: number = index + (dark ? ForumAuthorPalette.TONES.length : 0)
    const cached: ForumAuthorColorCache | undefined = ForumAuthorPalette.colors.get(slot)
    if (cached !== undefined && cached.resourceKey === resourceKey) return cached.color
    let seed: ColorMetrics = ColorMetrics.rgba(primary.red, primary.green, primary.blue)
    if (overlay !== undefined) seed = seed.blendColor(ColorMetrics.rgba(overlay.red, overlay.green, overlay.blue, tone.mix))
    const backgrounds: number[] = surfaces.map((surface: ColorMetrics) => ForumAuthorPalette.luminance(surface))
    let readable: ColorMetrics = seed
    if (!ForumAuthorPalette.readable(seed, backgrounds)) {
      // Resolve against the actual native background, including a theme change in flight.
      const endpoint: number = backgrounds[0] > 0.5 ? 0 : 255
      let low: number = 0
      let high: number = 1
      readable = ColorMetrics.rgba(endpoint, endpoint, endpoint)
      // Minimum necessary shade adjustment, using the system's alpha compositing.
      for (let step: number = 0; step < 9; step++) {
        const alpha: number = (low + high) / 2
        const candidate: ColorMetrics = seed.blendColor(ColorMetrics.rgba(endpoint, endpoint, endpoint, alpha))
        if (ForumAuthorPalette.readable(candidate, backgrounds)) { high = alpha; readable = candidate }
        else low = alpha
      }
    }
    const result = new ForumAuthorColorCache()
    result.resourceKey = resourceKey
    result.color = ForumAuthorPalette.hex(readable).toUpperCase()
    ForumAuthorPalette.colors.set(slot, result)
    return result.color
  }
}
