import { ReadableText } from '../common/ReadableText'
import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice } from '../components/ErrorNotice'
import { settleScrollTouch } from '../common/ScrollTouch'
import { MoreGlyph } from '../components/MoreGlyph'
import { getSymbolIcon } from '../common/DanXiIcons'
import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { AppState } from '../common/AppState'
import { AppLanguage } from '../common/AppLanguage'
import { AcademicCalendar } from '../common/AcademicCalendar'
import { AcademicAccount } from '../common/AcademicAccount'
import { Constant } from '../common/Constant'
import { ThemeColors } from '../common/Theme'
import { Course, SemesterInfo, TimetableHelper } from '../model/Academic'
import { ScheduleEdits, TimetableSchedule } from '../model/TimetableSchedule'
import { CourseFormValues, CourseFormIssue, TimetableCourseForm } from '../model/TimetableCourseForm'
import { TeachingCalendar } from '../model/TeachingCalendar'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { TimetableRepository, ScheduleSnapshot } from '../repository/TimetableRepository'
import { FduRepository } from '../repository/FduRepository'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { FloatingSurface } from '../components/FloatingSurface'
import { CalendarSettings } from '../components/CalendarSettings'
import { TimetableSource } from '../common/TimetableSource'
import { TopFade } from '../components/TopFade'
import { TimetableCalendarSheet } from '../components/TimetableCalendarSheet'
import { PeriodTimeAxis } from '../components/PeriodTimeAxis'
import { ScheduleTimelineGrid } from '../components/ScheduleTimelineGrid'

interface TimetableNotices {
  error: string
  verification: boolean
  dateMissing: boolean
  outsideTerm: boolean
  historical: boolean
  empty: boolean
  guest: boolean
}

@Component
export struct TimetablePage {
  private optionsTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private showSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  source: TimetableSource | undefined = undefined
  private touchScroller: Scroller = new Scroller()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink('main_active_tab') @Watch('activate') activeTab: number = 0
  @StorageLink('main_route_visible') @Watch('activate') mainVisible: boolean = true
  @StorageLink('app_foreground') @Watch('activate') foreground: boolean = true
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink('app_person') @Watch('accountChanged') personJson: string = ''
  @StorageLink(AcademicCalendar.KEY_REVISION) @Watch('dateChanged') calendarRevision: number = 0
  @State private semester: SemesterInfo = { id: 'local', name: '', startDate: '' }
  @State private semesters: SemesterInfo[] = []
  @State private official: Course[] = []
  @State private courses: Course[] = []
  @State private week: number = 1
  @State private agenda: boolean = false
  @State private optionsVisible: boolean = false
  @State private refreshing: boolean = false
  @State private pullOffset: number = 0
  @State private headerHeight: number = 0
  @State private noticeHeight: number = 0
  @State private notices: TimetableNotices | undefined = undefined
  @State private loading: boolean = false
  @State private error: string = ''
  @State private updatedAt: number = 0
  @State private showCalendar: boolean = false
  @State private showDetail: boolean = false
  @State private showEditor: boolean = false
  @State private showSheet: boolean = false
  @State private selected: Course = { id: '', code: '', name: '', teachers: [], room: '', weekday: 1, startUnit: 1, endUnit: 2, weekIndexes: [1] }
  @State private courseName: string = ''
  @State private teacher: string = ''
  @State private location: string = ''
  @State private code: string = ''
  @State private weekday: number = 0
  @State private firstUnit: string = ''
  @State private lastUnit: string = ''
  @State private weeks: string = ''
  @State private editorError: string = ''
  @State private saving: boolean = false
  @State private exporting: boolean = false
  @State private showExport: boolean = false
  @State private historicalDiary: boolean = false
  private edits: ScheduleEdits = { added: [], hidden: [] }
  private loaded: boolean = false
  private epoch: number = 0
  private editingKey: string = ''
  private active: boolean = false
  private accountScope: string = ''
  private resumeVerified: boolean = false
  private dayNames: Resource[] = [$r('app.string.weekday_mon'), $r('app.string.weekday_tue'),
    $r('app.string.weekday_wed'), $r('app.string.weekday_thu'), $r('app.string.weekday_fri'),
    $r('app.string.weekday_sat'), $r('app.string.weekday_sun')]

  private headerExtent(): number {
    return this.headerHeight > 0 ? this.headerHeight : px2vp(this.topPx) + 96
  }

  private noticeOffset(): number { return this.headerExtent() + 20 }
  private bodyOffset(): number { return this.noticeOffset() + this.noticeHeight }

  private publishNotices(): void {
    const dateMissing: boolean = !TeachingCalendar.validMonday(this.start())
    const currentWeek: number = dateMissing ? 0 : TeachingCalendar.week(this.start())
    this.notices = { error: this.error, verification: !!this.error && this.verificationRequired(), dateMissing: dateMissing,
      outsideTerm: !dateMissing && (currentWeek < 1 || currentWeek > this.maxWeek()), historical: this.historicalDiary,
      empty: !this.courses.length, guest: !AppState.isLoggedIn() }
  }

  aboutToAppear(): void {
    this.active = true; this.accountScope = this.currentAccountScope()
    this.activate()
  }
  aboutToDisappear(): void {
    this.active = false; this.epoch++; this.loading = false; this.refreshing = false
  }

