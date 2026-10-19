import { ReadableText } from '../common/ReadableText'
import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { router } from '@kit.ArkUI'
import { AppLanguage } from '../common/AppLanguage'
import { AppState } from '../common/AppState'
import { Constant } from '../common/Constant'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { ClassroomPreference } from '../common/ClassroomPreference'
import { ClassroomPresentation } from '../common/ClassroomPresentation'
import { CampusPreference } from '../common/CampusPreference'
import { getSymbolIcon } from '../common/DanXiIcons'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { ClassroomSchedule, ScheduledClassroom, ClassroomScheduleParser } from '../model/ClassroomSchedule'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { TimetableHelper } from '../model/Academic'
import { ClassroomScheduleSource, DefaultClassroomScheduleSource } from '../repository/ClassroomScheduleRepository'
import { HttpError } from '../util/HttpUtil'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { PeriodTimeAxis } from '../components/PeriodTimeAxis'
import { ScheduleTimelineGrid } from '../components/ScheduleTimelineGrid'
import { TopFade } from '../components/TopFade'
import { ErrorNotice } from '../components/ErrorNotice'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { settleScrollTouch } from '../common/ScrollTouch'

class ClassroomGridSource implements IDataSource {
  rows: ScheduledClassroom[] = []
  listeners: DataChangeListener[] = []
  totalCount(): number { return this.rows.length }
  getData(index: number): ScheduledClassroom { return this.rows[index] }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener) }
  unregisterDataChangeListener(listener: DataChangeListener): void { const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1) }
  update(rows: ScheduledClassroom[]): void { this.rows = rows; for (const listener of this.listeners) listener.onDataReloaded() }
}

@Entry
@Component
export struct ClassroomSchedulePage {
  private detailTransition: SheetTransitionGuard = new SheetTransitionGuard()
  source: ClassroomScheduleSource = new DefaultClassroomScheduleSource()
  private scroller: Scroller = new Scroller()
  private grid: ClassroomGridSource = new ClassroomGridSource()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(CampusPreference.KEY) @Watch('systemCampusChanged') systemCampus: string = '邯郸'
  @StorageLink(ClassroomPreference.KEY_HIGH_CONTRAST) highContrast: boolean = false
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') personJson: string = ''
  @State private campus: string = CampusPreference.current()
  @State private building: string = 'HGD'
  @State private day: string = ClassroomPresentation.day(new Date())
  @State private query: string = ''
  @State private rooms: ScheduledClassroom[] = []
  @State private visibleCount: number = 0
  @State private periodCount: number = 13
  @State private calendarOpacity: number = 1
  @State private error: string = ''
  @State private loading: boolean = false
  @State private verifying: boolean = false
  @State private verification: boolean = false
  @State private refreshing: boolean = false
  @State private detail: boolean = false
  @State private selected: ClassroomSchedule = new ClassroomSchedule()
  @State private selectedRoom: ScheduledClassroom = new ScheduledClassroom()
  private active: boolean = false
  private revision: number = 0
  private owner: string = ''
  private flightKey: string = ''
  private flight: Promise<void> | null = null
  private resume: boolean = false
  private resumeRead: boolean = false
  private initialized: boolean = false
  private campusScope: string = ''

