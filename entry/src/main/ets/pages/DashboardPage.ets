import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice } from '../components/ErrorNotice'
import { settleScrollTouch } from '../common/ScrollTouch'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { AcademicAccount } from '../common/AcademicAccount'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { TopFade } from '../components/TopFade'
import { FloatingSurface } from '../components/FloatingSurface'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
/**
 * Dashboard Page - Campus feature cards.
 * Immersive light sense design.
 * Ported from lib/page/subpage_dashboard.dart
 */

import { router, promptAction } from '@kit.ArkUI'
import { FduRepository } from '../repository/FduRepository'
import { ForumListSource } from '../common/ForumListSource'
import { CardRepository } from '../repository/CardRepository'
import { CampusService } from '../common/CampusService'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { Constant } from '../common/Constant'
import { getSymbolIcon } from '../common/DanXiIcons'
import { Announcement, CourseGrade, BusSchedule, BusDirection, busDirectionArrow, EmptyClassroom, ExamSchedule, GpaListItem, TimeTableEntry } from '../model/Academic'
import { CardInfo, CardRecord } from '../model/Card'
import { BusTimetable } from '../model/BusTimetable'
import { CampusPreviewItem } from '../model/CampusPreviewItem'
import { CampusCardInformation } from '../common/CampusCardInformation'
import { CardPresentation } from '../model/CardPresentation'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { DateTimeUtils } from '../util/CommonUtils'
import { ClassroomRepository } from '../repository/ClassroomRepository'
import { TabSegmentButtonV2, SegmentButtonV2Items } from '@ohos.arkui.advanced.SegmentButtonV2'
import { ColorMetrics } from '@kit.ArkUI'
import { AppState } from '../common/AppState'
import { CampusLayout } from '../common/CampusLayout'
import { BrowserLink } from '../common/BrowserLink'
import { AppLanguage } from '../common/AppLanguage'
import { common } from '@kit.AbilityKit'
import { AcademicCalendar } from '../common/AcademicCalendar'
import { TimetableRepository } from '../repository/TimetableRepository'
import { TimetableSchedule } from '../model/TimetableSchedule'
import { TeachingCalendar } from '../model/TeachingCalendar'
import { Course } from '../model/Academic'
import { SemesterInfo } from '../model/Academic'
import { AcademicContent } from '../components/AcademicContent'
import { ClassroomContent } from '../components/ClassroomContent'
import { AcademicPresentation } from '../common/AcademicPresentation'
import { LocalGpa } from '../common/LocalGpa'
import { AcademicRequest, AcademicSource } from '../common/AcademicRequest'
import { ClassroomRequest, classroomRowKey } from '../common/ClassroomRequest'
import { ClassroomPresentation } from '../common/ClassroomPresentation'
import { fileIo as fs, picker } from '@kit.CoreFileKit'
import { CampusHome } from '../components/CampusHome'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { CampusSignal } from '../common/CampusSignal'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { CampusPreview, CampusPreviewStore } from '../common/CampusPreview'
import { CampusPreference } from '../common/CampusPreference'
import { CampusFilterPreference } from '../common/CampusFilterPreference'

class DashboardAcademicSource implements AcademicSource {
  private repository: FduRepository
  private force: boolean
  constructor(repository: FduRepository, force: boolean) { this.repository = repository; this.force = force }
  getSemesters(): Promise<SemesterInfo[]> { return this.repository.getSemesters(this.force) }
  // getSemesters already refreshed this bundle; resolve its DOM default without another request.
  getCurrentSemester(): Promise<SemesterInfo> { return this.repository.getCurrentSemester(false) }
  getExamSchedules(): Promise<ExamSchedule[]> { return this.repository.getExamSchedules() }
  getCourseGrades(semesterId: string): Promise<CourseGrade[]> { return this.repository.getCourseGrades(semesterId) }
  getGpaList(): Promise<GpaListItem[]> { return this.repository.getGpaList() }
  getCourseGradesFromDataCenter(): Promise<CourseGrade[]> { return this.repository.getCourseGradesFromDataCenter() }
}

@Component
export struct DashboardPage {
  @Prop @Watch('detailChanged') detailFeature: string = ''
  @Prop @Watch('visibilityChanged') detailVisible: boolean = true
  private touchScroller: Scroller = new Scroller()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(AcademicCalendar.KEY_REVISION) @Watch('calendarChanged') calendarRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink(CampusPreference.KEY) @Watch('systemCampusChanged') systemCampus: string = '邯郸'
  @State announcements: Announcement[] = []
  @State announcementError: string = ''
  @State noticeLoadingMore: boolean = false
  @State noticeMoreError: string = ''
  @State noticeHasMore: boolean = false
  private noticePage: number = 1
  private noticeGeneration: number = 0
  private noticeSource: ForumListSource<Announcement> = new ForumListSource<Announcement>()