  activate(): void {
    if (!this.active || !this.foreground || this.activeTab !== 1 || !this.mainVisible || this.loading) return
    if (this.resumeVerified) {
      this.resumeVerified = false
      this.load(this.semester.id !== 'local' ? this.semester : undefined, true)
    } else if (!this.loaded) this.load()
  }
  private currentAccountScope(): string {
    const person = AppState.getPerson()
    return person.getStudentId() + ':' + person.getToken() + ':' + AcademicAccount.group()
  }
  accountChanged(): void {
    const scope: string = this.currentAccountScope()
    if (scope === this.accountScope) return
    this.accountScope = scope
    this.resumeVerified = false
    this.epoch++; this.loaded = false; this.loading = false
    this.notices = undefined
    this.official = []; this.courses = []; this.semesters = []; this.updatedAt = 0; this.error = ''; this.historicalDiary = false
    this.edits = { added: [], hidden: [] }; this.showEditor = false; this.showDetail = false; this.showSheet = false; this.saving = false
    this.semester = { id: 'local', name: '', startDate: '' }; this.activate()
  }
  dateChanged(): void {
    // Invalidate completions for the preceding date before selecting a term.
    this.epoch++; this.loaded = false; this.loading = false; this.refreshing = false
    this.notices = undefined
    this.official = []; this.courses = []; this.edits = { added: [], hidden: [] }
    this.updatedAt = 0; this.error = ''; this.historicalDiary = false; this.semester = { id: 'local', name: '', startDate: AcademicCalendar.start() }
    if (AppState.isLoggedIn() && AcademicAccount.isGraduate()) {
      const monday: string = this.semester.startDate
      this.semester = { id: TimetableRepository.graduateTermId(monday ? new Date(monday + 'T00:00:00') : new Date()), name: '', startDate: monday }
    }
    this.week = 1; this.activate()
  }
  private start(): string { return AcademicCalendar.start() || this.semester.startDate }
  private maxWeek(): number { return Math.max(18, ...this.courses.map((course: Course) => Math.max(...course.weekIndexes))) }
  private today(): void {
    const current = TeachingCalendar.week(this.start())
    this.week = current > this.maxWeek() ? 1 : Math.max(1, current)
  }
  private weekLabel(): string { return AppLanguage.text($r('app.string.timetable_week'), this.languageRevision).replace('{week}', String(this.week)) }
  private dayLabel(day: number): string { return AppLanguage.text(this.dayNames[day - 1], this.languageRevision) }
  private dayDate(day: number): string {
    if (!TeachingCalendar.validMonday(this.start())) return ''
    const date = TimetableSchedule.day(this.start(), this.week, day)
    return String(date.getMonth() + 1) + '/' + String(date.getDate())
  }
  private dayNumber(day: number): string {
    return TeachingCalendar.validMonday(this.start()) ? String(TimetableSchedule.day(this.start(), this.week, day).getDate()) : ''
  }
  private monthLabel(): string {
    if (!TeachingCalendar.validMonday(this.start())) return ''
    const first: Date = TimetableSchedule.day(this.start(), this.week, 1)
    const last: Date = TimetableSchedule.day(this.start(), this.week, 7)
    const format: string = AppLanguage.text($r('app.string.timetable_month_heading'), this.languageRevision)
    const firstLabel: string = format.replace('{year}', String(first.getFullYear())).replace('{month}', String(first.getMonth() + 1))
    const lastLabel: string = format.replace('{year}', String(last.getFullYear())).replace('{month}', String(last.getMonth() + 1))
    return firstLabel === lastLabel ? firstLabel : firstLabel + ' – ' + lastLabel
  }
  private isToday(day: number): boolean {
    if (!TeachingCalendar.validMonday(this.start())) return false
    const date: Date = TimetableSchedule.day(this.start(), this.week, day), now: Date = new Date()
    return date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
  }
  private courseTint(course: Course): string { return (this.darkMode ? '#38' : '#20') + TimetableSchedule.color(course).slice(1) }
  private inWeek(day: number): Course[] {
    return this.courses.filter((course: Course) => course.weekday === day && course.weekIndexes.includes(this.week))
      .sort((a: Course, b: Course) => a.startUnit - b.startUnit)
  }
  private conflicts(course: Course): Course[] {
    return this.inWeek(course.weekday).filter((row: Course) => row.startUnit <= course.endUnit && row.endUnit >= course.startUnit)
  }
  private async apply(snapshot: ScheduleSnapshot, epoch: number): Promise<void> {
    const edits = await TimetableRepository.edits(snapshot.semester)
    if (epoch !== this.epoch) return
    this.semester = snapshot.semester; this.official = snapshot.courses; this.updatedAt = snapshot.updatedAt
    this.historicalDiary = snapshot.historicalDiary === true
    this.edits = edits
    this.courses = TimetableSchedule.display(this.official, this.edits)
    this.today()
  }