  aboutToAppear(): void { this.active = true; this.initialize() }
  private async initialize(): Promise<void> {
    this.initialized = false
    this.campusScope = CampusPreference.current(); this.campus = this.campusScope
    const revision: number = this.revision
    const saved: string = await ClassroomPreference.building(this.campus).catch(() => ClassroomPresentation.buildings(this.campus)[0])
    if (!this.active || revision !== this.revision) return
    this.initialized = true
    this.building = ClassroomScheduleParser.normalizeBuilding(saved); this.campus = ClassroomScheduleParser.campus(this.building); this.load(false)
  }
  onPageShow(): void {
    this.active = true
    if (this.campusScope && this.campusScope !== CampusPreference.current()) { this.systemCampusChanged(); return }
    if (!this.initialized) { this.initialize(); return }
    if (this.resume) { this.resume = false; this.load(true) }
    else if (this.resumeRead) { this.resumeRead = false; this.load(false) }
    else if (this.owner && this.owner !== this.source.owner()) this.accountChanged()
  }
  systemCampusChanged(): void {
    if (!this.active || this.campusScope === CampusPreference.current()) return
    this.revision++; this.rooms = []; this.updateGrid(); this.detail = false; this.initialize()
  }
  onPageHide(): void { this.resumeRead = this.resumeRead || this.loading; this.active = false; this.refreshing = false }
  aboutToDisappear(): void { this.active = false; this.revision++; this.loading = false; this.refreshing = false; this.flight = null }
  accountChanged(): void { if (!this.active || this.owner === this.source.owner()) return; this.rooms = []; this.updateGrid(); this.detail = false; this.load(false) }
  private load(force: boolean): Promise<void> {
    if (!this.active || this.verifying) return Promise.resolve()
    this.resumeRead = false
    const key: string = this.source.owner() + '/' + this.building + '/' + this.day
    if (this.flight !== null && key === this.flightKey) return this.flight
    this.flightKey = key
    const task = this.read(force); this.flight = task
    task.finally(() => { if (this.flight === task) this.flight = null }); return task
  }
  private async read(force: boolean): Promise<void> {
    const revision: number = ++this.revision, owner: string = this.source.owner()
    this.owner = owner; this.loading = true; this.error = ''; this.verification = false
    try {
      const rooms = await this.source.read(this.building, this.day, force)
      if (!this.active || revision !== this.revision || owner !== this.source.owner()) return
      this.calendarOpacity = 0; this.rooms = rooms; this.updateGrid()
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.calendarOpacity = 1 })
    } catch (e) {
      if (this.active && revision === this.revision && owner === this.source.owner()) {
        this.error = ErrorDiagnostics.message(e as Object); this.verification = e instanceof HttpError && e.statusCode === -2
      }
    } finally { if (revision === this.revision) { this.loading = false; this.refreshing = false } }
  }
  private async verify(): Promise<void> {
    if (this.verifying || this.loading) return
    if (this.source instanceof DefaultClassroomScheduleSource && !AppState.isLoggedIn()) { await router.pushUrl({ url: 'pages/LoginPage' }); return }
    this.verifying = true
    try { await this.source.verify(); this.verifying = false; if (this.active) this.load(true); else this.resume = true }
    catch (e) { if (this.active) this.error = ErrorDiagnostics.message(e as Object) }
    finally { this.verifying = false }
  }
  private updateGrid(): void {
    const rows = ClassroomScheduleParser.search(this.rooms, this.query)
    let periods: number = 13
    for (const room of this.rooms) periods = Math.max(periods, room.periodCount)
    this.periodCount = periods; this.grid.update(rows); this.visibleCount = rows.length
  }
  private chooseBuilding(building: string): void {
    if (building === this.building) return
    this.building = building; this.campus = ClassroomScheduleParser.campus(building); this.rooms = []; this.updateGrid()
    ClassroomPreference.remember(this.campus, building).catch(() => {}); this.load(false)
  }
  private chooseDate(): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.day + 'T12:00:00'),
      start: ClassroomPresentation.dateOffset(new Date(), -1), end: ClassroomPresentation.dateOffset(new Date(), 14),
      onDateAccept: (date: Date): void => { const day = ClassroomPresentation.day(date); if (day === this.day) return; this.day = day; this.rooms = []; this.updateGrid(); this.load(false) } })
  }
  private buildingName(building: string): string {
    const names: Record<string, Resource> = { 'H2': $r('app.string.classroom_building_h2'), 'H3': $r('app.string.classroom_building_h3'),
      'H4': $r('app.string.classroom_building_h4'), 'H5': $r('app.string.classroom_building_h5'), 'H6': $r('app.string.classroom_building_h6'),
      'HGX': $r('app.string.classroom_building_hgx'), 'HGD': $r('app.string.classroom_building_hgd'), 'HQ': $r('app.string.classroom_building_hq'),
      'F': $r('app.string.classroom_building_f'), 'J': $r('app.string.classroom_building_j'), 'Z': $r('app.string.classroom_building_z') }
    return AppLanguage.text(names[building] ?? $r('app.string.classroom_building'), this.languageRevision)
  }
  private open(room: ScheduledClassroom, schedule: ClassroomSchedule): void {
    this.detailTransition.open(() => {
      if (!this.active) return
      this.selectedRoom = room; this.selected = schedule; this.detail = true
    }, () => this.getUIContext())
  }
  private eventColor(schedule: ClassroomSchedule): ResourceColor {
    const colors: ResourceColor[] = [$r('app.color.campus_palette_indigo'), $r('app.color.campus_palette_teal'), $r('app.color.campus_palette_blue'), $r('app.color.campus_palette_violet')]
    let hash: number = 0; for (let i: number = 0; i < schedule.name.length; i++) hash = (hash * 31 + schedule.name.charCodeAt(i)) >>> 0
    return colors[hash % colors.length]
  }
  @Builder
  BuildingChoices() {
    Menu() {
      ForEach(ClassroomScheduleParser.BUILDINGS, (building: string) => {
        MenuItem({ content: this.buildingName(building) }).selected(building === this.building).selectIcon(true).onClick(() => { this.chooseBuilding(building) })
      }, (building: string): string => building)
    }
  }
  @Builder
  Filters() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text($r('app.string.classroom_building')).fontSize(12).fontColor(ThemeColors.textSecondary)
        Row({ space: 6 }) { Text(this.buildingName(this.building)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          SymbolGlyph(getSymbolIcon('expand')).fontSize(14).fontColor([ThemeColors.textSecondary]) }
          .width('100%').height(40).id('classroom-building-filter').bindMenu(this.BuildingChoices())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 6 }) {
        Text($r('app.string.classroom_query_date')).fontSize(12).fontColor(ThemeColors.textSecondary)
        Row({ space: 6 }) { Text(this.day).fontSize(15).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          SymbolGlyph(getSymbolIcon('expand')).fontSize(14).fontColor([ThemeColors.textSecondary]) }
          .width('100%').height(40).id('classroom-date-filter').onClick(() => { this.chooseDate() })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding(ThemeDimens.cardInset).backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
    Row({ space: 8 }) {
      TextInput({ text: this.query, placeholder: $r('app.string.classroom_schedule_search') }).layoutWeight(1).height(44)
        .backgroundColor(Color.Transparent).fontSize(15).fontColor(ThemeColors.textPrimary).defaultFocus(false).id('classroom-search')
        .onChange((value: string) => { this.query = value; this.updateGrid() })
      if (this.query) Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(20).fontColor([ThemeColors.textSecondary]) }
        .width(36).height(36).backgroundColor(Color.Transparent).id('classroom-search-clear').onClick(() => { this.query = ''; this.updateGrid() })
    }.width('100%').padding({ left: 4, right: 8 }).backgroundColor($r('app.color.campus_search_surface')).borderRadius(24)
  }
  @Builder
  RoomColumn(room: ScheduledClassroom) {
    Column() {
      Column({ space: 3 }) { Text(room.room).fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).maxLines(1)
        Text(AppLanguage.text($r('app.string.classroom_capacity'), this.languageRevision, room.capacity)).fontSize(11).fontColor(ThemeColors.textSecondary) }
        .width(112).height(56).justifyContent(FlexAlign.Center)
      Stack({ alignContent: Alignment.TopStart }) {
        ScheduleTimelineGrid({ periodCount: this.periodCount, rowHeight: 64, freePeriods: room.freePeriods,
          highContrast: this.highContrast })
        ForEach(room.schedules, (schedule: ClassroomSchedule) => {
          Column({ space: 4 }) {
            Text(schedule.name).fontSize(13).lineHeight(19).fontWeight(FontWeight.Medium)
              .fontColor(this.highContrast ? $r('app.color.theme_bg_start') : ThemeColors.textPrimary)
              .maxLines(Math.max(1, Math.floor((schedule.end - schedule.start + 1) * 64 / 22) - 1)).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (schedule.end > schedule.start && schedule.teacher) Text(schedule.teacher).fontSize(11)
              .fontColor(this.highContrast ? $r('app.color.theme_bg_start') : ThemeColors.textSecondary).maxLines(1)
          }.width(104).height((schedule.end - schedule.start + 1) * 64 - 6).padding(8).alignItems(HorizontalAlign.Start)
            .backgroundColor(this.highContrast ? ThemeColors.textPrimary : $r('app.color.calendar_event_surface')).borderRadius(6)
            .border({ width: { left: 3 }, color: this.eventColor(schedule) })
            .position({ x: 4, y: (schedule.start - 1) * 64 + 3 }).id('classroom-event-' + room.room + '-' + schedule.start)
            .onClick(() => { this.open(room, schedule) }).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
        }, (schedule: ClassroomSchedule): string => String(schedule.start) + schedule.courseId + schedule.name)
      }.width(112).height(this.periodCount * 64).clip(true)
    }.width(112).backgroundColor($r('app.color.surface_fallback'))
  }
  @Builder
  Calendar() {
    Row({ space: 0 }) {
      Column() {
        Text($r('app.string.timetable_period_times')).fontSize(11).lineHeight(16).fontColor(ThemeColors.textSecondary)
          .width(52).height(56).textAlign(TextAlign.Center)
        PeriodTimeAxis({ periodCount: this.periodCount, rowHeight: 64, axisWidth: 52, controlPrefix: 'classroom-period-' })
      }
      if (this.visibleCount === 0) Column() {
        Text($r('app.string.classroom_room')).width('100%').height(56).fontSize(14).fontColor(ThemeColors.textSecondary).textAlign(TextAlign.Center)
        Stack({ alignContent: Alignment.Top }) {
          ScheduleTimelineGrid({ periodCount: this.periodCount, rowHeight: 64, highContrast: this.highContrast })
        }.width('100%').height(this.periodCount * 64)
      }.layoutWeight(1).height(56 + this.periodCount * 64).backgroundColor($r('app.color.surface_fallback'))
      else List({ space: 0 }) {
        LazyForEach(this.grid, (room: ScheduledClassroom) => { ListItem() { this.RoomColumn(room) } },
          (room: ScheduledClassroom): string => JSON.stringify(room))
      }.layoutWeight(1).height(56 + this.periodCount * 64).listDirection(Axis.Horizontal).scrollBar(BarState.Off).cachedCount(2)
    }.width('100%').height(56 + this.periodCount * 64).backgroundColor($r('app.color.surface_fallback')).borderRadius(20).clip(true).alignItems(VerticalAlign.Top).opacity(this.calendarOpacity)
  }
  @Builder
  Field(label: ResourceStr, value: string) {
    if (value) Row({ space: 16 }) { Text(label).fontSize(13).fontColor(ThemeColors.textSecondary).width(70)
      Text(value).fontSize(15).lineHeight(23).fontColor(ThemeColors.textPrimary).layoutWeight(1).copyOption(CopyOptions.LocalDevice) }.width('100%')
  }
  @Builder
  EventDetail() {
    Column({ space: 16 }) {
      Text(this.selected.name).fontSize(20).lineHeight(28).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
      this.Field($r('app.string.classroom_query_date'), this.day)
      this.Field($r('app.string.classroom_room'), this.selectedRoom.room)
      this.Field($r('app.string.classroom_period'), AppLanguage.text($r('app.string.classroom_range'), this.languageRevision, this.selected.start, this.selected.end))
      this.Field($r('app.string.classroom_course_id'), this.selected.courseId)
      this.Field($r('app.string.classroom_teacher'), this.selected.teacher)
      this.Field($r('app.string.classroom_category'), this.selected.category)
      this.Field($r('app.string.classroom_enrollment'), this.selected.enrollment)
    }.width('100%').padding({ left: 20, right: 20, top: 48, bottom: Math.max(24, px2vp(this.bottomPx)) + 12 })
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
        Scroll(this.scroller) {
          Column({ space: 14 }) {
            this.Filters()
            Text(ReadableText.resource($r('app.string.classroom_schedule_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
            if (this.error) Column({ space: 14 }) {
              ErrorNotice({ message: this.error, controlId: 'classroom-diagnostics' })
              if (this.verification) FloatingActionButton({ label: this.source instanceof DefaultClassroomScheduleSource && !AppState.isLoggedIn() ? $r('app.string.ui_log_in_to_campus_account') : $r('app.string.campus_verify_continue'), actionEnabled: !this.verifying, onAction: () => { this.verify() } }).width(176)
              else FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44, onAction: () => { this.load(true) } }).width(44)
            }.width('100%').padding(20).borderRadius(20).backgroundColor($r('app.color.surface_fallback'))
            if (this.visibleCount > 0 || (!this.loading && !this.error)) this.Calendar()
          }.width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: px2vp(this.topPx) + 76, bottom: Math.max(20, px2vp(this.bottomPx)) + 24 })
        }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) })
      CenterLoadingProgress({ busy: this.loading })
      TopFade({ extent: px2vp(this.topPx) + 62 })
      Row({ space: 12 }) {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 44, onAction: () => { router.back() } }).width(44)
        Text($r('app.string.feature_empty_classroom')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44, actionEnabled: !this.loading && !this.verifying,
          controlId: 'classroom-refresh', onAction: () => { this.verification ? this.verify() : this.load(true) } }).width(44)
      }.height(56).width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter }).margin({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgEnd).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.detail, this.EventDetail(), this.detailTransition.options(this.detail, { height: SheetSize.FIT_CONTENT, showClose: true, dragBar: false }))
  }
}
