import { AppState } from '../common/AppState'
import { AcademicAccount } from '../common/AcademicAccount'
import { AcademicCalendar } from '../common/AcademicCalendar'
import { AppLanguage } from '../common/AppLanguage'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { Course, SemesterInfo } from '../model/Academic'
import { ScheduleEdits, TimetableSchedule } from '../model/TimetableSchedule'
import { TeachingCalendar } from '../model/TeachingCalendar'
import { FduRepository } from './FduRepository'

export interface ScheduleSnapshot { semester: SemesterInfo; courses: Course[]; updatedAt: number; historicalDiary?: boolean }

class ScheduleRequest {
  networkStarted: boolean = false
  task: Promise<ScheduleSnapshot> | null = null
}

/** Cached whole-semester activities, isolated by account AND academic role. */
export class TimetableRepository {
  private static pending: Map<string, ScheduleRequest> = new Map<string, ScheduleRequest>()
  private static readonly CACHE_AGE_MS: number = 30 * 60 * 1000

  static owner(): string { return encodeURIComponent(AppState.getPerson().getStudentId() || 'guest') + '_' + AcademicAccount.group() }
  static termKey(semester: SemesterInfo): string { return encodeURIComponent(semester.id || semester.startDate || 'undated') }

  static graduateTermId(now: Date = new Date()): string {
    // A manual Monday adjusts week labels, not the identity of the server's
    // current term. Preserve local edits when that Monday is corrected.
    const candidate = TeachingCalendar.termAtDate(AcademicCalendar.cachedTerms(), now)
    // A calendar from a previous academic year cannot identify today's term.
    const official = candidate && now.getTime() - Date.parse(candidate.startDate + 'T00:00:00') <= 210 * 86400000 ? candidate : undefined
    const date = official ? new Date(official.startDate + 'T00:00:00') : now
    const month = date.getMonth()
    const fall = month >= 7 || (!official && month === 0)
    const year = date.getFullYear() - (!official && month === 0 ? 1 : 0)
    return 'graduate-' + String(year) + (fall ? '-fall' : '-spring')
  }

  static async semesters(force: boolean = false): Promise<SemesterInfo[]> {
    if (!AppState.isLoggedIn() || AcademicAccount.isGraduate()) return []
    return FduRepository.getInstance().getSemesters(force)
  }

  static async cached(selected?: SemesterInfo, monday: string = AcademicCalendar.start()): Promise<ScheduleSnapshot | undefined> {
    try {
      const owner: string = TimetableRepository.owner()
      const key: string = 'timetable_cache_' + owner + (selected ? '_' + TimetableRepository.termKey(selected) : '')
      let raw = await PreferencesUtil.getInstance().getString(key, '')
      if (!raw && selected) raw = await PreferencesUtil.getInstance().getString('timetable_cache_' + owner, '')
      if (!raw) return undefined
      const snapshot = JSON.parse(raw) as ScheduleSnapshot
      if (!Array.isArray(snapshot.courses) || !snapshot.semester || !snapshot.semester.id) return undefined
      if (selected && snapshot.semester.id !== selected.id) return undefined
      if (!selected && monday && !TimetableRepository.matchesDate(snapshot.semester, monday)) return undefined
      snapshot.courses = TimetableSchedule.merge(snapshot.courses)
      return snapshot
    } catch (e) { return undefined }
  }

  static async load(semester?: SemesterInfo, force: boolean = false): Promise<ScheduleSnapshot> {
    const owner = TimetableRepository.owner()
    const monday: string = AcademicCalendar.start()
    const key = owner + ':' + (semester?.id ?? '') + ':' + monday
    const pending = TimetableRepository.pending.get(key)
    if (pending && pending.task !== null) {
      const snapshot = await pending.task
      if (force && !pending.networkStarted) return TimetableRepository.load(semester, true)
      return snapshot
    }
    const request: ScheduleRequest = new ScheduleRequest()
    const task = TimetableRepository.read(semester, owner, monday, force, request)
    request.task = task
    TimetableRepository.pending.set(key, request)
    try { return await task }
    finally { if (TimetableRepository.pending.get(key) === request) TimetableRepository.pending.delete(key) }
  }

  private static matchesDate(semester: SemesterInfo, monday: string): boolean {
    if (AcademicAccount.isGraduate()) return semester.id === TimetableRepository.graduateTermId(new Date(monday + 'T00:00:00'))
    return TeachingCalendar.forMonday([semester], monday) !== undefined
  }