  private async load(selected?: SemesterInfo, force: boolean = false): Promise<void> {
    if (!this.active || !this.foreground || !this.mainVisible || this.activeTab !== 1) { this.refreshing = false; return }
    if (this.loading) { this.refreshing = false; return }
    this.loading = true; this.error = ''; const epoch = ++this.epoch
    try {
      if (!this.loaded && !selected) {
        const cached = this.source !== undefined ? await this.source.cached() : await TimetableRepository.cached()
        if (epoch !== this.epoch) return
        if (cached) await this.apply(cached, epoch)
        else {
          if (AcademicAccount.isGraduate() && this.semester.id === 'local') {
            const monday: string = AcademicCalendar.start()
            this.semester = { id: TimetableRepository.graduateTermId(monday ? new Date(monday + 'T00:00:00') : new Date()),
              name: '', startDate: monday }
          }
          this.edits = await TimetableRepository.edits(this.semester)
          if (epoch !== this.epoch) return
          this.courses = TimetableSchedule.display([], this.edits)
        }
        if (!this.active || !this.foreground || !this.mainVisible || this.activeTab !== 1 || epoch !== this.epoch) return
      }
      if (AppState.isLoggedIn()) {
        const snapshot = this.source !== undefined ? await this.source.load(selected, force) : await TimetableRepository.load(selected, force)
        if (epoch !== this.epoch) return
        await this.apply(snapshot, epoch)
        if (!this.active || !this.foreground || !this.mainVisible || this.activeTab !== 1 || epoch !== this.epoch) return
        if (!AcademicAccount.isGraduate()) {
          const semesters = this.source !== undefined ? await this.source.semesters() : await TimetableRepository.semesters()
          if (epoch !== this.epoch) return
          this.semesters = semesters
        }
      } else {
        this.semester = { id: 'local', name: '', startDate: AcademicCalendar.start() }; this.today()
      }
      if (epoch === this.epoch) this.loaded = true
    } catch (e) {
      if (epoch === this.epoch) this.error = ErrorDiagnostics.message(e as Object)
      if (epoch === this.epoch) this.loaded = true
    } finally { if (epoch === this.epoch) { this.loading = false; this.refreshing = false; this.publishNotices() } }
  }

  private async selectSemester(semester: SemesterInfo): Promise<void> {
    if (TeachingCalendar.validMonday(semester.startDate)) {
      if (AcademicCalendar.start() !== semester.startDate) await AcademicCalendar.setManual(semester.startDate)
      else await this.load(semester)
    } else await this.load(semester)
  }

  private moveWeek(offset: number): void {
    this.getUIContext().animateTo({ duration: 360, curve: Curve.Friction }, () => {
      this.week = Math.max(1, Math.min(this.maxWeek(), this.week + offset))
    })
  }

  private verificationRequired(): boolean {
    const repository: FduRepository = FduRepository.getInstance()
    return AppState.isLoggedIn() && repository.needsVerification(repository.academicService('timetable'))
  }

  private async verifyAndReload(): Promise<void> {
    if (!this.active || !this.foreground || !this.mainVisible || this.activeTab !== 1 || this.loading) return
    this.loading = true; const epoch: number = this.epoch
    try {
      const repository: FduRepository = FduRepository.getInstance()
      await repository.verifyService(repository.academicService('timetable'))
      if (!this.active || epoch !== this.epoch) return
      if (!this.foreground || !this.mainVisible || this.activeTab !== 1) { this.resumeVerified = true; return }
      this.loading = false
      await this.load(this.semester.id !== 'local' ? this.semester : undefined, true)
    } catch (e) {
      if (this.active && epoch === this.epoch) this.error = ErrorDiagnostics.message(e as Object)
    } finally { if (epoch === this.epoch) { this.loading = false; this.refreshing = false; this.publishNotices(); if (this.resumeVerified) this.activate() } }
  }

  private manualReload(): void {
    if (this.error && this.verificationRequired()) this.verifyAndReload()
    else this.load(this.semester.id !== 'local' ? this.semester : undefined, true)
  }

  private edit(course?: Course): void {
    if (this.saving) return
    this.openSheet(() => { this.prepareEditor(course) })
  }

  private openSheet(action: () => void): void {
    this.showSheetTransition.open(() => {
      if (!this.active) return
      action(); this.showSheet = true
    }, () => this.getUIContext())
  }

  private prepareEditor(course?: Course): void {
    this.showDetail = false; this.showCalendar = false; this.showExport = false
    this.editingKey = course ? TimetableSchedule.key(course) : ''
    const draft = TimetableCourseForm.draft(course)
    this.courseName = draft.name; this.teacher = draft.teacher
    this.location = draft.location; this.code = draft.code
    this.weekday = draft.weekday; this.firstUnit = draft.firstUnit
    this.lastUnit = draft.lastUnit; this.weeks = draft.weeks
    this.editorError = ''; this.showEditor = true
  }

  private formValues(): CourseFormValues {
    return { name: this.courseName, teacher: this.teacher, location: this.location, code: this.code,
      weekday: this.weekday, firstUnit: this.firstUnit, lastUnit: this.lastUnit, weeks: this.weeks }
  }

