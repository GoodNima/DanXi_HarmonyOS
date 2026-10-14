/**
 * Preferences utility for local storage.
 * Uses HarmonyOS @kit.ArkData preferences module.
 */

import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'

export class PreferencesUtil {
  private static instance: PreferencesUtil | null = null
  private prefs: preferences.Preferences | null = null
  private storeName: string = 'danxi_prefs'

  private constructor() {}

  static getInstance(): PreferencesUtil {
    if (!PreferencesUtil.instance) {
      PreferencesUtil.instance = new PreferencesUtil()
    }
    return PreferencesUtil.instance
  }

  /**
   * Initialize the preferences store.
   *
   * Throws on failure instead of silently leaving `prefs` null: a silent
   * failure used to turn every later read/write into a no-op, which surfaced
   * as "suddenly logged out" with no error anywhere.
   */
  async init(context: common.UIAbilityContext, storeName: string = 'danxi_prefs'): Promise<void> {
    this.storeName = storeName
    this.prefs = await preferences.getPreferences(context, this.storeName)
  }

  /** True once init() has succeeded; callers can use this to fail loudly. */
  isReady(): boolean {
    return this.prefs !== null
  }

  async putString(key: string, value: string): Promise<void> {
    if (!this.prefs) return
    await this.prefs.put(key, value)
    await this.prefs.flush()
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (!this.prefs) return defaultValue
    return await this.prefs.get(key, defaultValue) as string
  }

  async putBoolean(key: string, value: boolean): Promise<void> {
    if (!this.prefs) return
    await this.prefs.put(key, value)
    await this.prefs.flush()
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    if (!this.prefs) return defaultValue
    return await this.prefs.get(key, defaultValue) as boolean
  }

  async putInt(key: string, value: number): Promise<void> {
    if (!this.prefs) return
    await this.prefs.put(key, value)
    await this.prefs.flush()
  }

  async getInt(key: string, defaultValue: number = 0): Promise<number> {
    if (!this.prefs) return defaultValue
    return await this.prefs.get(key, defaultValue) as number
  }

  async remove(key: string): Promise<void> {
    if (!this.prefs) return
    await this.prefs.delete(key)
    await this.prefs.flush()
  }

  async clear(): Promise<void> {
    if (!this.prefs) return
    await this.prefs.clear()
    await this.prefs.flush()
  }
}