  private static async read(selected: SemesterInfo | undefined, owner: string, monday: string, force: boolean, request: ScheduleRequest): Promise<ScheduleSnapshot> {
    if (!force) {
      const snapshot: ScheduleSnapshot | undefined = await TimetableRepository.cached(selected, monday)
      if (owner !== TimetableRepository.owner()) throw new Error('Account changed')
      if (snapshot && snapshot.updatedAt > 0 && Date.now() >= snapshot.updatedAt &&
        Date.now() - snapshot.updatedAt < TimetableRepository.CACHE_AGE_MS) return snapshot
    }
    let chosen: SemesterInfo | undefined = selected
    if (!AcademicAccount.isGraduate()) {
      // Resolve the real catalog ID before consulting a whole-semester cache.
      // The catalog itself is cached separately by JwglRepository.
      const semesters: SemesterInfo[] = await TimetableRepository.semesters(force)
      if (owner !== TimetableRepository.owner()) throw new Error('Account changed')
      chosen = selected ? semesters.find((row: SemesterInfo) => row.id === selected.id) :
        monday ? TeachingCalendar.forMonday(semesters, monday) : TeachingCalendar.semester(semesters) ?? semesters[0]
      if (chosen === undefined) throw new Error(AppLanguage.text($r('app.string.timetable_semester_not_found'), 0, monday))
    } else {
      chosen = { id: TimetableRepository.graduateTermId(monday ? new Date(monday + 'T00:00:00') : new Date()),
        name: '', startDate: monday }
    }
    if (!force) {
      const snapshot = await TimetableRepository.cached(chosen, monday)
      if (owner !== TimetableRepository.owner()) throw new Error('Account changed')
      if (snapshot && snapshot.updatedAt > 0 &&
        Date.now() >= snapshot.updatedAt && Date.now() - snapshot.updatedAt < TimetableRepository.CACHE_AGE_MS) return snapshot
    }
    if (AcademicAccount.isGraduate() && chosen.id !== TimetableRepository.graduateTermId()) {
      const snapshot: ScheduleSnapshot | undefined = await TimetableRepository.cached(chosen, monday)
      if (!force && snapshot !== undefined) return snapshot
      request.networkStarted = true
      const courses: Course[] = await FduRepository.getInstance().getGraduateHistory(monday)
      if (owner !== TimetableRepository.owner()) throw new Error('Account changed')
      const history: ScheduleSnapshot = { semester: chosen, courses: courses, updatedAt: Date.now(), historicalDiary: true }
      await TimetableRepository.saveSnapshot(history, owner, monday)
      return history
    }
    request.networkStarted = true
    return TimetableRepository.fetch(chosen, owner, monday)
  }

  private static async fetch(semester: SemesterInfo, owner: string, monday: string): Promise<ScheduleSnapshot> {
    if (owner !== TimetableRepository.owner()) throw new Error('Account changed')
    const courses = TimetableSchedule.merge(await FduRepository.getInstance().getCourses(semester.id))
    const snapshot: ScheduleSnapshot = { semester: semester,
      courses: courses, updatedAt: Date.now() }
    await TimetableRepository.saveSnapshot(snapshot, owner, monday)
    return snapshot
  }

  private static async saveSnapshot(snapshot: ScheduleSnapshot, owner: string, monday: string): Promise<void> {
    // A request finishing after logout cannot install the previous account's data.
    if (owner !== TimetableRepository.owner()) throw new Error('Account changed')
    await PreferencesUtil.getInstance().putString('timetable_cache_' + owner + '_' + TimetableRepository.termKey(snapshot.semester), JSON.stringify(snapshot))
    if (monday === AcademicCalendar.start()) await PreferencesUtil.getInstance().putString('timetable_cache_' + owner, JSON.stringify(snapshot))
  }

  static async edits(semester: SemesterInfo): Promise<ScheduleEdits> {
    try {
      const raw = await PreferencesUtil.getInstance().getString('timetable_edits_' + TimetableRepository.owner() + '_' + TimetableRepository.termKey(semester), '')
      const edits = raw ? JSON.parse(raw) as ScheduleEdits : { added: [], hidden: [] } as ScheduleEdits
      return { added: Array.isArray(edits.added) ? edits.added.filter((course: Course) => TimetableSchedule.valid(course)) : [],
        hidden: Array.isArray(edits.hidden) ? edits.hidden.filter((key: string) => typeof key === 'string') : [] }
    } catch (e) { return { added: [], hidden: [] } }
  }

  static async saveEdits(semester: SemesterInfo, edits: ScheduleEdits): Promise<void> {
    await PreferencesUtil.getInstance().putString('timetable_edits_' + TimetableRepository.owner() + '_' + TimetableRepository.termKey(semester), JSON.stringify(edits))
  }
}
