import { uiMaterial } from '@kit.ArkUI'

/** The material object holds a visual style, not a frozen system strength.
 * Native hosts continue adapting their immersive light configuration. Refresh
 * JS objects only when a resource color mode or exposed capability changes. */
export function materialAppearanceKey(dark: boolean): string {
  const mode: string = dark ? 'dark' : 'light'
  try {
    const supported: boolean = uiMaterial.isImmersiveMaterialSupported()
    const info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo()
    return mode + ':' + String(supported) + ':' + String(info.state) + ':' + String(info.type)
  } catch (e) { return mode + ':unavailable' }
}

class MaterialCache {
  private static revision: number = -1
  private static regular: uiMaterial.ImmersiveMaterial | undefined = undefined
  private static regularInteractive: uiMaterial.ImmersiveMaterial | undefined = undefined
  private static floating: uiMaterial.ImmersiveMaterial | undefined = undefined
  private static floatingWithoutPoint: uiMaterial.ImmersiveMaterial | undefined = undefined
  private static cardFloating: uiMaterial.ImmersiveMaterial | undefined = undefined
  private static cardFloatingWithoutPoint: uiMaterial.ImmersiveMaterial | undefined = undefined

  static prepare(revision: number): void {
    if (MaterialCache.revision === revision) return
    MaterialCache.revision = revision
    MaterialCache.regular = undefined
    MaterialCache.regularInteractive = undefined
    MaterialCache.floating = undefined
    MaterialCache.floatingWithoutPoint = undefined
    MaterialCache.cardFloating = undefined
    MaterialCache.cardFloatingWithoutPoint = undefined
  }

  static regularMaterial(revision: number, interactive: boolean): uiMaterial.ImmersiveMaterial {
    MaterialCache.prepare(revision)
    if (interactive) {
      if (MaterialCache.regularInteractive === undefined) {
        MaterialCache.regularInteractive = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: $r('app.color.surface_tint'),
          applyShadow: true, interactive: true, lightEffect: {}
        })
      }
      return MaterialCache.regularInteractive
    }
    if (MaterialCache.regular === undefined) {
      MaterialCache.regular = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: $r('app.color.surface_tint'),
        applyShadow: true, interactive: false, lightEffect: null
      })
    }
    return MaterialCache.regular
  }

  static floatingMaterial(revision: number, pointFeedback: boolean, onCard: boolean): uiMaterial.ImmersiveMaterial {
    MaterialCache.prepare(revision)
    if (onCard) {
      if (pointFeedback) {
        if (MaterialCache.cardFloating === undefined) {
          MaterialCache.cardFloating = new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN, colorInvert: true,
            materialColor: $r('app.color.floating_card_tint'),
            applyShadow: true, interactive: true, lightEffect: {}
          })
        }
        return MaterialCache.cardFloating
      }
      if (MaterialCache.cardFloatingWithoutPoint === undefined) {
        MaterialCache.cardFloatingWithoutPoint = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN, colorInvert: true,
          materialColor: $r('app.color.floating_card_tint'),
          applyShadow: true, interactive: true, lightEffect: null
        })
      }
      return MaterialCache.cardFloatingWithoutPoint
    }
    if (pointFeedback) {
      if (MaterialCache.floating === undefined) {
        MaterialCache.floating = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN, colorInvert: true,
          applyShadow: true, interactive: true, lightEffect: {}
        })
      }
      return MaterialCache.floating
    }
    if (MaterialCache.floatingWithoutPoint === undefined) {
      MaterialCache.floatingWithoutPoint = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN, colorInvert: true,
        applyShadow: true, interactive: true, lightEffect: null
      })
    }
    return MaterialCache.floatingWithoutPoint
  }
}

/** A visible tint is independent of the device's system-managed material level. */
export function adaptiveMaterial(revision: number = 0, interactive: boolean = false): uiMaterial.Material | undefined {
  try {
    if (uiMaterial.isImmersiveMaterialSupported() &&
      uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE) {
      // Passive content cards and page backgrounds must not keep a point light
      // tracking the finger after the containing feed starts to scroll.
      return MaterialCache.regularMaterial(revision, interactive)
    }
    return uiMaterial.Material.empty
  } catch (e) {
    // Every caller sets a readable background BEFORE applying systemMaterial.
    return undefined
  }
}

/** Use on a supported host: native floating TabBar, navigation controls, or an
 * SDK 26 container with the public systemMaterial attribute.
 * Thickness is a visual style, not the device's quality level. Leave the latter
 * to the system, and do not cover the sampled content with another color layer.
 */
export function floatingMaterial(revision: number = 0, pointFeedback: boolean = true, onCard: boolean = false): uiMaterial.ImmersiveMaterial | undefined {
  try {
    if (uiMaterial.isImmersiveMaterialSupported() &&
      uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE) {
      // Reuse the same native object through the press. Only a boundary crossing
      // changes its point-light variant; pressure and system quality stay native.
      return MaterialCache.floatingMaterial(revision, pointFeedback, onCard)
    }
    return undefined
  } catch (e) { return undefined }
}

/** Generic container surfaces need the entry module's configured material mode
 * to be active. Before the window acknowledges it (and in feature-only QA
 * windows), retain a visible backing rather than exposing a transparent host.
 * This does not change the user's system light strength. */
export function containerFloatingMaterial(revision: number = 0, pointFeedback: boolean = true): uiMaterial.ImmersiveMaterial | undefined {
  try {
    if (uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.ENABLE) return undefined
    return floatingMaterial(revision, pointFeedback)
  } catch (e) { return undefined }
}

export function nativeFloatingBackground(revision: number = 0, fallback: ResourceColor | undefined = undefined): ResourceColor {
  // backgroundColor is drawn ABOVE systemMaterial, regardless of modifier order.
  // Do not let the 85%-opaque compatibility fallback hide native transmission.
  try {
    if (uiMaterial.isImmersiveMaterialSupported() &&
      uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE) return Color.Transparent
  } catch (e) {}
  return fallback ?? $r('app.color.floating_fallback')
}

/** Controls outside a native material host must keep their readable surface. */
export function floatingBackground(revision: number = 0): ResourceColor {
  return $r('app.color.floating_fallback')
}
