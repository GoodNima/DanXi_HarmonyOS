import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { resourceManager } from '@kit.LocalizationKit'
import { window } from '@kit.ArkUI'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { Constant } from './Constant'
import { materialAppearanceKey } from './AdaptiveMaterial'

/** Application color mode, resource qualifiers and system bars share one source. */
export class Appearance {
  private static context: common.UIAbilityContext | undefined = undefined
  private static barOverride: string = ''
  private static win: window.Window | undefined = undefined
  private static ready: boolean = false
  private static lifecycle: number = 0
  private static barRevision: number = 0
  private static applying: Promise<void> = Promise.resolve()
  private static barApplying: Promise<void> = Promise.resolve()
  private static barColor: string = ''
  private static materialKey: string = ''
  private static statusVisible: boolean = true
  private static statusApplied: boolean = true
  private static statusApplying: Promise<void> = Promise.resolve()

  static async init(context: common.UIAbilityContext, win: window.Window): Promise<void> {
    const lifecycle = ++Appearance.lifecycle
    Appearance.barRevision++
    Appearance.barApplying = Promise.resolve()
    Appearance.barColor = ''
    Appearance.materialKey = ''
    Appearance.ready = false
    Appearance.barOverride = ''
    Appearance.statusVisible = true
    Appearance.statusApplied = true
    Appearance.statusApplying = Promise.resolve()
    Appearance.context = context
    Appearance.win = win
    // An in-flight preference write belongs before the new window's restore.
    await Appearance.applying
    const mode = await PreferencesUtil.getInstance().getString(Constant.KEY_THEME_MODE, 'system')
    if (lifecycle !== Appearance.lifecycle) return
    Appearance.publishMode(Appearance.normalize(mode))
  }

  /** API 26 setColorMode requires the UIAbility page to have loaded. */
  static onWindowReady(): Promise<void> {
    if (Appearance.context === undefined || Appearance.win === undefined) return Promise.resolve()
    Appearance.ready = true
    const lifecycle = Appearance.lifecycle
    // Read after earlier saves finish, so startup cannot reapply an old choice.
    const task = Appearance.applying.then(() => Appearance.performApply(
      Appearance.normalize(AppStorage.get<string>('app_theme_mode') ?? 'system'), false, lifecycle))
    Appearance.applying = task.catch(() => {})
    return task
  }

  static onWindowDestroyed(): void {
    Appearance.lifecycle++
    Appearance.barRevision++
    Appearance.ready = false
    Appearance.context = undefined
    Appearance.win = undefined
    Appearance.barOverride = ''
    Appearance.barApplying = Promise.resolve()
    Appearance.barColor = ''
    Appearance.materialKey = ''
    Appearance.statusVisible = true
    Appearance.statusApplied = true
    Appearance.statusApplying = Promise.resolve()
  }

  static apply(mode: string, save: boolean = true): Promise<void> {
    const value = Appearance.normalize(mode)
    const lifecycle = Appearance.lifecycle
    const task = Appearance.applying.then(() => Appearance.performApply(value, save, lifecycle))
    // Preserve request order without allowing one failure to poison the queue.
    Appearance.applying = task.catch(() => {})
    return task
  }

  /** Serialize animated status-bar changes so a late hide cannot outlive a gallery. */
  static setStatusBarVisible(visible: boolean, animated: boolean = true): Promise<void> {
    Appearance.statusVisible = visible
    const win = Appearance.win
    const lifecycle: number = Appearance.lifecycle
    const task: Promise<void> = Appearance.statusApplying.then(async () => {
      if (!Appearance.ready || win === undefined || lifecycle !== Appearance.lifecycle ||
        visible !== Appearance.statusVisible || (animated && Appearance.statusApplied === visible)) return
      // A completed native promise does not mean its visibility animation has
      // finished. An explicit non-animated handoff must settle that animation
      // even when its requested endpoint matches the cached visible value.
      await win.setSpecificSystemBarEnabled('status', visible, animated)
      if (lifecycle === Appearance.lifecycle) Appearance.statusApplied = visible
    })
    Appearance.statusApplying = task.catch(() => { console.warn('Appearance: status visibility update failed') })
    return task
  }

  private static normalize(mode: string): string {
    return mode === 'light' || mode === 'dark' ? mode : 'system'
  }

  private static nativeMode(mode: string): ConfigurationConstant.ColorMode {
    return mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
  }

  private static publishMode(value: string): void {
    // setColorMode can synchronously call onConfigurationUpdate. Publish first.
    Appearance.barRevision++
    AppStorage.setOrCreate<string>('app_theme_mode', value)
    AppStorage.setOrCreate<boolean>('app_dark_mode', value === 'dark' ||
      (value === 'system' && Appearance.context?.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK))
  }

