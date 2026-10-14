import { vibrator } from '@kit.SensorServiceKit'
import { PreferencesUtil } from '../util/PreferencesUtil'

/** Opt-in, system-managed touch vibration. No polling and no vibration on scroll. */
export class HapticFeedback {
  static readonly KEY_ENABLED: string = 'haptic_feedback_enabled'
  private static last: number = 0
  private static writes: Promise<void> = Promise.resolve()
  private static effectSupported: boolean | undefined = undefined
  static async init(): Promise<void> {
    AppStorage.setOrCreate<boolean>(HapticFeedback.KEY_ENABLED,
      await PreferencesUtil.getInstance().getBoolean(HapticFeedback.KEY_ENABLED, false))
  }
  static async set(enabled: boolean): Promise<void> {
    const task = HapticFeedback.writes.catch(() => {}).then(async (): Promise<void> => {
      await PreferencesUtil.getInstance().putBoolean(HapticFeedback.KEY_ENABLED, enabled)
      AppStorage.setOrCreate<boolean>(HapticFeedback.KEY_ENABLED, enabled)
      if (enabled) HapticFeedback.selection()
    })
    HapticFeedback.writes = task
    await task
  }
  static selection(): void {
    if (AppStorage.get<boolean>(HapticFeedback.KEY_ENABLED) !== true || Date.now() - HapticFeedback.last < 80) return
    HapticFeedback.last = Date.now()
    try {
      if (HapticFeedback.effectSupported === undefined) {
        try { HapticFeedback.effectSupported = vibrator.getEffectInfoSync('haptic.common.click').isEffectSupported }
        catch (e) { HapticFeedback.effectSupported = false }
      }
      const effect: vibrator.VibrateEffect = HapticFeedback.effectSupported ?
        { type: 'preset', effectId: 'haptic.common.click', count: 1, intensity: 35 } : { type: 'time', duration: 6 }
      vibrator.startVibration(effect, { usage: 'touch' }).catch(() => {})
    } catch (e) { /* Devices without a motor must retain the action and visual feedback. */ }
  }
}
