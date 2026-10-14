import { CampusPreference } from './CampusPreference'
import { PreferencesUtil } from '../util/PreferencesUtil'

interface CampusFilterRecord { systemCampus: string; selected: string }

/** Manual filters survive reopening. A changed system campus starts a new
 * scope, so old per-service selections cannot override My → Current campus. */
export class CampusFilterPreference {
  private static writes: Promise<void> = Promise.resolve()
  private static key(feature: string): string { return 'campus_filter_' + feature }
  static async read(feature: string, fallback: string = CampusPreference.current(), allowAll: boolean = false): Promise<string> {
    await CampusFilterPreference.writes.catch(() => {})
    const value: string = await PreferencesUtil.getInstance().getString(CampusFilterPreference.key(feature), '')
    try {
      const record = JSON.parse(value) as CampusFilterRecord
      if (record.systemCampus === CampusPreference.current() &&
        (CampusPreference.CHOICES.includes(record.selected) || (allowAll && record.selected === ''))) return record.selected
    } catch (error) { /* An absent or old preference uses the current campus. */ }
    return fallback
  }
  static remember(feature: string, selected: string, allowAll: boolean = false): Promise<void> {
    if (!CampusPreference.CHOICES.includes(selected) && !(allowAll && selected === '')) return Promise.resolve()
    const record: CampusFilterRecord = { systemCampus: CampusPreference.current(), selected: selected }
    const task = CampusFilterPreference.writes.catch(() => {}).then(async (): Promise<void> => {
      await PreferencesUtil.getInstance().putString(CampusFilterPreference.key(feature), JSON.stringify(record))
    })
    CampusFilterPreference.writes = task; return task
  }
}