  private formError(issue: CourseFormIssue): Resource {
    switch (issue) {
      case CourseFormIssue.NAME: return $r('app.string.timetable_editor_error_name')
      case CourseFormIssue.WEEKDAY: return $r('app.string.timetable_editor_error_weekday')
      case CourseFormIssue.FIRST_UNIT: return $r('app.string.timetable_editor_error_first_unit')
      case CourseFormIssue.LAST_UNIT: return $r('app.string.timetable_editor_error_last_unit')
      case CourseFormIssue.UNIT_ORDER: return $r('app.string.timetable_editor_error_order')
      case CourseFormIssue.WEEKS: return $r('app.string.timetable_editor_error_weeks')
      default: return $r('app.string.timetable_invalid')
    }
  }

  private async saveCourse(): Promise<void> {
    if (this.saving) return
    const values = this.formValues()
    const issue = TimetableCourseForm.issue(values)
    const course = TimetableCourseForm.course(values, 'local-' + String(Date.now()))
    if (!course) {
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.editorError = AppLanguage.text(this.formError(issue), this.languageRevision)
      })
      return
    }
    this.saving = true
    this.editorError = ''
    const epoch = this.epoch
    const owner = TimetableRepository.owner()
    const semester = this.semester
    const termKey = TimetableRepository.termKey(semester)
    const draft: ScheduleEdits = { added: this.edits.added.filter((row: Course) => TimetableSchedule.key(row) !== this.editingKey),
      hidden: this.edits.hidden.slice() }
    if (this.editingKey && this.official.some((row: Course) => TimetableSchedule.key(row) === this.editingKey) &&
      !draft.hidden.includes(this.editingKey)) draft.hidden.push(this.editingKey)
    draft.added.push(course)
    try {
      await TimetableRepository.saveEdits(semester, draft)
      if (epoch !== this.epoch || owner !== TimetableRepository.owner() || termKey !== TimetableRepository.termKey(this.semester)) return
      this.edits = draft; this.courses = TimetableSchedule.display(this.official, draft); this.showEditor = false; this.showSheet = false
      this.publishNotices()
    } catch (e) {
      if (epoch === this.epoch && owner === TimetableRepository.owner() && termKey === TimetableRepository.termKey(this.semester)) {
        this.editorError = AppLanguage.text($r('app.string.timetable_save_failed'), this.languageRevision)
      }
    } finally { if (epoch === this.epoch && owner === TimetableRepository.owner()) this.saving = false }
  }

  private async removeCourse(): Promise<void> {
    if (this.saving) return
    this.saving = true
    const epoch: number = this.epoch
    const owner: string = TimetableRepository.owner()
    const semester: SemesterInfo = this.semester
    const termKey: string = TimetableRepository.termKey(semester)
    const key = TimetableSchedule.key(this.selected)
    const draft: ScheduleEdits = { added: this.edits.added.filter((row: Course) => TimetableSchedule.key(row) !== key), hidden: this.edits.hidden.slice() }
    if (this.official.some((row: Course) => TimetableSchedule.key(row) === key) && !draft.hidden.includes(key)) draft.hidden.push(key)
    try {
      await TimetableRepository.saveEdits(semester, draft)
      if (epoch !== this.epoch || owner !== TimetableRepository.owner() || termKey !== TimetableRepository.termKey(this.semester)) return
      this.edits = draft
      this.courses = TimetableSchedule.display(this.official, draft); this.showDetail = false; this.showSheet = false
      this.publishNotices()
    } catch (e) {
      if (epoch === this.epoch && owner === TimetableRepository.owner()) DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.timetable_save_failed')))
    } finally { if (epoch === this.epoch && owner === TimetableRepository.owner()) this.saving = false }
  }

  private async restoreOfficial(): Promise<void> {
    if (this.saving) return
    this.saving = true
    const epoch: number = this.epoch
    const owner: string = TimetableRepository.owner()
    const semester: SemesterInfo = this.semester
    const termKey: string = TimetableRepository.termKey(semester)
    const draft: ScheduleEdits = { added: this.edits.added, hidden: [] }
    try {
      await TimetableRepository.saveEdits(semester, draft)
      if (epoch !== this.epoch || owner !== TimetableRepository.owner() || termKey !== TimetableRepository.termKey(this.semester)) return
      this.edits = draft; this.courses = TimetableSchedule.display(this.official, draft)
      this.publishNotices()
    } catch (e) {
      if (epoch === this.epoch && owner === TimetableRepository.owner()) DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.timetable_save_failed')))
    } finally { if (epoch === this.epoch && owner === TimetableRepository.owner()) this.saving = false }
  }

  private exportCalendar(): void {
    if (this.exporting || this.showSheet) return
    this.openSheet(() => {
      if (!TeachingCalendar.validMonday(this.start())) { this.showCalendar = true; return }
      this.showEditor = false; this.showDetail = false; this.showCalendar = false; this.showExport = true
    })
  }

  @Builder
  LocalNote() {
    Text(ReadableText.resource($r('app.string.timetable_local_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).padding(16).lineBreakStrategy(LineBreakStrategy.GREEDY)
  }

  @Builder
  Options() {
    Menu() {
      MenuItem({ content: $r('app.string.timetable_add'), symbolStartIcon: this.menuIcon($r('sys.symbol.plus')) }).onClick(() => { this.edit() })
      MenuItem({ content: $r('app.string.ui_reload'), symbolStartIcon: this.menuIcon(getSymbolIcon('refresh')) }).enabled(!this.loading).onClick(() => { this.manualReload() })
      MenuItem({ content: $r('app.string.timetable_semester_date'), symbolStartIcon: this.menuIcon(getSymbolIcon('timetable')) }).onClick(() => { this.openSheet(() => { this.showCalendar = true }) })
      MenuItem({ content: $r('app.string.timetable_export'), symbolStartIcon: this.menuIcon(getSymbolIcon('timetable')) }).enabled(this.courses.length > 0 && !this.exporting).onClick(() => { this.exportCalendar() })
      MenuItem({ content: $r('app.string.timetable_restore'), symbolStartIcon: this.menuIcon($r('sys.symbol.arrowshape_turn_up_left')) }).enabled(this.edits.hidden.length > 0).onClick(() => { this.restoreOfficial() })
      this.LocalNote()
    }.width(300)
  }

  private menuIcon(resource: Resource): SymbolGlyphModifier {
    const icon: SymbolGlyphModifier = new SymbolGlyphModifier(resource)
    icon.fontSize(19).fontColor([ThemeColors.primary])
    return icon
  }

  @Builder
  WeekChoices() {
    Menu() {
      ForEach(Array.from({ length: this.maxWeek() }, (_value: Object, index: number) => index + 1), (week: number) => {
        MenuItem({ content: AppLanguage.text($r('app.string.timetable_week'), this.languageRevision).replace('{week}', String(week)) })
          .selected(this.week === week).selectIcon(true).onClick(() => { this.moveWeek(week - this.week) })
      })
    }
  }

  @Builder
  SemesterChoices() {
    Menu() {
      ForEach(this.semesters, (semester: SemesterInfo) => {
        MenuItem({ content: semester.name }).selected(this.semester.id === semester.id).selectIcon(true)
          .onClick(() => { this.selectSemester(semester) })
      })
    }.width(280)
  }

  @Builder
  MoreButton() {
    FloatingActionButton({ label: $r('app.string.detail_more'), icon: 'more', controlId: 'timetable-options', controlHeight: 48,
      onAction: () => { this.optionsTransition.open(() => {
        if (this.active) this.optionsVisible = true
      }, () => this.getUIContext()) } }).width(48)
      .bindMenu(this.optionsVisible, this.Options, this.optionsTransition.menuOptions(this.optionsVisible, { onDisappear: () => { this.optionsVisible = false } }))
  }

  @Builder
  Header() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text($r('app.string.ui_timetable')).fontSize(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        FloatingActionButton({ label: $r('app.string.timetable_today'), onAction: () => { this.today() } }).width(74)
        this.MoreButton()
      }
      Row({ space: 8 }) {
        FloatingActionButton({ label: $r('app.string.timetable_previous_week'), icon: 'previous', zeroContentPadding: true, controlId: 'timetable-previous-week', actionEnabled: this.week > 1, onAction: () => { this.moveWeek(-1) } }).width(40)
        Row() { Text(this.weekLabel()).fontSize(14).fontColor(ThemeColors.textPrimary) }
          .layoutWeight(1).height(40).justifyContent(FlexAlign.Center).bindMenu(this.WeekChoices)
        FloatingActionButton({ label: $r('app.string.timetable_next_week'), icon: 'forward', zeroContentPadding: true, controlId: 'timetable-next-week', actionEnabled: this.week < this.maxWeek(), onAction: () => { this.moveWeek(1) } }).width(40)
        FloatingActionButton({ label: this.agenda ? $r('app.string.timetable_week_view') : $r('app.string.timetable_agenda'),
          onAction: () => { this.getUIContext().animateTo({ duration: 360, curve: Curve.Friction }, () => { this.agenda = !this.agenda }) } }).width(80)
      }
      if (this.semester.name) {
        Row({ space: 6 }) {
          Text(this.semester.name).fontSize(12).fontColor(ThemeColors.textSecondary)
          if (this.semesters.length > 1) {
            SymbolGlyph(getSymbolIcon('expand')).fontSize(14).fontColor([ThemeColors.textSecondary])
          }
        }.height(28).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .id('timetable-semester-selector').bindMenu(this.SemesterChoices)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }
    }.padding({ left: 16, right: 16, top: px2vp(this.topPx) + 8, bottom: 4 }).width('100%')
      .onSizeChange((oldValue: SizeOptions, newValue: SizeOptions) => {
        const height: number = Number(newValue.height)
        if (Number.isFinite(height) && height > 0 && height !== this.headerHeight) this.headerHeight = height
      })
  }

  @Builder
  DayCell(day: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      ScheduleTimelineGrid({ periodCount: 15, rowHeight: 58 })
      ForEach(this.inWeek(day), (course: Course) => {
        Column({ space: 3 }) {
          Text(course.name).fontSize(11).lineHeight(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
            .maxLines(Math.max(1, Math.min(6, Math.floor(((course.endUnit - course.startUnit + 1) * 58 - 28) / 16))))
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (course.room) Text(course.room).fontSize(10).lineHeight(14).fontColor(ThemeColors.textSecondary)
            .maxLines(course.endUnit > course.startUnit ? 2 : 1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start).padding({ left: 6, right: 4, top: 6, bottom: 4 })
          .width(String(100 / TimetableSchedule.laneCount(this.inWeek(day))) + '%')
          .height((course.endUnit - course.startUnit + 1) * 58 - 4).borderRadius(6).backgroundColor(this.courseTint(course))
          .border({ width: { left: 2 }, color: TimetableSchedule.color(course) })
          .position({ x: String(TimetableSchedule.lane(course, this.inWeek(day)) * 100 / TimetableSchedule.laneCount(this.inWeek(day))) + '%',
            y: (course.startUnit - 1) * 58 + 2 })
          .id('timetable-event-' + course.id).clip(true)
          .onClick(() => { this.openSheet(() => { this.selected = course; this.showDetail = true; this.showEditor = false }) })
          .accessibilityText(course.name + ' ' + course.room + ' ' + String(course.startUnit) + '-' + String(course.endUnit))
      }, (course: Course) => TimetableSchedule.key(course))
    }.height(15 * 58).layoutWeight(1)
  }

  @Builder
  WeekGrid() {
    Column({ space: 10 }) {
      if (this.monthLabel()) {
        Text(this.monthLabel()).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          .width('100%').padding({ left: 4 }).id('timetable-month')
      }
      Row() {
        Text($r('app.string.timetable_period_times')).width(52).height(66).fontSize(10).lineHeight(15)
          .fontColor(ThemeColors.textSecondary).textAlign(TextAlign.Center)
        ForEach(TimetableSchedule.DAYS, (day: number) => {
          Column({ space: 6 }) {
            Text(this.dayLabel(day)).fontSize(12).fontColor(day > 5 ? ThemeColors.textHint : ThemeColors.textSecondary)
            Text(this.dayNumber(day)).fontSize(19).fontWeight(FontWeight.Medium)
              .fontColor(this.isToday(day) ? Color.White : ThemeColors.textPrimary)
              .width(36).height(36).textAlign(TextAlign.Center).borderRadius(18)
              .backgroundColor(this.isToday(day) ? $r('app.color.calendar_today') : Color.Transparent)
          }.layoutWeight(1).height(66).justifyContent(FlexAlign.Center).id('timetable-day-' + day)
            .accessibilityText(this.dayLabel(day) + ' ' + this.dayDate(day))
        }, (day: number): string => String(day))
      }.width('100%')
      Row({ space: 0 }) {
        PeriodTimeAxis({ periodCount: 15, rowHeight: 58, axisWidth: 52 })
        ForEach(TimetableSchedule.DAYS, (day: number) => { this.DayCell(day) })
      }.width('100%').alignItems(VerticalAlign.Top).backgroundColor($r('app.color.surface_fallback')).borderRadius(20).clip(true)
    }.width('100%')
  }

  @Builder
  Agenda() {
    ForEach(TimetableSchedule.DAYS, (day: number) => {
      Text(this.dayLabel(day) + ' ' + this.dayDate(day)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).margin({ top: 16, bottom: 8 })
      if (!this.inWeek(day).length) { Text($r('app.string.timetable_no_class_day')).fontSize(13).fontColor(ThemeColors.textSecondary).padding(12) }
      ForEach(this.inWeek(day), (course: Course) => {
        Row({ space: 12 }) {
          Column().width(4).height(56).borderRadius(2).backgroundColor(TimetableSchedule.color(course))
          Column({ space: 5 }) {
            Text(course.name).fontSize(16).fontColor(ThemeColors.textPrimary)
            Text(TimetableHelper.getSlotStartTime(course.startUnit) + ' – ' + TimetableSchedule.endTime(course.endUnit) +
              '  ' + course.room).fontSize(12).fontColor(ThemeColors.textSecondary)
            Text(course.teachers.join(' / ')).fontSize(12).fontColor(ThemeColors.textSecondary)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%').padding(12).backgroundColor($r('app.color.surface_fallback')).borderRadius(16).margin({ bottom: 8 })
          .onClick(() => { this.openSheet(() => { this.selected = course; this.showDetail = true; this.showEditor = false }) })
      }, (course: Course) => TimetableSchedule.key(course))
    })
  }

  @Builder
  Details() {
    Column({ space: 14 }) {
      Text(this.selected.name).fontSize(22).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      if (this.selected.teachers.length) Text(this.selected.teachers.join(' / ')).fontSize(15).fontColor(ThemeColors.textSecondary)
      if (this.selected.room) Text(this.selected.room).fontSize(15).fontColor(ThemeColors.textSecondary)
      if (this.selected.code) Text(this.selected.code).fontSize(13).fontColor(ThemeColors.textSecondary)
      Text(this.dayLabel(this.selected.weekday) + ' · ' + TimetableHelper.getSlotStartTime(this.selected.startUnit) + ' – ' +
        TimetableSchedule.endTime(this.selected.endUnit)).fontSize(15).fontColor(ThemeColors.textPrimary)
      Text(AppLanguage.text($r('app.string.timetable_weeks'), this.languageRevision) + ' ' + this.selected.weekIndexes.join(', ')).fontSize(13).fontColor(ThemeColors.textSecondary)
      Text(ReadableText.resource($r('app.string.timetable_local_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).lineBreakStrategy(LineBreakStrategy.GREEDY)
      Row({ space: 12 }) {
        Button($r('app.string.timetable_edit')).onClick(() => { this.edit(this.selected) }).layoutWeight(1)
        Button($r('app.string.timetable_remove')).fontColor(ThemeColors.error)
          .backgroundColor($r('app.color.surface_fallback'))
          .onClick(() => { this.removeCourse() }).layoutWeight(1)
      }
    }.padding(24).width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  SheetContent() {
    if (this.showExport) {
      TimetableCalendarSheet({ courses: this.courses, monday: this.start(), owner: TimetableRepository.owner(),
        onBusy: (value: boolean) => { this.exporting = value } })
    } else if (this.showEditor) this.Editor()
    else if (this.showDetail) this.Details()
    else {
      Column() { CalendarSettings({ authenticationVisible: this.activeTab === 1 && this.showSheet && this.mainVisible }) }
        .padding({ top: 48 }).width('100%')
    }
  }

  @Builder
  EditorTextField(title: Resource, value: string, placeholder: Resource, fieldId: string, changed: (value: string) => void) {
    Column({ space: 4 }) {
      Text(title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .id(fieldId).width('100%').constraintSize({ minHeight: 42 }).fontSize(15)
        .fontColor(ThemeColors.textPrimary).placeholderColor(ThemeColors.textHint).borderRadius(12)
        .enabled(!this.saving).onChange((text: string) => { changed(text); this.editorError = '' })
        .accessibilityText(AppLanguage.text(title, this.languageRevision))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  EditorPeriodField(title: Resource, value: string, fieldId: string, changed: (value: string) => void) {
    Column({ space: 4 }) {
      Text(title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%')
      Select(TimetableSchedule.UNITS.map((unit: number): SelectOption => ({ value: String(unit) })))
        .selected(value ? Number(value) - 1 : -1).value(value || $r('app.string.timetable_editor_period_hint'))
        .id(fieldId).width('100%').constraintSize({ minHeight: 42 }).font({ size: 15 })
        .fontColor(value ? ThemeColors.textPrimary : ThemeColors.textHint).optionFont({ size: 15 })
        .optionFontColor(ThemeColors.textPrimary).selectedOptionFontColor(ThemeColors.primary).borderRadius(12)
        .enabled(!this.saving).onSelect((index: number) => { changed(String(index + 1)); this.editorError = '' })
        .accessibilityText(AppLanguage.text(title, this.languageRevision))
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }

  @Builder
  Editor() {
    // One native sheet detent and one native keyboard avoider. The Scroll
    // follows the resized sheet; no keyboard callback rewrites layout geometry.
    Scroll() { this.EditorFields() }
      .id('timetable-course-editor-scroll').width('100%')
      .height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
  }

  @Builder
  EditorFields() {
    Column({ space: 10 }) {
      Column({ space: 6 }) {
        Text(this.editingKey ? $r('app.string.timetable_edit_title') : $r('app.string.timetable_add'))
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).padding({ right: 32 })
        Text($r('app.string.timetable_editor_intro')).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
      }.alignItems(HorizontalAlign.Start).width('100%').margin({ bottom: 2 })
      this.EditorTextField($r('app.string.timetable_course_name'), this.courseName, $r('app.string.timetable_course_name'),
        'timetable-course-name', (text: string) => { this.courseName = text })
      this.EditorTextField($r('app.string.timetable_room'), this.location, $r('app.string.timetable_editor_optional'),
        'timetable-course-room', (text: string) => { this.location = text })
      Row({ space: 10 }) {
        Column() {
          this.EditorTextField($r('app.string.timetable_teacher'), this.teacher, $r('app.string.timetable_editor_optional'),
            'timetable-course-teacher', (text: string) => { this.teacher = text })
        }.layoutWeight(1)
        Column() {
          this.EditorTextField($r('app.string.timetable_code'), this.code, $r('app.string.timetable_editor_optional'),
            'timetable-course-code', (text: string) => { this.code = text })
        }.layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Top)
      Column({ space: 4 }) {
        Text($r('app.string.timetable_weekday')).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary).width('100%')
        Select(this.dayNames.map((name: ResourceStr): SelectOption => ({ value: name }))).selected(this.weekday - 1)
          .id('timetable-course-weekday').value(this.weekday > 0 ? this.dayLabel(this.weekday) : $r('app.string.timetable_select_weekday'))
          .font({ size: 15 }).fontColor(this.weekday > 0 ? ThemeColors.textPrimary : ThemeColors.textHint)
          .optionFont({ size: 15 }).optionFontColor(ThemeColors.textPrimary).selectedOptionFontColor(ThemeColors.primary)
          .onSelect((index: number) => { this.weekday = index + 1; this.editorError = '' }).enabled(!this.saving)
          .width('100%').constraintSize({ minHeight: 42 }).borderRadius(12)
          .accessibilityText(AppLanguage.text($r('app.string.timetable_weekday'), this.languageRevision))
      }.alignItems(HorizontalAlign.Start).width('100%')
      Row({ space: 10 }) {
        this.EditorPeriodField($r('app.string.timetable_first_unit'), this.firstUnit, 'timetable-course-first-unit',
          (text: string) => { this.firstUnit = text })
        this.EditorPeriodField($r('app.string.timetable_last_unit'), this.lastUnit, 'timetable-course-last-unit',
          (text: string) => { this.lastUnit = text })
      }.width('100%').alignItems(VerticalAlign.Top)
      Column({ space: 4 }) {
        this.EditorTextField($r('app.string.timetable_weeks'), this.weeks, $r('app.string.timetable_editor_weeks_placeholder'),
          'timetable-course-weeks', (text: string) => { this.weeks = text })
        Text(ReadableText.resource($r('app.string.timetable_weeks_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
      }.alignItems(HorizontalAlign.Start).width('100%')
      if (this.editorError) {
        ErrorNotice({ message: this.editorError, controlId: 'timetablepage-diagnostics', textSize: 12, textColor: ThemeColors.error }).id('timetable-course-error')
          .width('100%').transition(TransitionEffect.OPACITY)
      }
      Button($r('app.string.timetable_save')).id('timetable-save-course').width('100%').constraintSize({ minHeight: 44 })
        .backgroundColor(ThemeColors.primary).fontColor(Color.White).enabled(!this.saving).onClick(() => { this.saveCourse() })
      Text(ReadableText.resource($r('app.string.timetable_editor_local_note'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
    }.padding({ left: 20, right: 20, top: 8, bottom: 16 }).width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  Notices() {
    Column() {
      if (this.notices !== undefined) {
            if (this.notices.error) {
              ErrorNotice({ message: this.notices.error, controlId: 'timetablepage-diagnostics', textSize: 13, textColor: ThemeColors.error }).padding(12).width('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
            }
            if (this.notices.verification) {
              FloatingActionButton({ label: $r('app.string.campus_verify_continue'), actionEnabled: !this.loading,
                onAction: () => { this.verifyAndReload() } }).margin({ left: 12, bottom: 12 })
                .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
            }
            if (this.notices.dateMissing) {
              Text(ReadableText.resource($r('app.string.timetable_date_hint'))).fontSize(13).lineHeight(21).fontColor(ThemeColors.primary).padding(12).width('100%')
                .onClick(() => { this.openSheet(() => { this.showCalendar = true }) }).lineBreakStrategy(LineBreakStrategy.GREEDY)
                .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
            } else if (this.notices.outsideTerm) {
              Text($r('app.string.timetable_outside_term')).fontSize(12).fontColor(ThemeColors.textSecondary).padding(12)
                .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
            }
            if (this.notices.historical) {
              Text(ReadableText.resource($r('app.string.timetable_history_diary_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary)
                .padding({ left: 8, right: 8, top: 4, bottom: 12 }).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
                .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
            }
            if (this.notices.empty) {
              Text(this.notices.guest ? $r('app.string.timetable_guest') : $r('app.string.timetable_empty')).fontSize(13).lineHeight(20).fontColor(ThemeColors.textSecondary).padding({ left: 8, right: 8, top: 2, bottom: 8 })
                .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
            }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).id('timetable-notices').hitTestBehavior(HitTestMode.Transparent)
      .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
        const height: number = Number(newSize.height)
        if (Number.isFinite(height) && height >= 0 && height !== this.noticeHeight) this.noticeHeight = height
      })
      .translate({ y: this.noticeOffset() }).animation({ duration: 240, curve: Curve.Friction })
      .position({ x: 0, y: 0 })
  }

  @Builder
  Content() {
    Column() {
      Column() {
        // Positioned notices do not participate in Column's main-flow size.
        this.Notices()
        Column() {
          if (this.agenda) this.Agenda()
          else this.WeekGrid()
          if (this.updatedAt > 0) Text(AppLanguage.text($r('app.string.timetable_updated'), this.languageRevision) + ' ' +
            new Date(this.updatedAt).toLocaleString()).fontSize(12).fontColor(ThemeColors.textSecondary).padding(12)
        }.width('100%').alignItems(HorizontalAlign.Start).renderGroup(true).id('timetable-course-body')
          .translate({ y: this.bodyOffset() }).animation({ duration: 240, curve: Curve.Friction })
      }.width('100%')
        // Account for the rendered offsets once in scroll extent; only
        // translate is animated, never the padding or timetable row sizes.
        .padding({ bottom: this.bodyOffset() + px2vp(this.bottomPx) + 110 })
    }.width('100%').padding({ left: 12, right: 12 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
        Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        Scroll(this.touchScroller) {
          this.Content()
        }.width('100%').height('100%').scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) }).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }.width('100%').height('100%').onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => { this.load(this.semester.id !== 'local' ? this.semester : undefined, true) })
      CenterLoadingProgress({ busy: this.loading && !this.refreshing })
      TopFade({ extent: this.headerExtent() })
      FeedRefreshProgress({ topInset: this.headerExtent() + 16, pullOffset: this.pullOffset, refreshing: this.refreshing })
      this.Header()
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showSheet, this.SheetContent(), this.showSheetTransition.options(this.showSheet, {
        height: this.showEditor ? 640 : SheetSize.FIT_CONTENT,
        showClose: !this.exporting, dragBar: !this.exporting,
        shouldDismiss: (action: SheetDismiss) => { if (!this.exporting) action.dismiss() },
        keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
        onDisappear: () => { this.showEditor = false; this.showDetail = false; this.showCalendar = false; this.showExport = false }
      }))
  }
}
