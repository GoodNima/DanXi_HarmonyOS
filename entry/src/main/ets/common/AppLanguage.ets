import { common } from '@kit.AbilityKit'
import { i18n } from '@kit.LocalizationKit'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { Constant } from './Constant'

/** UI language and resource qualifiers share the saved preference. */
export class AppLanguage {
  static readonly KEY_MODE: string = 'app_language_mode'
  static readonly KEY_REVISION: string = 'app_language_revision'
  static readonly CHOICES: string[] = ['system', 'zh-CN', 'en-US', 'ja-JP', 'zh-TW']
  private static context: common.UIAbilityContext | undefined = undefined
  private static appliedLanguage: string = ''
  private static ready: boolean = false

  static normalize(mode: string): string {
    return AppLanguage.CHOICES.includes(mode) ? mode : 'system'
  }

  static current(): string {
    return AppLanguage.appliedLanguage || AppLanguage.resolve(AppStorage.get<string>(AppLanguage.KEY_MODE) ?? 'system',
      i18n.System.getSystemLanguage())
  }

  static resolve(mode: string, system: string): string {
    if (AppLanguage.normalize(mode) !== 'system') return mode
    const tag = system.toLowerCase().replace(/_/g, '-')
    if (tag === 'en' || tag.startsWith('en-')) return 'en-US'
    if (tag === 'ja' || tag.startsWith('ja-')) return 'ja-JP'
    if (tag.startsWith('zh') && /(?:hant|tw|hk|mo)/.test(tag)) return 'zh-TW'
    return 'zh-CN'
  }

  static async init(context: common.UIAbilityContext): Promise<void> {
    AppLanguage.ready = false
    AppLanguage.appliedLanguage = ''
    AppLanguage.context = context
    const mode = await PreferencesUtil.getInstance().getString(Constant.KEY_LANGUAGE, 'system')
    AppStorage.setOrCreate<string>(AppLanguage.KEY_MODE, AppLanguage.normalize(mode))
  }

  // API 26 setLanguage requires an already loaded UIAbility window.
  static onWindowReady(): void {
    AppLanguage.ready = true
    AppLanguage.syncSystem()
  }

  static onWindowDestroyed(): void {
    AppLanguage.ready = false
  }

  static syncSystem(): void {
    if (!AppLanguage.ready || AppLanguage.context === undefined) return
    const mode = AppStorage.get<string>(AppLanguage.KEY_MODE) ?? 'system'
    const tag = AppLanguage.resolve(mode, i18n.System.getSystemLanguage())
    if (tag === AppLanguage.appliedLanguage) return
    const previous = AppLanguage.appliedLanguage
    // Native setLanguage synchronously invokes onConfigurationUpdate. Set the
    // guard first so that callback cannot recursively set the same language.
    AppLanguage.appliedLanguage = tag
    try { AppLanguage.context.getApplicationContext().setLanguage(tag) }
    catch (e) {
      AppLanguage.appliedLanguage = previous
      throw new Error(String(e))
    }
    AppStorage.setOrCreate<number>(AppLanguage.KEY_REVISION,
      (AppStorage.get<number>(AppLanguage.KEY_REVISION) ?? 0) + 1)
  }

  static async apply(mode: string): Promise<void> {
    const value = AppLanguage.normalize(mode)
    const previous = AppStorage.get<string>(AppLanguage.KEY_MODE) ?? 'system'
    await PreferencesUtil.getInstance().putString(Constant.KEY_LANGUAGE, value)
    AppStorage.setOrCreate<string>(AppLanguage.KEY_MODE, value)
    try { AppLanguage.syncSystem() }
    catch (e) {
      AppStorage.setOrCreate<string>(AppLanguage.KEY_MODE, previous)
      await PreferencesUtil.getInstance().putString(Constant.KEY_LANGUAGE, previous)
      throw new Error(String(e))
    }
  }

  static title(mode: string): Resource {
    switch (mode) {
      case 'zh-CN': return $r('app.string.language_zh_cn')
      case 'zh-TW': return $r('app.string.language_zh_tw')
      case 'en-US': return $r('app.string.language_en')
      case 'ja-JP': return $r('app.string.language_ja')
      default: return $r('app.string.theme_system')
    }
  }

  /** Composed labels and toasts; plain Text can use $r directly. */
  static text(resource: Resource, revision: number = 0, ...args: (string | number)[]): string {
    if (AppLanguage.context === undefined) return ''
    return AppLanguage.context.resourceManager.getStringSync(resource.id, ...args)
  }

  static weekday(day: number, revision: number = 0): string {
    const names: Resource[] = [$r('app.string.weekday_mon'), $r('app.string.weekday_tue'),
      $r('app.string.weekday_wed'), $r('app.string.weekday_thu'), $r('app.string.weekday_fri'),
      $r('app.string.weekday_sat'), $r('app.string.weekday_sun')]
    return day >= 1 && day <= 7 ? AppLanguage.text(names[day - 1]) : ''
  }

  static campus(name: string, revision: number = 0): string {
    switch (name) {
      case '邯郸': return AppLanguage.text($r('app.string.campus_handan'))
      case '枫林': return AppLanguage.text($r('app.string.campus_fenglin'))
      case '江湾': return AppLanguage.text($r('app.string.campus_jiangwan'))
      case '张江': return AppLanguage.text($r('app.string.campus_zhangjiang'))
      default: return name
    }
  }

  /** Localize the wire model's presentation time without changing server data. */
  static relativeTime(value: string, revision: number = 0): string {
    if (value === '刚刚') return AppLanguage.text($r('app.string.time_just_now'))
    const match = /^(\d+)(分钟|小时|天)前$/.exec(value)
    if (match === null) return value
    const resource = match[2] === '分钟' ? $r('app.string.time_minutes_ago') :
      match[2] === '小时' ? $r('app.string.time_hours_ago') : $r('app.string.time_days_ago')
    return AppLanguage.text(resource, revision, Number(match[1]))
  }
}
