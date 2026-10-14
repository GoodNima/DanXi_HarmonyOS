/**
 * Global app state manager.
 * Uses HarmonyOS AppStorage for global state sharing.
 */

import { Person } from '../model/Person'
import { Constant } from '../common/Constant'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { FduRepository } from '../repository/FduRepository'
import { ForumPresentation } from './ForumPresentation'
import { CampusLayout, CampusModule } from './CampusLayout'
import { AcademicCalendar } from './AcademicCalendar'
import { CampusPreference } from './CampusPreference'
import { ForumPreferences } from './ForumPreferences'
import { ForumRepository } from '../repository/ForumRepository'

export class AppState {
  private static accountEpoch: number = 0
  private static accountWrites: Promise<void> = Promise.resolve()
  private static writeAccount(action: () => Promise<void>): Promise<void> {
    const task = AppState.accountWrites.then(action, action)
    AppState.accountWrites = task.catch(() => {})
    return task
  }
  static readonly KEY_PERSON: string = 'app_person'
  static readonly KEY_IS_LOGGED_IN: string = 'app_is_logged_in'
  static readonly KEY_IS_GUEST: string = 'app_is_guest'
  static readonly KEY_THEME_MODE: string = 'app_theme_mode'
  static readonly KEY_DASHBOARD_ORDER: string = 'app_dashboard_order'

  /**
   * Initialize app state from preferences.
   */
  static async init(): Promise<void> {
    await AcademicCalendar.init()
    await CampusPreference.init()
    await ForumPreferences.init()
    // Restore the guest flag from disk. This used to be hard-reset to false on
    // every launch, so a returning guest was always bounced to the login page.
    const isGuest: boolean = await PreferencesUtil.getInstance().getBoolean(Constant.KEY_IS_GUEST, false)
    AppStorage.setOrCreate<boolean>(AppState.KEY_IS_GUEST, isGuest)
    const personJson = await PreferencesUtil.getInstance().getString(Constant.KEY_USER_INFO, '')
    if (personJson) {
      const person = Person.fromJson(personJson)
      await FduRepository.getInstance().restoreSession(person)
      AppStorage.setOrCreate<boolean>(AppState.KEY_IS_LOGGED_IN, person.isLoggedIn())
      AppStorage.setOrCreate<string>(AppState.KEY_PERSON, personJson)
    } else {
      AppStorage.setOrCreate<boolean>(AppState.KEY_IS_LOGGED_IN, false)
      AppStorage.setOrCreate<string>(AppState.KEY_PERSON, '')
    }

    const themeMode = await PreferencesUtil.getInstance().getString(Constant.KEY_THEME_MODE, 'system')
    AppStorage.setOrCreate<string>(AppState.KEY_THEME_MODE, themeMode)
    AppStorage.setOrCreate<boolean>(Constant.KEY_USE_WEBVPN,
      await PreferencesUtil.getInstance().getBoolean(Constant.KEY_USE_WEBVPN, true))
    const foldMode = await PreferencesUtil.getInstance().getString(Constant.KEY_FORUM_FOLD_BEHAVIOR, 'fold')
    AppStorage.setOrCreate<string>(Constant.KEY_FORUM_FOLD_BEHAVIOR, ForumPresentation.foldMode(foldMode))

    const orderJson = await PreferencesUtil.getInstance().getString(Constant.KEY_DASHBOARD_ORDER, '')
    AppStorage.setOrCreate<string>(AppState.KEY_DASHBOARD_ORDER, JSON.stringify(CampusLayout.parse(orderJson)))
  }

  /**
   * Save person to state and preferences.
   */
  static async setPerson(person: Person): Promise<void> {
    const epoch: number = ++AppState.accountEpoch
    const json = person.toJson()
    await AppState.writeAccount(async () => {
      if (epoch === AppState.accountEpoch) await PreferencesUtil.getInstance().putString(Constant.KEY_USER_INFO, json)
    })
    if (epoch !== AppState.accountEpoch) return
    AppStorage.setOrCreate<string>(AppState.KEY_PERSON, json)
    AppStorage.setOrCreate<boolean>(AppState.KEY_IS_LOGGED_IN, person.isLoggedIn())
  }