  private static async performApply(value: string, save: boolean, lifecycle: number): Promise<void> {
    if (lifecycle !== Appearance.lifecycle) return
    const previous = AppStorage.get<string>('app_theme_mode') ?? 'system'
    const previousDark = AppStorage.get<boolean>('app_dark_mode') ?? false
    // A failed save must leave the native resources and displayed choice intact.
    if (save) await PreferencesUtil.getInstance().putString(Constant.KEY_THEME_MODE, value)
    if (lifecycle !== Appearance.lifecycle) return
    Appearance.publishMode(value)
    const context = Appearance.context
    if (Appearance.ready && context !== undefined) {
      try {
        context.getApplicationContext().setColorMode(Appearance.nativeMode(value))
      } catch (e) {
        Appearance.publishMode(previous)
        AppStorage.setOrCreate<boolean>('app_dark_mode', previousDark)
        try { context.getApplicationContext().setColorMode(Appearance.nativeMode(previous)) }
        catch (rollbackError) { console.warn('Appearance: native theme rollback failed') }
        if (save) {
          try { await PreferencesUtil.getInstance().putString(Constant.KEY_THEME_MODE, previous) }
          catch (rollbackError) { console.warn('Appearance: saved theme rollback failed') }
        }
        if (lifecycle === Appearance.lifecycle) {
          try { await Appearance.updateBars() }
          catch (barError) { console.warn('Appearance: system bars rollback failed') }
        }
        throw new Error(String(e))
      }
    }
    await Appearance.updateBars()
    await Appearance.setStatusBarVisible(Appearance.statusVisible)
  }

  /** The gallery's first layout must already use the window's real dimensions. */
  static windowSize(): SizeOptions {
    const rect = Appearance.win?.getWindowProperties().windowRect
    return { width: rect?.width ?? 0, height: rect?.height ?? 0 }
  }

  static setBarAppearance(mode: string, animated: boolean = false): void {
    Appearance.barOverride = mode
    Appearance.updateBars(animated).catch(() => {})
  }

  static async updateBars(animated: boolean = false): Promise<void> {
    const context = Appearance.context
    const win = Appearance.win
    if (context === undefined || win === undefined) return
    const lifecycle = Appearance.lifecycle
    const revision = ++Appearance.barRevision
    // The native setter recreates the resource manager; never cache it.
    const config = await context.resourceManager.getConfiguration()
    if (lifecycle !== Appearance.lifecycle || revision !== Appearance.barRevision ||
      context !== Appearance.context || win !== Appearance.win) return
    const mode = Appearance.barOverride || (AppStorage.get<string>('app_theme_mode') ?? 'system')
    const dark = mode === 'dark' || (mode === 'system' && config.colorMode === resourceManager.ColorMode.DARK)
    const appMode = AppStorage.get<string>('app_theme_mode') ?? 'system'
    const appDark: boolean = appMode === 'dark' ||
      (appMode === 'system' && config.colorMode === resourceManager.ColorMode.DARK)
    AppStorage.setOrCreate<boolean>('app_dark_mode', appDark)
    // A foreground/configuration callback must still observe native capability
    // changes immediately, but unchanged values do not recreate every material.
    const materialKey: string = materialAppearanceKey(appDark)
    if (materialKey !== Appearance.materialKey) {
      Appearance.materialKey = materialKey
      AppStorage.setOrCreate<number>('ui_material_revision',
        (AppStorage.get<number>('ui_material_revision') ?? 0) + 1)
    }
    const color = dark ? '#FFFFFFFF' : '#FF000000'
    // Serialize native setters, so a slower old request cannot finish after and
    // overwrite the newest mode. Cache only successful writes for this window.
    const task: Promise<void> = Appearance.barApplying.then(async (): Promise<void> => {
      if (lifecycle !== Appearance.lifecycle || revision !== Appearance.barRevision ||
        context !== Appearance.context || win !== Appearance.win || color === Appearance.barColor) return
      const properties: window.SystemBarProperties = {
        statusBarColor: '#00000000', navigationBarColor: '#00000000',
        statusBarContentColor: color, navigationBarContentColor: color
      }
      if (animated) properties.enableStatusBarAnimation = true
      await win.setWindowSystemBarProperties(properties)
      if (lifecycle === Appearance.lifecycle && context === Appearance.context && win === Appearance.win) {
        Appearance.barColor = color
      }
    })
    Appearance.barApplying = task.catch(() => {})
    await task
  }
}
