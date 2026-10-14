import { AppState } from './AppState'
import { CampusPreviewItem } from '../model/CampusPreviewItem'
import { CampusLayout } from './CampusLayout'
import { CampusCardInformation } from './CampusCardInformation'
import { AppLanguage } from './AppLanguage'
import { AcademicCalendar } from './AcademicCalendar'
import { AcademicAccount } from './AcademicAccount'
import { CampusPreference } from './CampusPreference'
import { CampusFilterPreference } from './CampusFilterPreference'
import { CampusService } from './CampusService'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { FduRepository } from '../repository/FduRepository'
import { CardRepository } from '../repository/CardRepository'
import { ZlappRepository } from '../repository/ZlappRepository'
import { TimetableRepository } from '../repository/TimetableRepository'
import { TimetableSchedule } from '../model/TimetableSchedule'
import { SemesterInfo } from '../model/Academic'
import { TeachingCalendar } from '../model/TeachingCalendar'
import { CardPresentation } from '../model/CardPresentation'
import { CampusGreeting } from './CampusGreeting'
import { AccountIdentity } from './AccountIdentity'
import { Person } from '../model/Person'
import { CampusUtilities } from './CampusUtilities'
import { CampusLiveServices } from './CampusLiveServices'
import { ClassroomScheduleRepository } from '../repository/ClassroomScheduleRepository'
import { ClassroomScheduleParser } from '../model/ClassroomSchedule'
import { LibraryBooksRepository } from '../repository/LibraryBooksRepository'
import { ClassroomPresentation } from './ClassroomPresentation'
import { ClassroomPreference } from './ClassroomPreference'
import { CampusSignal } from './CampusSignal'
import { LocalGpa } from './LocalGpa'

export class CampusPreview {
  items: CampusPreviewItem[] = []
  total: number = -1
  id: string = ''
  value: string = ''
  description: string = ''
  secondary: string = ''
  updatedAt: number = 0
  status: string = 'ready'
  tone: string = ''
  gpa: string = ''
  credits: string = ''
  examCount: number = -1
  gradeCount: number = -1
  calculation: string = ''
}

export interface CampusPreviewSource {
  read(id: string, force: boolean): Promise<CampusPreview>
  cached(id: string): Promise<CampusPreview | undefined>
  publish(row: CampusPreview, owner: string): Promise<void>
}

