/**
 * Theme configuration for DanXi HarmonyOS app.
 * Immersive light sense (沉浸光感) design system.
 */

// ── Color Palette ──────────────────────────────────────
export class ThemeColors {
  // Brand
  static readonly primary: ResourceColor = $r('app.color.theme_primary')
  static readonly primaryLight: ResourceColor = $r('app.color.theme_primary_light')
  static readonly primaryDark: ResourceColor = $r('app.color.theme_primary_dark')
  static readonly accent: ResourceColor = $r('app.color.theme_accent')

  // Backgrounds – light, airy gradient stops
  static readonly bgStart: ResourceColor = $r('app.color.theme_bg_start')
  static readonly bgEnd: ResourceColor = $r('app.color.theme_bg_end')
  static readonly cardBg: ResourceColor = $r('app.color.theme_card_bg')
  static readonly cardGlass: ResourceColor = $r('app.color.theme_card_glass')

  // Text
  static readonly textPrimary: ResourceColor = $r('app.color.theme_text_primary')
  static readonly textSecondary: ResourceColor = $r('app.color.theme_text_secondary')
  static readonly textHint: ResourceColor = $r('app.color.theme_text_hint')

  // Functional
  static readonly divider: ResourceColor = $r('app.color.theme_divider')
  static readonly success: ResourceColor = $r('app.color.theme_success')
  static readonly warning: ResourceColor = $r('app.color.theme_warning')
  static readonly error: ResourceColor = $r('app.color.theme_error')
  static readonly info: ResourceColor = $r('app.color.theme_info')

  // Tab bar
  static readonly tabBarBg: ResourceColor = $r('app.color.theme_tab_bar_bg')
  static readonly tabActive: ResourceColor = $r('app.color.theme_tab_active')
  static readonly tabInactive: ResourceColor = $r('app.color.theme_tab_inactive')
}

// ── Dimensions ─────────────────────────────────────────
export class ThemeDimens {
  static readonly cardGutter: number = 12
  static readonly cardInset: number = 16
  static readonly compactCardVerticalInset: number = 8
  static readonly compactCardTopInset: number = 4
  static readonly cardContentGap: number = 6
  static readonly paddingSmall: number = 8
  static readonly paddingMedium: number = 16
  static readonly paddingLarge: number = 24
  static readonly radiusSmall: number = 6
  static readonly radiusMedium: number = 12
  static readonly radiusLarge: number = 20
  static readonly textSizeSmall: number = 12
  static readonly textSizeBody: number = 14
  static readonly textSizeTitle: number = 16
  static readonly textSizeLarge: number = 20
  static readonly textSizeXLarge: number = 24
}