  private async loadMoreNotices(): Promise<void> {
    if (this.activeFeature !== 'announcement' || this.isLoading || this.refreshing || this.noticeLoadingMore || !this.noticeHasMore) return
    const generation: number = this.noticeGeneration
    this.noticeLoadingMore = true
    this.noticeMoreError = ''
    try {
      const page = await this.fduRepo.getAnnouncementPage(undefined, this.noticePage + 1)
      if (generation !== this.noticeGeneration || this.activeFeature !== 'announcement') return
      const fresh: Announcement[] = page.rows.filter((row: Announcement) => !this.announcements.some((old: Announcement) => old.url === row.url))
      this.announcements = this.announcements.concat(fresh)
      this.noticeSource.update(this.announcements)
      this.noticePage++
      this.noticeHasMore = page.hasMore && fresh.length > 0
    } catch (e) {
      if (generation === this.noticeGeneration) this.noticeMoreError = ErrorDiagnostics.message(e as Object)
    } finally { if (generation === this.noticeGeneration) this.noticeLoadingMore = false }
  }
  @State busSchedules: BusSchedule[] = []
  @State busHoliday: boolean = new Date().getDay() === 0 || new Date().getDay() === 6
  @State busStart: string = '邯郸'
  @State busEnd: string = '江湾'
  @State busShowAll: boolean = false
  @State busNow: Date = new Date()
  private busTimer: number = -1
  private busGeneration: number = 0
  private busCache: Map<boolean, BusSchedule[]> = new Map<boolean, BusSchedule[]>()
  private busLoaded: boolean = false
  private busDayItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.bus_weekday') }, { text: $r('app.string.bus_holiday') }
  ])
  private cardRangeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.card_recent') }, { text: $r('app.string.card_7_days') },
    { text: $r('app.string.card_15_days') }, { text: $r('app.string.card_30_days') }
  ])
  private cardGeneration: number = 0
  @State cardDays: number = 0
  @State cardProgress: string = ''
  @State emptyClassrooms: EmptyClassroom[] = []
  @StorageLink('academic_account_revision') @Watch('academicChanged') academicRevision: number = 0
  @State graduate: boolean = false
  @State courseGrades: CourseGrade[] = []
  @State graduateStartKnown: boolean = false
  @State exams: ExamSchedule[] = []
  // The GPA endpoint returns a ranking TABLE (one row per major), not a single
  // weighted average — see model/Academic.ets. The old `gpaSummary` held a total
  // credit count and a per-semester map that no Fudan service sends.
  @State gpaList: GpaListItem[] = []
  @State academicSemesters: SemesterInfo[] = []
  @State academicSemesterId: string = ''
  @State academicLoading: boolean = false
  @State academicSemesterError: string = ''
  @State academicFallback: boolean = false
  private academicRequest: AcademicRequest = new AcademicRequest()
  private classroomRequest: ClassroomRequest = new ClassroomRequest()
  @State classroomLoading: boolean = false
  @State gradeError: string = ''
  @State timetable: TimeTableEntry[] = []
  // Campus card. Loaded on demand rather than in loadData(), because reaching
  // it requires a CAS login for the ecard service on top of the my.fudan one
  // the user already did; doing that at startup would put an extra handshake on
  // the critical path for a tab most sessions never open.
  @State cardInfo: CardInfo | null = null
  @State cardError: string = ''
  @State cardLoading: boolean = false
  @State cardLoaded: boolean = false
  // One error slot per campus service. These failures used to be swallowed by
  // `.catch(() => {})`, which hid the fact that the values on screen were
  // invented. Kept per-service rather than shared so that wiring one service
  // up later cannot leave a stale message showing on it.
  @State busError: string = ''
  @State classroomError: string = ''
  @State examError: string = ''
  @State gpaError: string = ''
  @State timetableError: string = ''
  @State isLoading: boolean = true
  @State private detailOpacity: number = 1
  private detailMotionRevision: number = 0
  private revealDetail(commit: () => void, valid: () => boolean = () => true): Promise<void> {
    if (!this.detailFeature) { if (valid()) commit(); return Promise.resolve() }
    const revision: number = ++this.detailMotionRevision
    return new Promise<void>((resolve: () => void) => {
      this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut, onFinish: () => {
        if (!this.active || !this.detailVisible || revision !== this.detailMotionRevision || !valid()) {
          if (revision === this.detailMotionRevision) this.detailOpacity = 1
          resolve(); return
        }
        commit()
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.detailOpacity = 1 })
        resolve()
      } }, () => { this.detailOpacity = 0 })
    })
  }
  @State refreshing: boolean = false
  @State private pullOffset: number = 0
  @State activeFeature: string = 'announcement'
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') personJson: string = ''
  @StorageLink(AppState.KEY_DASHBOARD_ORDER) @Watch('layoutChanged') dashboardJson: string = ''
  @State visibleFeatures: string[] = Constant.DEFAULT_DASHBOARD_ORDER.slice()
  private openingNotice: boolean = false
  private exportingExams: boolean = false
  @State classroomBuilding: string = 'HGD'
  @State classroomDay: string = ''
  @State classroomCampus: string = '邯郸'
  private featureGeneration: number = 0
  @StorageLink('campus_refresh') @Watch('resumeCampus') campusRefresh: number = 0
  private loadedFeatures: Set<string> = new Set<string>()
  private active: boolean = false
  private accountScope: string = ''
  private academicGroup: string = ''

  private fduRepo: FduRepository = FduRepository.getInstance()

  /**
   * Error.prototype.toString() decorates the message with the error's name, so
   * String(err) renders as "HttpError: <message>" (HttpError sets this.name) or
   * "Error: <message>". Strip that prefix so the card shows the sentence the
   * repository wrote and nothing else.
   */
  private static errorText(err: Object): string {
    const text: string = String(err)
    const sep: number = text.indexOf(': ')
    // Only a leading bare identifier counts as a name ("HttpError", "Error",
    // "TypeError"): no spaces before the colon, and not a long message.
    if (sep > 0 && sep <= 24 && text.substring(0, sep).indexOf(' ') < 0) {
      return text.substring(sep + 2)
    }
    return text
  }

  /**
   * Campus pair plus direction: "邯郸 → 枫林".
   *
   * The bus endpoint returns no line name — upstream flattens every route's
   * departures into one list and keeps the route object nowhere — so the route
   * is identified by its endpoints, which is what the Flutter app shows too.
   */
  private static busRouteText(item: BusSchedule): string {
    if (item.startCampus.length === 0 && item.endCampus.length === 0) {
      // A campus name outside the known four. Show the times rather than an
      // empty heading.
      return AppLanguage.text($r('app.string.ui_shuttle_departures'))
    }
    return item.startCampus + busDirectionArrow(item.direction) + item.endCampus
  }

  /**
   * Departure and arrival.
   *
   * Upstream falls back to whichever of the two exists
   * (`realStartTime = startTime ?? endTime`, bus_repository.dart:72), and the
   * parser already drops rows where both are empty, so this never returns ''.
   */
  private static busTimeText(item: BusSchedule): string {
    if (item.startTime.length > 0 && item.endTime.length > 0) {
      return item.startTime + ' - ' + item.endTime
    }
    return item.startTime.length > 0 ? item.startTime : item.endTime
  }

  aboutToAppear(): void {
    this.active = true
    this.accountScope = this.currentAccountScope()
    this.academicGroup = AcademicAccount.group()
    if (!this.detailFeature) return
    this.activeFeature = this.detailFeature
    this.visibleFeatures = AppState.getDashboardOrder()
    if (!Constant.DEFAULT_DASHBOARD_ORDER.includes(this.activeFeature)) this.activeFeature = 'announcement'
    this.graduate = AcademicAccount.isGraduate()
    AcademicAccount.semesterStart().then((value: string) => { this.graduateStartKnown = value.length > 0 })
    this.loadBusPreferences()
    this.busTimer = setInterval(() => { this.busNow = new Date() }, 30000)
    this.loadData()
  }

  private layoutChanged(): void {
    if (this.detailFeature) return
    this.visibleFeatures = AppState.getDashboardOrder()
    if (!this.visibleFeatures.includes(this.activeFeature)) {
      this.activeFeature = this.visibleFeatures[0]
    }
  }

  private async openAnnouncement(item: Announcement): Promise<void> {
    if (this.openingNotice) return
    this.openingNotice = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await BrowserLink.open(context, item.url)
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.announcement_open_failed'))) }
    finally { this.openingNotice = false }
  }

  aboutToDisappear(): void {
    this.detailMotionRevision++; this.detailOpacity = 1
    this.noticeGeneration++
    this.noticeLoadingMore = false
    this.active = false
    if (this.busTimer >= 0) clearInterval(this.busTimer)
    this.busGeneration++
    this.cardGeneration++
    this.classroomRequest.invalidate()
    this.academicRequest.invalidate()
    this.featureGeneration++
  }

  private detailChanged(): void {
    if (this.active && this.detailFeature && this.activeFeature !== this.detailFeature) {
      this.activeFeature = this.detailFeature; this.loadData()
    }
  }

  private publishPreview(id: string, value: string, description: string, secondary: string = '', tone: string = '', items: CampusPreviewItem[] = [], total: number = -1): void {
    const row: CampusPreview = new CampusPreview()
    row.tone = tone; row.id = id; row.value = value; row.description = description; row.secondary = secondary; row.updatedAt = Date.now()
    row.items = items; row.total = total
    CampusPreviewStore.publish(row, CampusPreviewStore.owner()).catch(() => {})
  }

  private async loadBusPreferences(): Promise<void> {
    const selectedStart: string = this.busStart
    const selectedEnd: string = this.busEnd
    const start = await CampusFilterPreference.read('bus_start')
    const end = await CampusFilterPreference.read('bus_end', start === '江湾' ? '邯郸' : '江湾')
    if (this.busStart === selectedStart && BusTimetable.CAMPUSES.includes(start)) this.busStart = start
    if (this.busEnd === selectedEnd && BusTimetable.CAMPUSES.includes(end)) this.busEnd = end
  }

  private saveBusRoute(): void {
    const prefs = PreferencesUtil.getInstance()
    prefs.putString('bus_start', this.busStart).catch(() => {})
    prefs.putString('bus_end', this.busEnd).catch(() => {})
    CampusFilterPreference.remember('bus_start', this.busStart).catch(() => {})
    CampusFilterPreference.remember('bus_end', this.busEnd).catch(() => {})
    this.publishBusPreview()
  }
  private systemCampusChanged(): void {
    if (!this.active || this.activeFeature !== 'bus') return
    this.busStart = CampusPreference.current(); this.busEnd = this.busStart === '江湾' ? '邯郸' : '江湾'
    this.publishBusPreview()
  }

  private busRows(): BusSchedule[] {
    return BusTimetable.filter(this.busSchedules, this.busStart, this.busEnd, this.busShowAll, this.busNow)
  }

  private selectBusDay(index: number): void {
    const holiday = index === 1
    if (holiday === this.busHoliday) return
    this.busHoliday = holiday
    this.loadBus(false)
  }

  private async showBusRows(rows: BusSchedule[]): Promise<void> {
    const generation: number = this.busGeneration
    await this.revealDetail(() => {
      this.busSchedules = rows
      this.busLoading = false
      this.busLoaded = true
    }, () => generation === this.busGeneration)
    this.publishBusPreview()
  }

  private publishBusPreview(): void {
    const items: CampusPreviewItem[] = !this.busLoading && !this.busError && this.busLoaded ?
      CampusCardInformation.buses(this.busSchedules, this.busStart, this.busEnd, this.busNow) : []
    const value: string = this.busLoading ? AppLanguage.text($r('app.string.ui_loading')) :
      this.busError || !this.busLoaded ? AppLanguage.text($r('app.string.campus_preview_open')) :
      items[0]?.value || AppLanguage.text($r('app.string.bus_empty'))
    this.publishPreview('bus', value,
      this.busStart + ' → ' + this.busEnd,
      AppLanguage.text(this.busHoliday ? $r('app.string.bus_holiday') : $r('app.string.bus_weekday')), '', items)
  }

  private selectCardRange(index: number): void {
    const days = [0, 7, 15, 30][index]
    if (days === undefined || days === this.cardDays) return
    this.cardDays = days
    this.loadCard()
  }

  private async loadBus(force: boolean): Promise<void> {
    const generation = ++this.busGeneration
    const holiday = this.busHoliday
    this.isLoading = false
    this.busError = ''
    const cached = this.busCache.get(holiday)
    if (!force && cached !== undefined) { await this.showBusRows(cached); return }
    this.busLoaded = false
    this.busLoading = true
    try {
      const rows = await this.fduRepo.getBusSchedules(holiday)
      if (generation !== this.busGeneration) return
      this.busCache.set(holiday, rows)
      await this.showBusRows(rows)
    } catch (e) {
      if (generation === this.busGeneration) this.busError = DashboardPage.errorText(e)
    } finally {
      if (generation === this.busGeneration) {
        this.busLoading = false
        if (this.busError) this.publishBusPreview()
      }
    }
  }
  @State busLoading: boolean = false

  private accountChanged(): void {
    const scope: string = this.currentAccountScope()
    if (scope === this.accountScope) return
    this.accountScope = scope
    this.busGeneration++; this.cardGeneration++; this.featureGeneration++
    this.classroomRequest.invalidate(); this.academicRequest.invalidate()
    this.loadedFeatures.clear(); this.busCache.clear()
    this.busLoaded = false
    this.busSchedules = []; this.emptyClassrooms = []; this.cardInfo = null
    this.announcements = []; this.cardLoaded = false
    this.noticeGeneration++; this.noticeLoadingMore = false; this.noticeHasMore = false; this.noticeSource.update([])
    this.busLoading = false; this.cardLoading = false; this.classroomLoading = false
    this.academicChanged(true)
    if (this.active && this.detailVisible && this.detailFeature && this.activeFeature === 'empty_classroom') this.loadClassrooms(false)
    else if (this.active && this.detailVisible && this.detailFeature && this.activeFeature !== 'academic') this.loadFeature(this.activeFeature)
  }

  private currentAccountScope(): string {
    const person = AppState.getPerson()
    return person.getStudentId() + ':' + person.getToken() + ':' + AcademicAccount.group()
  }

  academicChanged(force: boolean = false): void {
    const group: string = AcademicAccount.group()
    if (!force && group === this.academicGroup) return
    this.academicGroup = group
    this.graduate = AcademicAccount.isGraduate()
    this.loadedFeatures.clear()
    this.exams = []; this.gpaList = []; this.timetable = []; this.courseGrades = []
    this.academicSemesters = []; this.academicSemesterId = ''
    this.academicRequest.invalidate()
    this.academicLoading = false
    AcademicAccount.semesterStart().then((value: string) => { this.graduateStartKnown = value.length > 0 })
    this.featureGeneration++
    this.isLoading = false
    this.examError = ''; this.gpaError = ''; this.gradeError = ''; this.academicSemesterError = ''; this.timetableError = ''
    if (this.active && this.detailVisible && this.detailFeature && this.activeFeature === 'academic') this.loadFeature('academic')
  }

  calendarChanged(): void {
    this.graduateStartKnown = AcademicCalendar.start().length > 0
    this.loadedFeatures.delete('timetable')
    // A calendar update changes local week labels; it does not invalidate server courses.
  }

  resumeCampus(): void {
    this.graduateStartKnown = AcademicCalendar.start().length > 0
  }

  loadData(): void {
    if (this.active && this.detailFeature && this.detailVisible) this.loadFeature(this.activeFeature)
  }

  private service(): string {
    if (this.activeFeature === 'bus') return CampusService.BUS
    if (this.activeFeature === 'card') return CampusService.ECARD
    if (this.activeFeature === 'empty_classroom') return ClassroomRepository.LOGIN_URL
    if (['academic', 'timetable'].includes(this.activeFeature)) return this.fduRepo.academicService(this.activeFeature)
    return ''
  }

  private verificationRequired(): boolean {
    const service: string = this.service()
    return service.length > 0 && this.fduRepo.canLoginOnDemand() && this.fduRepo.needsVerification(service)
  }

  private refreshRunning: boolean = false
  private resumeVerified: boolean = false
  private visibilityChanged(): void {
    if (!this.detailVisible) { this.detailMotionRevision++; this.detailOpacity = 1 }
    if (this.active && this.detailVisible && this.resumeVerified && !this.refreshRunning) {
      this.resumeVerified = false
      this.refreshData()
    }
  }
  private async refreshData(verify: boolean = false): Promise<void> {
    if (this.refreshRunning) return
    if (this.isLoading || this.cardLoading || this.busLoading || this.classroomLoading || this.academicLoading) { this.refreshing = false; return }
    this.refreshing = true
    this.refreshRunning = true
    this.loadedFeatures.clear()
    this.cardLoaded = false
    this.busNow = new Date()
    const feature: string = this.activeFeature
    const owner: string = this.currentAccountScope()
    const generation: number = this.featureGeneration
    try {
      if (verify && this.verificationRequired()) await this.fduRepo.verifyService(this.service())
      if (!this.active || owner !== this.currentAccountScope() || generation !== this.featureGeneration || feature !== this.activeFeature) return
      if (!this.detailVisible) { this.resumeVerified = verify; return }
      if (this.activeFeature === 'empty_classroom') await this.loadClassrooms(true)
      else await this.loadFeature(this.activeFeature, true)
    }
    catch (e) {
      if (this.active && this.detailVisible && owner === this.currentAccountScope() && feature === this.activeFeature) {
        DiagnosticNavigation.feedback(this.getUIContext(), DashboardPage.errorText(e as Object))
      }
    }
    finally { this.refreshRunning = false; this.refreshing = false; this.visibilityChanged() }
  }

  /** Request only the selected service: a bus timeout must not queue every other login. */
  private async loadFeature(feature: string, force: boolean = false): Promise<void> {
    const generation = ++this.featureGeneration
    if (feature !== 'empty_classroom') { this.classroomRequest.invalidate(); this.classroomLoading = false }
    if (feature !== 'academic') { this.academicRequest.invalidate(); this.academicLoading = false }
    if (feature === 'bus') { await this.loadBus(force); return }
    if (feature === 'empty_classroom') { this.isLoading = false; return }
    if (feature === 'academic') {
      if (!force && this.loadedFeatures.has('academic')) { this.isLoading = false; return }
      await this.loadAcademic(force); return
    }
    if (feature === 'card') {
      this.isLoading = false
      if (force || !this.cardLoaded) await this.loadCard(force)
      return
    }
    if (!force && this.loadedFeatures.has(feature)) {
      this.isLoading = false
      return
    }
    if (!this.refreshing) this.isLoading = true
    try {
      if (feature === 'announcement') {
        const noticeGeneration: number = ++this.noticeGeneration
        this.noticeLoadingMore = false
        this.noticeMoreError = ''
        const page = await this.fduRepo.getAnnouncementPage()
        if (generation !== this.featureGeneration) return
        if (noticeGeneration !== this.noticeGeneration) return
        await this.revealDetail(() => {
          this.announcements = page.rows; this.noticeSource.update(this.announcements)
          this.noticePage = 1; this.noticeHasMore = page.hasMore; this.announcementError = ''
        }, () => generation === this.featureGeneration && noticeGeneration === this.noticeGeneration)

      } else if (feature === 'timetable') {
        const snapshot = await TimetableRepository.load(undefined, force)
        const edits = await TimetableRepository.edits(snapshot.semester)
        const week = TeachingCalendar.week(AcademicCalendar.manual() ? AcademicCalendar.start() :
          snapshot.semester.startDate || AcademicCalendar.start())
        const rows = TimetableSchedule.display(snapshot.courses, edits)
          .filter((course: Course) => week <= 0 || course.weekIndexes.includes(week))
          .map((course: Course): TimeTableEntry => ({ courseName: course.name, teacher: course.teachers.join(' / '),
            location: course.room, weekday: course.weekday, startSection: course.startUnit, endSection: course.endUnit,
            weeks: course.weekIndexes, color: TimetableSchedule.color(course) }))
        if (generation !== this.featureGeneration) return
        this.timetable = rows
        this.timetableError = ''
      }
      if (generation !== this.featureGeneration) return
      this.loadedFeatures.add(feature)
    } catch (e) {
      if (generation !== this.featureGeneration) return
      const message = DashboardPage.errorText(e)
      if (feature === 'announcement') { this.announcements = []; this.noticeSource.update([]); this.noticeHasMore = false; this.announcementError = message }
      else if (feature === 'bus') { this.busSchedules = []; this.busError = message }
      else if (feature === 'empty_classroom') { this.emptyClassrooms = []; this.classroomError = message }
      else if (feature === 'exam') { this.exams = []; this.examError = message }
      else if (feature === 'gpa') { this.gpaList = []; this.gpaError = message }
      else if (feature === 'timetable') { this.timetable = []; this.timetableError = message }
    } finally {
      if (generation === this.featureGeneration && this.activeFeature === feature) this.isLoading = false
    }
  }

  /**
   * Load the campus card, opening its CAS session first.
   *
   * The card is behind ecard.fudan.edu.cn, a DIFFERENT CAS service from the
   * my.fudan.edu.cn one the user logged into, so ensureSession() may have to
   * run a whole extra login (four redirect hops plus an RSA handshake) right
   * here. That is why this is a separate method called on first tab open
   * instead of part of loadData().
   *
   * Reachable without credentials too: ensureSession() throws a message naming
   * the service, which surfaces through cardError rather than an empty card.
   */
  private async loadClassrooms(force: boolean): Promise<void> {
    const generation: number = this.featureGeneration
    this.isLoading = false
    this.classroomLoading = true
    this.classroomError = ''
    const campus: string = this.classroomCampus
    const day: string = this.classroomDay
    const queryBuilding: string = this.classroomBuilding
    const result = await this.classroomRequest.load((building: string, refresh: boolean) =>
      this.fduRepo.getEmptyClassrooms(building, campus, refresh, day), queryBuilding, force)
    if (result === undefined) return
    await this.revealDetail(() => {
      this.emptyClassrooms = result.rows; this.classroomError = result.error; this.classroomLoading = false
    }, () => generation === this.featureGeneration && queryBuilding === this.classroomBuilding && campus === this.classroomCampus && day === this.classroomDay)
    if (generation !== this.featureGeneration) return
    if (result.error.length === 0) {
      this.loadedFeatures.add('empty_classroom')
      const today: string = ClassroomPresentation.day(new Date())
      if (day !== today) return
      const currentSlot = ClassroomPresentation.currentSlot(today)
      const free: number = result.rows.filter(row => ClassroomPresentation.slotFree(row, currentSlot) === true).length
      this.publishPreview('empty_classroom', currentSlot > 0 ? AppLanguage.text($r('app.string.campus_classroom_count'), this.languageRevision).replace('{count}', String(free)) :
        AppLanguage.text($r('app.string.campus_preview_open')), AppLanguage.text(currentSlot > 0 ? $r('app.string.campus_classroom_period_note') : $r('app.string.campus_classroom_outside_period')) + '\n' +
        queryBuilding + ' · ' + day, AppLanguage.campus(campus), currentSlot > 0 ? CampusSignal.classrooms(free,
          result.rows.filter(row => ClassroomPresentation.slotFree(row, currentSlot) !== undefined).length) : '',
        CampusCardInformation.classrooms(result.rows, currentSlot), currentSlot > 0 ? CampusCardInformation.classroomTotal(result.rows, currentSlot) : -1)
    }
  }

  private async loadAcademic(force: boolean): Promise<void> {
    const generation: number = this.featureGeneration
    const semester: string = this.academicSemesterId
    this.isLoading = false
    this.academicLoading = true
    this.loadedFeatures.delete('academic')
    this.examError = ''; this.gradeError = ''; this.gpaError = ''; this.academicSemesterError = ''
    const result = await this.academicRequest.load(new DashboardAcademicSource(this.fduRepo, force),
      this.graduate, this.academicSemesterId)
    if (result === undefined) return
    await this.revealDetail(() => {
      this.academicSemesters = result.fallback ? [] : result.semesters; this.academicSemesterId = result.semesterId
      this.exams = result.exams; this.courseGrades = result.grades; this.gpaList = result.ranks
      this.examError = result.examError; this.gradeError = result.gradeError; this.gpaError = result.rankError
      this.academicSemesterError = result.semesterError; this.academicFallback = result.fallback; this.academicLoading = false
    }, () => generation === this.featureGeneration && semester === this.academicSemesterId)
    if (generation !== this.featureGeneration) return
    if (!result.gradeError || !result.rankError) {
      const local = LocalGpa.calculate(result.grades, this.graduate)
      const preview = new CampusPreview()
      preview.id = 'academic'; preview.gpa = local.gpa; preview.credits = local.credits; preview.calculation = 'local-v1'
      preview.value = local.gpa ? 'GPA ' + local.gpa : AppLanguage.text($r('app.string.academic_my_gpa_unavailable'))
      preview.description = AppLanguage.text($r('app.string.campus_academic_summary')).replace('{exams}', result.examError ? '—' : String(result.exams.length))
        .replace('{grades}', result.gradeError ? '—' : String(result.grades.length))
      preview.secondary = result.semesters.find(row => row.id === result.semesterId)?.name ?? ''
      preview.updatedAt = Date.now()
      CampusPreviewStore.publish(preview, CampusPreviewStore.owner()).catch(() => {})
    }
    if ([result.examError, result.gradeError, result.rankError, result.semesterError].every((error: string) => error.length === 0)) {
      this.loadedFeatures.add('academic')
    }
  }

  private selectSemester(id: string): void {
    if (id === this.academicSemesterId) return
    this.academicSemesterId = id
    this.loadFeature('academic', true)
  }

  private async exportExams(): Promise<void> {
    if (this.exportingExams) return
    let content: string = ''
    try { content = AcademicPresentation.examsCalendar(this.exams) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.academic_export_unavailable'))); return }
    this.exportingExams = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const paths = await new picker.DocumentViewPicker(context).save({ newFileNames: ['DanXi-Exams.ics'], fileSuffixChoices: ['iCalendar|.ics'] })
      if (paths.length === 0) return
      const file = fs.openSync(paths[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
      try { fs.writeSync(file.fd, content) } finally { fs.closeSync(file) }
      promptAction.showToast({ message: $r('app.string.timetable_exported') })
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.timetable_export_failed'))) }
    finally { this.exportingExams = false }
  }

  async loadCard(force: boolean = false): Promise<void> {
    const generation = ++this.cardGeneration
    const days = this.cardDays
    this.cardLoading = true
    this.cardLoaded = true
    this.cardError = ''
    this.cardProgress = ''
    try {
      const info = await this.fduRepo.withService(CampusService.ECARD, async (cookies: string) => {
        const repository = CardRepository.getInstance()
        repository.setSession(cookies)
        if (force) repository.invalidate()
        const balance = await repository.getCardInfo(-1)
        if (generation === this.cardGeneration) this.cardInfo = balance
        balance.records = await repository.getCardRecords(days, (page: number, total: number) => {
          if (generation === this.cardGeneration) this.cardProgress = String(page) + ' / ' + String(total)
        }, (rows: CardRecord[]) => {
          if (generation === this.cardGeneration) this.cardInfo = { name: balance.name, cash: balance.cash, records: rows }
        })
        return balance
      })
      if (generation === this.cardGeneration) {
        await this.revealDetail(() => { this.cardInfo = { name: info.name, cash: info.cash, records: info.records } }, () => generation === this.cardGeneration)
        this.publishPreview('card', CardPresentation.balance(info.cash), AppLanguage.text($r('app.string.ui_card_balance')), info.name, CampusSignal.amount(info.cash))
      }
    } catch (e) {
      if (generation === this.cardGeneration) this.cardError = DashboardPage.errorText(e)
    } finally {
      if (generation === this.cardGeneration) this.cardLoading = false
    }
  }

  build() {
    if (!this.detailFeature) {
      CampusHome()
    } else {
    Stack({ alignContent: Alignment.Top }) {
        Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
      Column() {
      if (this.activeFeature === 'announcement') {
        List({ scroller: this.touchScroller }) { this.AnnouncementContent() }
          .width('100%').layoutWeight(1).padding({ left: 16, right: 16 })
          .contentStartOffset(px2vp(this.topPx) + 72)
          .contentEndOffset(Math.max(16, px2vp(this.bottomPx)) + 24)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) })
          .onReachEnd(() => { if (!this.noticeMoreError) this.loadMoreNotices() })
      } else {
        Scroll(this.touchScroller) {
          Column() {
            if (this.activeFeature === 'bus') {
              Column() {
                this.CampusUnavailable(AppLanguage.text($r('app.string.ui_bus'), this.languageRevision), this.busError)
                this.BusContent()
              }
                .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            } else if (this.activeFeature === 'empty_classroom') {
              Column() {
                this.EmptyClassroomContent()
              }.width('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            } else if (this.activeFeature === 'academic') {
              Column() {
                AcademicContent({ graduate: this.graduate, exams: this.exams, grades: this.courseGrades, ranks: this.gpaList,
                  semesters: this.academicSemesters, semesterId: this.academicSemesterId,
                  studentId: AppState.getPerson().getStudentId(), loading: this.academicLoading, loadingOverlay: true,
                  examError: this.examError, gradeError: this.gradeError, rankError: this.gpaError,
                  semesterError: this.academicSemesterError, fallback: this.academicFallback,
                  onSemester: (id: string) => { this.selectSemester(id) },
                  onReload: () => { this.refreshData(this.verificationRequired()) }, onExport: () => { this.exportExams() } })
              }.width('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            } else if (this.activeFeature === 'timetable') {
              Column() {
                this.CampusUnavailable(AppLanguage.text($r('app.string.ui_timetable'), this.languageRevision), this.timetableError)
                if (this.timetableError.length === 0) this.TimetableContent()
              }
                .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            } else if (this.activeFeature === 'card') {
              Column() {
                this.CardContent()
              }
                .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            }
          }
          .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: px2vp(this.topPx) + 72, bottom: Math.max(16, px2vp(this.bottomPx)) + 24 })
        }
        .align(Alignment.Top).scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) })
        .onReachEnd(() => { if (!this.noticeMoreError) this.loadMoreNotices() })
        .layoutWeight(1)
      }
      }.width('100%').height('100%').renderGroup(true)
        .opacity(this.detailOpacity * (this.detailLoading() && !this.refreshing ? 0.45 : 1)).animation({ duration: 220, curve: Curve.EaseOut })
      }.height('100%').width('100%').onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => { this.refreshData() })
      CenterLoadingProgress({ busy: this.detailLoading() && !this.refreshing })
      TopFade({ extent: px2vp(this.topPx) + 56 })
      FeedRefreshProgress({ topInset: px2vp(this.topPx) + 84, pullOffset: this.pullOffset, refreshing: this.refreshing })
      Column() {
      // Header
      Row({ space: 12 }) {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48, onAction: () => { router.back() }  }).width(48)
        Text(AppLanguage.text(CampusLayout.title(this.activeFeature), this.languageRevision))
          .fontSize(20).lineHeight(28).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1).textAlign(TextAlign.Center)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 48,
          controlId: 'campus-detail-refresh', actionEnabled: !this.detailLoading() && !this.refreshing,
          onAction: () => { this.refreshData(this.verificationRequired()) } }).width(48)
      }
      .width('100%')
      .height(56).padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })

      // Content area with cross-fade animation
      }.width('100%').padding({ top: px2vp(this.topPx) })
        .hitTestBehavior(HitTestMode.Transparent)

    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  private detailLoading(): boolean {
    return this.isLoading || this.busLoading || this.classroomLoading || this.academicLoading || this.cardLoading
  }

  @Builder
  FeatureTab(icon: string, label: ResourceStr, feature: string) {
    FloatingSurface({ radius: 24, acceptsInput: true,
      content: () => { this.FeatureControl(icon, label, feature) } })
      .width(this.featureWidth(feature))
      .height(48).margin({ right: 6 })
  }

  private featureWidth(feature: string): number {
    const label = AppLanguage.text(CampusLayout.title(feature), this.languageRevision)
    let width = 40 // Includes the native floating host's horizontal content inset.
    for (let i = 0; i < label.length; i++) width += label.charCodeAt(i) > 127 ? 11 : 6
    return Math.max(68, width)
  }

  @Builder
  FeatureControl(icon: string, label: ResourceStr, feature: string) {
    Button({ type: ButtonType.Capsule }) {
    Column() {
      SymbolGlyph(getSymbolIcon(icon))
        .fontSize(20)
        .fontColor([this.activeFeature === feature ? ThemeColors.primary : ThemeColors.textPrimary])
      Text(label)
        .fontSize(11)
        .maxLines(1).width('100%').textAlign(TextAlign.Center)
        .fontColor(this.activeFeature === feature ? ThemeColors.tabActive : ThemeColors.textPrimary)
        .fontWeight(this.activeFeature === feature ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 2 })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%').height('100%').padding({ top: 2, bottom: 2 })
    .borderRadius(ThemeDimens.radiusMedium)
    }
    .width('100%').height('100%').padding(0).backgroundColor(Color.Transparent)
    .stateEffect(false).hoverEffect(HoverEffect.None)
    .onClick(() => {
      if (this.activeFeature === feature) return
      this.getUIContext().animateTo({ duration: 360, curve: Curve.Friction }, () => {
        this.activeFeature = feature
      })
      // The card is the one tab whose data is fetched on first open, since it
      // costs an extra CAS login. Kick that off here rather than at startup.
      this.loadFeature(feature)
    })
  }

  // ── Glass card wrapper for content items ──
  @Builder
  GlassItem(content: void) {
    // Using inline glass styling on each item
  }

  /**
   * Honest fallback for the campus services that could not be loaded.
   *
   * The previous build filled these with invented values — a fake 3.72 GPA,
   * fake remaining-seat counts, fake exam dates and seat numbers — which on
   * screen looked exactly like live data.
   *
   * The trailing line used to read "登录链路尚未接通" (the login chain is not
   * connected). That stopped being true when id.fudan.edu.cn was reverse
   * engineered and verified against the live server, and leaving it up would
   * send anyone debugging a failure after the wrong cause.
   */
  @Builder
  CampusUnavailable(featureLabel: string, message: string) {
    if (message.length > 0) {
      Column() {
        Text(featureLabel + AppLanguage.text($r('app.string.ui_unavailable'), this.languageRevision))
          .fontSize(ThemeDimens.textSizeTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
        ErrorNotice({ message: message, controlId: 'dashboardpage-diagnostics', textSize: ThemeDimens.textSizeSmall, textColor: ThemeColors.textHint })
          .margin({ top: 6 })
        if (this.fduRepo.canLoginOnDemand() && !this.verificationRequired()) {
          FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', onCard: true, zeroContentPadding: true, controlHeight: 48,
            actionEnabled: !this.detailLoading() && !this.refreshing,
            onAction: () => { this.refreshData(this.verificationRequired()) } }).width(48).margin({ top: 12 })
        } else {
        Button(this.fduRepo.canLoginOnDemand() ? AppLanguage.text($r('app.string.campus_verify_continue'), this.languageRevision) : AppLanguage.text($r('app.string.ui_log_in_to_campus_account'), this.languageRevision))
          .margin({ top: 12 }).onClick(() => {
            if (this.fduRepo.canLoginOnDemand()) this.refreshData(this.verificationRequired())
            else router.pushUrl({ url: 'pages/LoginPage' }).catch((diagnosticFailure: Object) => {
              DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.ui_could_not_open_login_please_try_again'), this.languageRevision))
            })
          })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
      .borderRadius(ThemeDimens.radiusMedium)
      .margin({ top: 8 })
    }
  }

  @Builder
  AnnouncementContent() {
    // The notices are fetched from the live campus site, so surface a real
    // failure instead of rendering an empty card that looks like "no news".
    if (this.announcementError.length > 0 && this.announcements.length === 0) {
      ListItem() {
      Column() {
        Text(AppLanguage.text($r('app.string.ui_could_not_load_academic_notices'), this.languageRevision))
          .fontSize(ThemeDimens.textSizeTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
        ErrorNotice({ message: this.announcementError, controlId: 'dashboardpage-diagnostics', textSize: ThemeDimens.textSizeSmall, textColor: ThemeColors.textHint })
          .margin({ top: 6 })
        Text(AppLanguage.text($r('app.string.ui_source_jwc_fudan_edu_cn_may_require_campus_netwo'), this.languageRevision))
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textHint)
          .margin({ top: 4 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
      .borderRadius(ThemeDimens.radiusMedium)
      .margin({ top: 8 })
      }
    }
    LazyForEach(this.noticeSource, (item: Announcement, index: number) => {
      ListItem() {
      Column() {
        Row() {
          Text(item.title)
            .fontSize(ThemeDimens.textSizeTitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        // The AAO list page carries no body text, so this line is hidden
        // rather than shown empty.
        if (item.content.length > 0) {
          Text(item.content)
            .fontSize(ThemeDimens.textSizeBody)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 8 })
        }
        Row() {
          Text(item.source)
            .fontSize(ThemeDimens.textSizeSmall)
            .fontColor(ThemeColors.primary)
          Blank()
          Text(item.publishTime)
            .fontSize(ThemeDimens.textSizeSmall)
            .fontColor(ThemeColors.textHint)
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
      .borderRadius(ThemeDimens.radiusMedium)
      .margin({ top: 8 })
      .accessibilityRole(AccessibilityRoleType.BUTTON).accessibilityText(item.title)
      .onClick(() => { this.openAnnouncement(item) })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
      .onVisibleAreaChange([0.01], (visible: boolean) => {
        if (visible && index >= this.announcements.length - 3 && !this.noticeMoreError) this.loadMoreNotices()
      })
      }
    }, (item: Announcement): string => item.url + '|' + item.title + '|' + item.publishTime)
    ListItem() {
    Column() {
    if (this.noticeLoadingMore) {
      LoadingProgress().width(24).height(24).color(ThemeColors.primary).margin(12)
    } else if (this.noticeMoreError) {
      ErrorNotice({ message: this.noticeMoreError, controlId: 'dashboardpage-diagnostics', textSize: 12, textColor: ThemeColors.textSecondary }).margin(8)
      FloatingActionButton({ label: $r('app.string.ui_retry'), icon: 'refresh', zeroContentPadding: true, controlHeight: 48, onAction: () => { this.loadMoreNotices() } }).width(48)
    } else if (this.announcements.length > 0 && !this.noticeHasMore) {
      Text($r('app.string.detail_all_loaded')).fontSize(12).fontColor(ThemeColors.textHint).margin(12)
    }
    }.width('100%')
    }
  }

  @Builder
  BusContent() {
    Column({ space: 12 }) {
      TabSegmentButtonV2({ items: this.busDayItems, selectedIndex: this.busHoliday ? 1 : 0,
        $selectedIndex: (index: number) => { this.selectBusDay(index) }, enableStateAnimation: true,
        itemFontColor: ColorMetrics.resourceColor($r('app.color.theme_text_primary')),
        itemSelectedFontColor: ColorMetrics.rgba(255, 255, 255),
        itemSelectedBackgroundColor: ColorMetrics.resourceColor($r('app.color.theme_primary')),
        buttonBackgroundColor: ColorMetrics.resourceColor($r('app.color.input_surface'))
      }).width('100%')
      Row({ space: 8 }) {
        Text($r('app.string.bus_start')).fontSize(14)
        Select(BusTimetable.CAMPUSES.map((campus: string): SelectOption => ({ value: AppLanguage.campus(campus, this.languageRevision) })))
          .value(AppLanguage.campus(this.busStart, this.languageRevision)).selected(BusTimetable.CAMPUSES.indexOf(this.busStart)).layoutWeight(1)
          .onSelect((index: number) => {
            this.revealDetail(() => { this.busStart = BusTimetable.CAMPUSES[index]; this.saveBusRoute() })
          })
        Button($r('app.string.bus_swap')).onClick(() => {
          const start = this.busStart
          this.revealDetail(() => { this.busStart = this.busEnd; this.busEnd = start; this.saveBusRoute() })
        })
      }
      Row({ space: 8 }) {
        Text($r('app.string.bus_end')).fontSize(14)
        Select(BusTimetable.CAMPUSES.map((campus: string): SelectOption => ({ value: AppLanguage.campus(campus, this.languageRevision) })))
          .value(AppLanguage.campus(this.busEnd, this.languageRevision)).selected(BusTimetable.CAMPUSES.indexOf(this.busEnd)).layoutWeight(1)
          .onSelect((index: number) => {
            this.revealDetail(() => { this.busEnd = BusTimetable.CAMPUSES[index]; this.saveBusRoute() })
          })
      }
      Row() {
        Text(this.busShowAll ? $r('app.string.bus_all') : $r('app.string.bus_upcoming')).layoutWeight(1).fontSize(14)
        Toggle({ type: ToggleType.Switch, isOn: this.busShowAll })
          .onChange((value: boolean) => {
            this.revealDetail(() => {
              this.busShowAll = value; this.busNow = new Date()
            })
          })
      }
      Text($r('app.string.bus_time_note')).fontSize(12).fontColor(ThemeColors.textSecondary)
    }.width('100%').padding(16).margin({ top: 8 }).borderRadius(16)
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      

    if (!this.busLoading && !this.busError && this.busRows().length === 0) {
      Text(this.busStart === this.busEnd ? $r('app.string.bus_same_station') : $r('app.string.bus_empty'))
        .fontSize(14).fontColor(ThemeColors.textSecondary).padding(24)
    }
    ForEach(this.busRows(), (item: BusSchedule) => {
      Row() {
        Column({ space: 6 }) {
          Text(AppLanguage.campus(item.startCampus, this.languageRevision)).fontSize(17).fontWeight(FontWeight.Medium)
          Text(item.startTime || '—').fontSize(16)
        }.layoutWeight(1)
        Text(busDirectionArrow(item.direction)).fontSize(24).fontColor(ThemeColors.primary)
        Column({ space: 6 }) {
          Text(AppLanguage.campus(item.endCampus, this.languageRevision)).fontSize(17).fontWeight(FontWeight.Medium)
          Text(item.endTime || '—').fontSize(16)
        }.layoutWeight(1)
      }.width('100%').padding(ThemeDimens.cardInset).margin({ top: 10 }).borderRadius(16)
        .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
        
        .renderGroup(true)
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
          .animation({ duration: 360, curve: Curve.Friction }))
    }, (item: BusSchedule) => item.startCampus + '_' + item.endCampus + '_' + item.direction + '_' + item.startTime + '_' + item.endTime)
  }

  @Builder
  EmptyClassroomContent() {
    ClassroomContent({ items: this.emptyClassrooms, building: this.classroomBuilding, day: this.classroomDay,
      loading: this.classroomLoading, loadingOverlay: true, error: this.classroomError,
      onQuery: (building: string, campus: string, day: string, force: boolean) => {
        this.classroomBuilding = building; this.classroomCampus = campus; this.classroomDay = day
        this.loadClassrooms(force)
      } })
  }

  @Builder
  TimetableContent() {
    if (this.graduate && !this.graduateStartKnown) {
      Text($r('app.string.graduate_week_hint')).fontColor(ThemeColors.textSecondary).padding(12)
    }
    ForEach(this.timetable.filter((t: TimeTableEntry) => t.weekday === DateTimeUtils.getTodayWeekday()), (item: TimeTableEntry) => {
      Row() {
        // Color bar
        Column()
          .width(4)
          .height(60)
          .backgroundColor(item.color)
          .borderRadius(2)

        Column() {
          Text(item.courseName)
            .fontSize(ThemeDimens.textSizeTitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary)
          Row() {
            Text(item.teacher)
              .fontSize(ThemeDimens.textSizeSmall)
              .fontColor(ThemeColors.textSecondary)
            Text(item.location)
              .fontSize(ThemeDimens.textSizeSmall)
              .fontColor(ThemeColors.textSecondary)
              .margin({ left: 12 })
          }
          .margin({ top: 4 })
          Text(AppLanguage.text($r('app.string.ui_period'), this.languageRevision) + item.startSection + '-' + item.endSection + AppLanguage.text($r('app.string.ui_'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeSmall)
            .fontColor(ThemeColors.textHint)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
      .borderRadius(ThemeDimens.radiusMedium)
      .margin({ top: 8 })
    })

    if (this.timetable.filter((t: TimeTableEntry) => t.weekday === DateTimeUtils.getTodayWeekday()).length === 0) {
      Column() {
        Text('🎉')
          .fontSize(48)
        Text(this.graduate && !this.graduateStartKnown ? AppLanguage.text($r('app.string.ui_no_loaded_courses_for_today'), this.languageRevision) : AppLanguage.text($r('app.string.ui_no_classes_today'), this.languageRevision))
          .fontSize(ThemeDimens.textSizeBody)
          .fontColor(ThemeColors.textSecondary)
          .margin({ top: 8 })
      }
      .width('100%')
      .padding(40)
      .justifyContent(FlexAlign.Center)
    }
  }

  /**
   * Campus card: balance plus recent transactions.
   *
   * Every value here is a string copied from the page, not a parsed number —
   * see model/Card.ets for why. Nothing is recomputed or rounded, so what is on
   * screen is what the card site says.
   */
  @Builder
  CardContent() {
    TabSegmentButtonV2({ items: this.cardRangeItems, selectedIndex: [0, 7, 15, 30].indexOf(this.cardDays),
      $selectedIndex: (index: number) => { this.selectCardRange(index) }, enableStateAnimation: true,
      itemFontColor: ColorMetrics.resourceColor($r('app.color.theme_text_primary')),
      itemSelectedFontColor: ColorMetrics.rgba(255, 255, 255),
      itemSelectedBackgroundColor: ColorMetrics.resourceColor($r('app.color.theme_primary')),
      buttonBackgroundColor: ColorMetrics.resourceColor($r('app.color.input_surface'))
    }).width('100%').margin({ top: 12, bottom: 12 })
    if (this.cardLoading) {
      Column() {
        Text(this.cardProgress ? $r('app.string.card_progress', this.cardProgress) : $r('app.string.card_loading'))
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textHint)
          .margin({ top: 8 })
      }
      .width('100%')
      .padding(12)
      .justifyContent(FlexAlign.Center)
    }

    // Not logged in, or the site refused us: say which, in the site's terms.
    this.CampusUnavailable(AppLanguage.text($r('app.string.ui_campus_card'), this.languageRevision), this.cardError)

    if (this.cardInfo !== null) {
      // ── Balance card ──
      Column() {
        Row() {
          Text(AppLanguage.text($r('app.string.ui_card_balance'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeBody)
            .fontColor(ThemeColors.textSecondary)
          Blank()
          Text(this.cardInfo.name)
            .fontSize(ThemeDimens.textSizeSmall)
            .fontColor(ThemeColors.textHint)
        }
        .width('100%')

        Text(CardPresentation.balance(this.cardInfo.cash))
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(CampusContentStyle.signalColor(CampusSignal.amount(this.cardInfo.cash), ThemeColors.textSecondary))
          .margin({ top: 8 })
        if (CardPresentation.isLow(this.cardInfo.cash)) {
          Text($r('app.string.card_low_balance')).fontColor(CampusContentStyle.signalColor(CampusSignal.amount(this.cardInfo.cash), ThemeColors.textSecondary)).fontSize(12).margin({ top: 6 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
      .borderRadius(ThemeDimens.radiusLarge)

      // ── Transactions ──
      if (this.cardInfo.records.length > 0) {
        Text(this.cardDays === 0 ? $r('app.string.card_recent') : $r('app.string.card_records_days', this.cardDays))
          .fontSize(ThemeDimens.textSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .margin({ top: 20, bottom: 4 })

        ForEach(this.cardInfo.records, (item: CardRecord) => {
          Row() {
            Column() {
              Text(item.location.length > 0 ? item.location : item.type)
                .fontSize(ThemeDimens.textSizeTitle)
                .fontColor(ThemeColors.textPrimary)
              Text(item.time.replace('T', ' ') + ' · ' + item.type)
                .fontSize(ThemeDimens.textSizeSmall)
                .fontColor(ThemeColors.textHint)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text(CardPresentation.amount(item))
              .fontSize(ThemeDimens.textSizeTitle)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeColors.textPrimary)
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
          .borderRadius(ThemeDimens.radiusMedium)
          .margin({ top: 8 })
        })
      } else if (!this.cardLoading && !this.cardError) {
        // Distinguish "no transactions in range" from "failed to load": the
        // balance above proves the session worked, so an empty list here is
        // genuinely an empty list.
        Column() {
          Text(AppLanguage.text($r('app.string.ui_no_transactions_in_this_date_range'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeBody)
            .fontColor(ThemeColors.textSecondary)
        }
        .width('100%')
        .padding(32)
        .justifyContent(FlexAlign.Center)
      }
    }
  }
}