/** Preview payloads contain summaries only, scoped to account, role and campus. */
export class CampusPreviewStore {
  static readonly REVISION: string = 'campus_preview_revision'
  private static readonly memory: Map<string, CampusPreview> = new Map<string, CampusPreview>()
  static owner(): string {
    return (AppState.getPerson().getStudentId() || 'guest') + ':' + String(AppStorage.get<boolean>(AppState.KEY_IS_LOGGED_IN) !== false) +
      ':' + AcademicAccount.group() + ':' + CampusPreference.current() + ':' + AppLanguage.current()
  }
  static key(id: string, owner: string = CampusPreviewStore.owner()): string {
    return 'campus_preview_' + encodeURIComponent(owner) + '_' + id
  }
  static async cached(id: string): Promise<CampusPreview | undefined> {
    // Independent forum sessions and changing service permissions must not
    // restore a private snapshot before its current owner has been checked.
    if (['evaluation', 'campus_access', 'sports', 'life_code', 'dining', 'electricity'].includes(id)) return undefined
    const key: string = CampusPreviewStore.key(id)
    const remembered: CampusPreview | undefined = CampusPreviewStore.memory.get(key)
    if (remembered !== undefined && (id !== 'academic' || remembered.calculation === 'local-v1') &&
      remembered.updatedAt > 0 && remembered.updatedAt <= Date.now() + 60000 &&
      Date.now() - remembered.updatedAt <= 7 * 86400000) return CampusPreviewStore.copy(remembered)
    if (remembered !== undefined) CampusPreviewStore.memory.delete(key)
    try {
      const raw: string = await PreferencesUtil.getInstance().getString(key, '')
      if (!raw) return undefined
      const row: CampusPreview = JSON.parse(raw) as CampusPreview
      if (id === 'academic' && (row.calculation !== 'local-v1' || typeof row.gpa !== 'string' || typeof row.credits !== 'string')) return undefined
      if (row.id !== id || typeof row.value !== 'string' || typeof row.description !== 'string' ||
        typeof row.secondary !== 'string' || !Number.isFinite(row.updatedAt) || row.updatedAt <= 0 ||
        row.updatedAt > Date.now() + 60000 || Date.now() - row.updatedAt > 7 * 86400000) return undefined
      CampusPreviewStore.remember(key, row)
      return CampusPreviewStore.copy(row)
    } catch (e) { return undefined }
  }
  static async publish(row: CampusPreview, owner: string): Promise<void> {
    if (owner !== CampusPreviewStore.owner()) return
    // These protected previews are already scoped by their live repositories;
    // writing unusable private snapshots to disk was both wasteful and stale.
    if (['evaluation', 'campus_access', 'sports', 'life_code', 'dining', 'electricity'].includes(row.id)) return
    const key: string = CampusPreviewStore.key(row.id, owner)
    const prior: CampusPreview | undefined = CampusPreviewStore.memory.get(key)
    if (prior !== undefined && JSON.stringify(prior) === JSON.stringify(row)) return
    CampusPreviewStore.remember(key, row)
    await PreferencesUtil.getInstance().putString(key, JSON.stringify(row))
    if (owner === CampusPreviewStore.owner()) AppStorage.setOrCreate<number>(CampusPreviewStore.REVISION,
      (AppStorage.get<number>(CampusPreviewStore.REVISION) ?? 0) + 1)
  }
  private static remember(key: string, row: CampusPreview): void {
    CampusPreviewStore.memory.set(key, CampusPreviewStore.copy(row))
    while (CampusPreviewStore.memory.size > 64) {
      const first: string | undefined = CampusPreviewStore.memory.keys().next().value
      if (first !== undefined) CampusPreviewStore.memory.delete(first)
    }
  }
  private static copy(row: CampusPreview): CampusPreview {
    const value = new CampusPreview(); value.id = row.id; value.value = row.value
    value.description = row.description; value.secondary = row.secondary
    value.updatedAt = row.updatedAt; value.status = row.status; value.tone = row.tone || (row.id === 'card' ? CampusSignal.amount(row.value) : ''); value.gpa = row.gpa ?? ''; value.credits = row.credits ?? ''
    if (value.gpa && Number.isFinite(Number(value.gpa))) value.gpa = Number(value.gpa).toFixed(2)
    value.examCount = CampusPreviewStore.academicCount(row, true)
    value.gradeCount = CampusPreviewStore.academicCount(row, false)
    value.calculation = row.calculation ?? ''; value.items = CampusPreviewItem.copy(row.items)
    value.total = Number.isInteger(row.total) && row.total >= 0 ? row.total : -1
    return value
  }
  private static academicCount(row: CampusPreview, exams: boolean): number {
    const count: number = exams ? row.examCount : row.gradeCount
    if (Number.isInteger(count) && count >= 0) return count
    if (row.id !== 'academic') return -1
    // Migrate a previous local summary without another online request. Match
    // its localized template, rather than splitting arbitrary caption text.
    const template: string = AppLanguage.text($r('app.string.campus_academic_summary'))
    const first: number = template.indexOf('{exams}'); const last: number = template.indexOf('{grades}')
    if (first < 0 || last <= first) return -1
    const prefix: string = template.substring(0, first)
    const middle: string = template.substring(first + 7, last)
    const suffix: string = template.substring(last + 8)
    const text: string = row.description
    const separator: number = text.indexOf(middle, prefix.length)
    if (!middle || !text.startsWith(prefix) || !text.endsWith(suffix) || separator < 0) return -1
    const raw: string = exams ? text.substring(prefix.length, separator) :
      text.substring(separator + middle.length, text.length - suffix.length)
    return /^\d+$/.test(raw) && Number.isSafeInteger(Number(raw)) ? Number(raw) : -1
  }
  static greeting(now: Date): Resource {
    return CampusGreeting.resource(now, CampusGreeting.lunar(now))
  }
  static greetingText(now: Date, revision: number): string { return CampusGreeting.text(now, revision) }
}

/** Summary refresh does not open an authentication window for every card.
 * Existing sessions are read directly; the explicit detail page owns renewal. */
