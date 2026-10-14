import { PreferencesUtil } from '../util/PreferencesUtil'
import { CalendarTerm, TeachingCalendar } from '../model/TeachingCalendar'

interface CalendarCache { terms: CalendarTerm[]; updatedAt: number }

/** One date preference shared by Settings, Campus and the standalone timetable. */
export class AcademicCalendar {
  static readonly KEY_MODE: string = 'calendar_mode'
  static readonly KEY_START: string = 'calendar_start'
  static readonly KEY_REVISION: string = 'academic_calendar_revision'
  private static terms: CalendarTerm[] = []
  private static updatedAt: number = 0

  static async init(): Promise<void> {
    const prefs = PreferencesUtil.getInstance()
    const old = await prefs.getString('graduate_semester_start', '')
    const mode = await prefs.getString(AcademicCalendar.KEY_MODE, 'manual')
    let manual = await prefs.getString('calendar_manual_start', old)
    try {
      const cache = JSON.parse(await prefs.getString('official_calendar_cache', '{}')) as CalendarCache
      AcademicCalendar.terms = Array.isArray(cache.terms) ? cache.terms.filter((row: CalendarTerm) =>
        TeachingCalendar.validMonday(row.startDate)) : []
      AcademicCalendar.updatedAt = cache.updatedAt || 0
    } catch (e) { AcademicCalendar.terms = [] }
    // Preserve the effective date when upgrading from automatic mode. This is
    // a local migration; subsequent foregrounds never choose a new semester.
    if (mode === 'auto') manual = TeachingCalendar.current(AcademicCalendar.terms)?.startDate ?? manual
    if (!TeachingCalendar.validMonday(manual)) manual = ''
    await prefs.putString('calendar_manual_start', manual)
    await prefs.putString(AcademicCalendar.KEY_MODE, 'manual')
    AppStorage.setOrCreate<string>('calendar_manual_start', manual)
    AppStorage.setOrCreate<string>(AcademicCalendar.KEY_MODE, 'manual')
    AppStorage.setOrCreate<string>('calendar_manual_source', await prefs.getString('calendar_manual_source', ''))
    AcademicCalendar.publish()
  }

  static start(): string { return AppStorage.get<string>(AcademicCalendar.KEY_START) ?? '' }
  static manual(): boolean { return AppStorage.get<string>(AcademicCalendar.KEY_MODE) === 'manual' }
  static source(): string { return AppStorage.get<string>('calendar_source') ?? '' }
  static updated(): number { return AcademicCalendar.updatedAt }
  static cachedTerms(): CalendarTerm[] { return AcademicCalendar.terms.slice() }
  static fresh(): boolean { return AcademicCalendar.updatedAt > 0 && Date.now() >= AcademicCalendar.updatedAt &&
    Date.now() - AcademicCalendar.updatedAt < 86400000 && AcademicCalendar.terms.length > 0 }

  static publish(): void {
    const start = AppStorage.get<string>('calendar_manual_start') ?? ''
    const old = AcademicCalendar.start()
    AppStorage.setOrCreate<string>(AcademicCalendar.KEY_START, start)
    AppStorage.setOrCreate<string>('calendar_source', AppStorage.get<string>('calendar_manual_source') ?? '')
    AppStorage.setOrCreate<number>('calendar_updated', AcademicCalendar.updatedAt)
    if (old !== start) AppStorage.setOrCreate<number>(AcademicCalendar.KEY_REVISION,
      (AppStorage.get<number>(AcademicCalendar.KEY_REVISION) ?? 0) + 1)
  }

  static async setMode(mode: string): Promise<void> {
    const chosen = 'manual'
    await PreferencesUtil.getInstance().putString(AcademicCalendar.KEY_MODE, chosen)
    AppStorage.setOrCreate<string>(AcademicCalendar.KEY_MODE, chosen)
    AcademicCalendar.publish()
  }

  static async setManual(value: string, source: string = ''): Promise<void> {
    if (!TeachingCalendar.validMonday(value)) throw new Error('Invalid teaching-week Monday')
    await PreferencesUtil.getInstance().putString('calendar_manual_start', value)
    await PreferencesUtil.getInstance().putString('calendar_manual_source', source)
    AppStorage.setOrCreate<string>('calendar_manual_start', value)
    AppStorage.setOrCreate<string>('calendar_manual_source', source)
    await AcademicCalendar.setMode('manual')
  }

  static async store(terms: CalendarTerm[]): Promise<void> {
    if (terms.length === 0 || terms.some((row: CalendarTerm) => !TeachingCalendar.validMonday(row.startDate))) {
      throw new Error('Invalid official calendar')
    }
    const cache: CalendarCache = { terms: terms, updatedAt: Date.now() }
    await PreferencesUtil.getInstance().putString('official_calendar_cache', JSON.stringify(cache))
    AcademicCalendar.terms = terms
    AcademicCalendar.updatedAt = cache.updatedAt
    AcademicCalendar.publish()
  }
}
