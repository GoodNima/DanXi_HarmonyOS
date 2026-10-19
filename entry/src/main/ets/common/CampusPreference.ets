import { PreferencesUtil } from '../util/PreferencesUtil'
import { Constant } from './Constant'
import { CampusFormStore } from '../widget/CampusFormStore'

/** Same four campus choices as upstream SettingsProvider.campus. */
export class CampusPreference {
  static readonly KEY: string = 'current_campus'
  static readonly REVISION_KEY: string = 'campus_preference_revision'
  static readonly CHOICES: string[] = Constant.CAMPUS_NAMES
  private static pending: Promise<void> = Promise.resolve()

  static normalize(value: string): string { return CampusPreference.CHOICES.includes(value) ? value : '邯郸' }
  static current(): string { return CampusPreference.normalize(AppStorage.get<string>(CampusPreference.KEY) ?? '') }
  static title(value: string): Resource {
    if (value === '枫林') return $r('app.string.campus_fenglin')
    if (value === '张江') return $r('app.string.campus_zhangjiang')
    if (value === '江湾') return $r('app.string.campus_jiangwan')
    return $r('app.string.campus_handan')
  }
  static async init(): Promise<void> {
    const value = await PreferencesUtil.getInstance().getString(CampusPreference.KEY, '邯郸')
    AppStorage.setOrCreate<string>(CampusPreference.KEY, CampusPreference.normalize(value))
  }
  static set(value: string): Promise<void> {
    if (!CampusPreference.CHOICES.includes(value)) return Promise.reject(new Error('Invalid campus'))
    const task = CampusPreference.pending.catch(() => {}).then(async (): Promise<void> => {
      await PreferencesUtil.getInstance().putString(CampusPreference.KEY, value)
      if (value !== CampusPreference.current()) CampusFormStore.clear()
      AppStorage.setOrCreate<string>(CampusPreference.KEY, value)
      AppStorage.setOrCreate<number>(CampusPreference.REVISION_KEY, (AppStorage.get<number>(CampusPreference.REVISION_KEY) ?? 0) + 1)
    })
    CampusPreference.pending = task
    return task
  }
}