export class DefaultCampusPreviewSource implements CampusPreviewSource {
  cached(id: string): Promise<CampusPreview | undefined> {
    if (id !== 'electricity') return CampusPreviewStore.cached(id)
    const summary = CampusLiveServices.cachedElectricityPreview()
    if (summary === undefined) return Promise.resolve(undefined)
    const row = new CampusPreview(); row.id = id; row.value = summary.value
    row.description = summary.description; row.secondary = summary.secondary
    row.updatedAt = summary.updatedAt; row.tone = summary.tone
    return Promise.resolve(row)
  }
  publish(row: CampusPreview, owner: string): Promise<void> { return CampusPreviewStore.publish(row, owner) }
  async read(id: string, force: boolean): Promise<CampusPreview> {
    const capturedPerson: Person = AppState.getPerson()
    // These services apply their own account/session scopes and short live
    // TTLs. Bypass the generic persisted TTL so visitor counts remain current
    // and an independent forum logout immediately invalidates DanKe previews.
    if (CampusUtilities.supported(id) || ['developer_notice', 'dining', 'library', 'electricity'].includes(id)) {
      const summary = CampusUtilities.supported(id) ? await CampusUtilities.preview(id, force) : await CampusLiveServices.preview(id, force)
      const preview: CampusPreview = new CampusPreview()
      preview.id = id; preview.value = summary.value; preview.description = summary.description
      preview.secondary = summary.secondary; preview.updatedAt = summary.updatedAt; preview.status = summary.status; preview.tone = summary.tone
      preview.items = CampusPreviewItem.copy(summary.items)
      return preview
    }
    const cached: CampusPreview | undefined = await CampusPreviewStore.cached(id)
    // Today's course summary depends on local edits, teaching dates and the day
    // as well as the official snapshot. Recompute it from local storage without
    // opening a network request or masking new manual courses behind this TTL.
    if (id !== 'timetable' && id !== 'empty_classroom' && id !== 'library_books' && !force && cached !== undefined && Date.now() - cached.updatedAt < 5 * 60000) {
      if (id === 'card') AccountIdentity.publishName(capturedPerson, cached.secondary)
      return cached
    }
    const row: CampusPreview = new CampusPreview()
    row.id = id
    const repo: FduRepository = FduRepository.getInstance()
    if (id === 'empty_classroom') {
      const now = new Date(); const day = ClassroomPresentation.day(now)
      const slot = ClassroomPresentation.currentSlot(day, now)
      const campus = CampusPreference.current(); const building = await ClassroomPreference.building(campus)
      const label = AppLanguage.text($r('app.string.campus_classroom_period_note')) + '\n' + ClassroomPresentation.previewLabel(building, day)
      if (!force && cached !== undefined && cached.description === label && Date.now() - cached.updatedAt < 60000) return cached
      if (slot === 0) {
        row.value = AppLanguage.text($r('app.string.campus_preview_open')); row.status = 'pending'
        row.description = AppLanguage.text($r('app.string.campus_classroom_outside_period')) + '\n' + ClassroomPresentation.previewLabel(building, day)
        row.secondary = AppLanguage.campus(campus); row.updatedAt = Date.now(); return row
      }
      // A passive preview uses only an existing WebVPN cookie. It never starts
      // authentication; without one the direct campus endpoint remains usable.
      const rooms = ClassroomScheduleParser.preview(await ClassroomScheduleRepository.read(building, day, force, false))
      row.items = CampusCardInformation.classrooms(rooms, slot)
      row.total = CampusCardInformation.classroomTotal(rooms, slot)
      row.value = AppLanguage.text($r('app.string.campus_classroom_count')).replace('{count}',
        String(rooms.filter(room => ClassroomPresentation.slotFree(room, slot) === true).length))
      row.tone = CampusSignal.classrooms(rooms.filter(room => ClassroomPresentation.slotFree(room, slot) === true).length,
        rooms.filter(room => ClassroomPresentation.slotFree(room, slot) !== undefined).length)
      row.description = label; row.secondary = AppLanguage.campus(campus)
    } else if (id === 'library_books') {
      const pinned = await LibraryBooksRepository.pinned()
      row.value = pinned.length > 0 ? AppLanguage.text($r('app.string.books_pinned_count'), 0, pinned.length) : AppLanguage.text($r('app.string.books_search_short'))
      row.description = AppLanguage.text($r('app.string.books_preview_hint'))
      row.secondary = pinned[0]?.title ?? AppLanguage.text($r('app.string.books_public_hint'))
    } else if (id === 'academic' && AcademicAccount.group() !== 'unknown' && repo.cookiesFor(CampusService.GPA)) {
      const graduate: boolean = AcademicAccount.isGraduate()
      const semester = graduate ? undefined : await repo.getCurrentSemester().catch(() => undefined)
      // Independent summaries share one fan-out; a missing semester list or
      // exam endpoint must not erase available local grade calculations.
      const gradeTask = repo.getCourseGrades(semester?.id ?? '').catch(() => undefined)
      const examTask = graduate ? Promise.resolve(undefined) : repo.getExamSchedules().catch(() => undefined)
      const grades = await gradeTask; const exams = await examTask
      const local = LocalGpa.calculate(grades ?? [], graduate)
      row.gpa = local.gpa; row.credits = local.credits; row.calculation = 'local-v1'
      row.examCount = exams === undefined ? -1 : exams.length
      row.gradeCount = grades === undefined ? -1 : grades.length
      row.value = local.gpa ? 'GPA ' + local.gpa : AppLanguage.text($r('app.string.academic_my_gpa_unavailable'))
      row.description = AppLanguage.text($r('app.string.campus_academic_summary')).replace('{exams}', exams === undefined ? '—' : String(exams.length))
        .replace('{grades}', grades === undefined ? '—' : String(grades.length))
      row.secondary = semester?.name ?? AppLanguage.text($r('app.string.graduate_scores_note'))
    } else if (id === 'announcement') {
      const notices = await repo.getAnnouncements()
      row.value = notices[0]?.title ?? AppLanguage.text($r('app.string.campus_no_notices'))
      row.description = notices.slice(1, 6).map(item => item.title).join('\n')
      row.secondary = notices[0]?.publishTime ?? ''
    } else if (id === 'timetable') {
      const snapshot = await TimetableRepository.cached()
      const semester: SemesterInfo = snapshot?.semester ?? { id: 'local', name: '', startDate: AcademicCalendar.start() }
      const edits = await TimetableRepository.edits(semester)
      const displayed = TimetableSchedule.display(snapshot?.courses ?? [], edits)
      // A guest or an account whose official import failed can still maintain
      // its local semester. With no available data, keep the explicit entry
      // prompt rather than claiming that the official timetable is empty.
      if (snapshot === undefined && displayed.length === 0) return DefaultCampusPreviewSource.pending(id)
      const now: Date = new Date()
      const week = TeachingCalendar.week(AcademicCalendar.manual() ? AcademicCalendar.start() :
        semester.startDate || AcademicCalendar.start(), now)
      const courses = displayed.filter(course =>
        course.weekday === (now.getDay() || 7) && (week <= 0 || course.weekIndexes.includes(week)))
        .sort((a, b) => a.startUnit - b.startUnit)
      row.value = courses[0]?.name ?? AppLanguage.text($r('app.string.ui_no_classes_today'))
      row.description = courses.slice(0, 3).map(course => String(course.startUnit) + '–' + String(course.endUnit) +
        ' · ' + course.name + (course.room ? ' · ' + course.room : '')).join('\n')
      row.secondary = semester.name
      row.updatedAt = snapshot?.updatedAt ?? now.getTime()
    } else if (id === 'card' && repo.cookiesFor(CampusService.ECARD)) {
      const card = CardRepository.getInstance()
      card.setSession(repo.cookiesFor(CampusService.ECARD))
      if (force) card.invalidate()
      const balance = await card.getCardInfo(-1)
      row.tone = CampusSignal.amount(balance.cash)
      row.value = CardPresentation.balance(balance.cash)
      row.description = AppLanguage.text($r('app.string.ui_card_balance'))
      row.secondary = balance.name
      AccountIdentity.publishName(capturedPerson, balance.name)
    } else if (id === 'bus' && repo.cookiesFor(CampusService.BUS)) {
      const buses = ZlappRepository.getInstance()
      buses.setSession(repo.cookiesFor(CampusService.BUS))
      const now: Date = new Date()
      const start: string = await CampusFilterPreference.read('bus_start')
      const end: string = await CampusFilterPreference.read('bus_end', start === '江湾' ? '邯郸' : '江湾')
      row.items = CampusCardInformation.buses(await buses.getBusSchedules(now.getDay() === 0 || now.getDay() === 6), start, end, now)
      row.value = row.items[0].value || AppLanguage.text($r('app.string.bus_empty'))
      row.description = start + ' → ' + end
      row.secondary = AppLanguage.text(now.getDay() === 0 || now.getDay() === 6 ? $r('app.string.bus_holiday') : $r('app.string.bus_weekday'))
    } else { return cached ?? DefaultCampusPreviewSource.pending(id) }
    if (row.updatedAt === 0) row.updatedAt = Date.now()
    return row
  }

  private static pending(id: string): CampusPreview {
    const row: CampusPreview = new CampusPreview()
    row.id = id; row.status = 'pending'
    row.value = AppLanguage.text($r('app.string.campus_preview_open'))
    row.description = AppLanguage.text(CampusLayout.hint(id))
    return row
  }
}

export class CampusDetailParams {
  feature: string = 'announcement'
  constructor(feature: string) { this.feature = feature }
}
