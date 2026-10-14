import { PreferencesUtil } from '../util/PreferencesUtil'
import { ClassroomPresentation } from './ClassroomPresentation'

export class ClassroomPreference {
  static readonly KEY_HIGH_CONTRAST: string = 'classroom_high_contrast'
  static readonly KEY_ONLY_FREE: string = 'classroom_only_free'
  static readonly KEY_REMEMBER_BUILDING: string = 'classroom_remember_building'
  private static loaded: boolean = false
  private static loading: Promise<void> | undefined = undefined
  private static writes: Promise<void> = Promise.resolve()

  static async init(): Promise<void> {
    if (ClassroomPreference.loaded) return
    if (ClassroomPreference.loading !== undefined) return ClassroomPreference.loading
    ClassroomPreference.loading = ClassroomPreference.restore()
    try { await ClassroomPreference.loading; ClassroomPreference.loaded = true }
    finally { ClassroomPreference.loading = undefined }
  }

  private static async restore(): Promise<void> {
    const prefs = PreferencesUtil.getInstance()
    AppStorage.setOrCreate<boolean>(ClassroomPreference.KEY_HIGH_CONTRAST,
      await prefs.getBoolean(ClassroomPreference.KEY_HIGH_CONTRAST, false))
    AppStorage.setOrCreate<boolean>(ClassroomPreference.KEY_ONLY_FREE,
      await prefs.getBoolean(ClassroomPreference.KEY_ONLY_FREE, false))
    AppStorage.setOrCreate<boolean>(ClassroomPreference.KEY_REMEMBER_BUILDING,
      await prefs.getBoolean(ClassroomPreference.KEY_REMEMBER_BUILDING, true))
  }

  static async set(key: string, value: boolean): Promise<void> {
    if (![ClassroomPreference.KEY_HIGH_CONTRAST, ClassroomPreference.KEY_ONLY_FREE,
      ClassroomPreference.KEY_REMEMBER_BUILDING].includes(key)) return
    await ClassroomPreference.init()
    const task = ClassroomPreference.writes.catch(() => {}).then(async (): Promise<void> => {
      await PreferencesUtil.getInstance().putBoolean(key, value)
      AppStorage.setOrCreate<boolean>(key, value)
    })
    ClassroomPreference.writes = task
    await task
  }

  static async building(campus: string): Promise<string> {
    await ClassroomPreference.init()
    const buildings = ClassroomPresentation.buildings(campus)
    if (AppStorage.get<boolean>(ClassroomPreference.KEY_REMEMBER_BUILDING) === false) return buildings[0]
    const value = await PreferencesUtil.getInstance().getString('classroom_building_' + campus, '')
    const migrated: string = ['F1', 'F2'].includes(value) ? 'F' : ['JA', 'JB'].includes(value) ? 'J' : value === 'Z2' ? 'Z' : value
    return buildings.includes(migrated) ? migrated : buildings[0]
  }

  static async remember(campus: string, building: string): Promise<void> {
    await ClassroomPreference.init()
    const task = ClassroomPreference.writes.catch(() => {}).then(async (): Promise<void> => {
      if (AppStorage.get<boolean>(ClassroomPreference.KEY_REMEMBER_BUILDING) === false ||
        !ClassroomPresentation.buildings(campus).includes(building)) return
      await PreferencesUtil.getInstance().putString('classroom_building_' + campus, building)
    })
    ClassroomPreference.writes = task
    await task
  }
}