  /** Merge a delayed authenticated profile only into the exact account that requested it. */
  static async updateIdentity(expected: string, name: string, department: string): Promise<boolean> {
    if (!AppState.isLoggedIn() || AppStorage.get<string>(AppState.KEY_PERSON) !== expected || !name.trim()) return false
    const person = Person.fromJson(expected); const info = person.getInfo()
    if (info === null) return false
    info.name = name.trim(); if (department.trim()) info.department = department.trim()
    person.setInfo(info)
    await AppState.setPerson(person)
    return AppState.isLoggedIn() && AppStorage.get<string>(AppState.KEY_PERSON) === person.toJson()
  }

  /**
   * Get current person.
   */
  static getPerson(): Person {
    const json = AppStorage.get<string>(AppState.KEY_PERSON) ?? ''
    return Person.fromJson(json)
  }

  /**
   * Check if user is logged in.
   */
  static isLoggedIn(): boolean {
    return AppStorage.get<boolean>(AppState.KEY_IS_LOGGED_IN) ?? false
  }

  /**
   * Set app to guest mode.
   */
  static async setGuest(): Promise<void> {
    ++AppState.accountEpoch
    AppStorage.setOrCreate<boolean>(AppState.KEY_IS_GUEST, true)
    AppStorage.setOrCreate<boolean>(AppState.KEY_IS_LOGGED_IN, false)
    AppStorage.setOrCreate<string>(AppState.KEY_PERSON, '')
    await AppState.writeAccount(() => PreferencesUtil.getInstance().remove(Constant.KEY_USER_INFO))
    // Persist, otherwise the flag dies with the process (see init()).
    await PreferencesUtil.getInstance().putBoolean(Constant.KEY_IS_GUEST, true)
  }

  /**
   * Check if user is in guest mode.
   */
  static isGuest(): boolean {
    return AppStorage.get<boolean>(AppState.KEY_IS_GUEST) ?? false
  }

  /**
   * Clear guest mode flag.
   */
  static async clearGuest(): Promise<void> {
    AppStorage.setOrCreate<boolean>(AppState.KEY_IS_GUEST, false)
    await PreferencesUtil.getInstance().putBoolean(Constant.KEY_IS_GUEST, false)
  }

  /**
   * Logout and clear state.
   */
  static async logout(): Promise<void> {
    ++AppState.accountEpoch
    FduRepository.getInstance().forgetCredentials()
    AppStorage.setOrCreate<string>(AppState.KEY_PERSON, '')
    AppStorage.setOrCreate<boolean>(AppState.KEY_IS_LOGGED_IN, false)
    AppStorage.setOrCreate<boolean>(AppState.KEY_IS_GUEST, false)
    await ForumRepository.getInstance().forgetSession()
    await AppState.writeAccount(() => PreferencesUtil.getInstance().remove(Constant.KEY_USER_INFO))
    await PreferencesUtil.getInstance().remove(Constant.KEY_LOGIN_TOKEN)
    await PreferencesUtil.getInstance().putBoolean(Constant.KEY_IS_GUEST, false)
  }

  /**
   * Get dashboard order.
   */
  static getDashboardOrder(): string[] {
    return AppState.getDashboardLayout().filter((row: CampusModule) => row.enabled).map((row: CampusModule) => row.id)
  }

  static getDashboardLayout(): CampusModule[] {
    return CampusLayout.parse(AppStorage.get<string>(AppState.KEY_DASHBOARD_ORDER) ?? '')
  }

  static async setDashboardLayout(rows: CampusModule[]): Promise<void> {
    const json = JSON.stringify(CampusLayout.parse(JSON.stringify(rows)))
    const previous: string = JSON.stringify(AppState.getDashboardLayout())
    try {
      await PreferencesUtil.getInstance().putString(Constant.KEY_DASHBOARD_ORDER, json)
    } catch (error) {
      // Preferences.put changes its memory cache before flush reaches disk.
      // Restore that cache too: otherwise an unrelated later setting flush
      // could persist a draft whose Save failed and whose editor was cancelled.
      try { await PreferencesUtil.getInstance().putString(Constant.KEY_DASHBOARD_ORDER, previous) } catch (rollbackError) {}
      throw error as Error
    }
    AppStorage.setOrCreate<string>(AppState.KEY_DASHBOARD_ORDER, json)
  }

  /**
   * Save dashboard order.
   */
  static async setDashboardOrder(order: string[]): Promise<void> {
    await AppState.setDashboardLayout(CampusLayout.parse(JSON.stringify(order)))
  }
}
