import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { router } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { AppLanguage } from '../common/AppLanguage'
import { AppState } from '../common/AppState'
import { Constant } from '../common/Constant'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { CampusPreference } from '../common/CampusPreference'
import { CampusFilterPreference } from '../common/CampusFilterPreference'
import { BookingBitmapCache } from '../util/BookingBitmapCache'
import { getSymbolIcon } from '../common/DanXiIcons'
import { BookingVenueImage } from '../components/BookingVenueImage'
import { BookingImageCache } from '../util/BookingImageCache'
import { VenueImageReader } from '../util/BookingBitmapCache'
import { BookingBrowserSession } from '../components/BookingBrowserSession'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ClassroomPresentation } from '../common/ClassroomPresentation'
import { SportsBooking, BookingVenue, BookingDetail, BookingCalendar, BookingPeriod, BookingPeriodDetail, BookingAppointment, BookingOccupant, BookingField, BookingCollected, BookingLaunch } from '../model/SportsBooking'
import { SportsBookingSource, SportsBookingRepository } from '../repository/SportsBookingRepository'
import { HttpError } from '../util/HttpUtil'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { CampusActionLabel } from '../components/CampusActionLabel'
import { TopFade } from '../components/TopFade'
import { ErrorNotice } from '../components/ErrorNotice'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { settleScrollTouch } from '../common/ScrollTouch'

class BookingVenueList implements IDataSource {
  rows: BookingVenue[] = []
  private listeners: DataChangeListener[] = []
  totalCount(): number { return this.rows.length }
  getData(index: number): BookingVenue { return this.rows[index] }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener) }
  unregisterDataChangeListener(listener: DataChangeListener): void { const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1) }
  update(rows: BookingVenue[]): void {
    if (rows.length === this.rows.length && rows.every((row: BookingVenue, index: number): boolean => row === this.rows[index])) return
    this.rows = rows; for (const listener of this.listeners) listener.onDataReloaded()
  }
}

@Entry
@Component
export struct SportsBookingPage {
  private webSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private sheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  source: SportsBookingSource = new SportsBookingRepository()
  imageReader: VenueImageReader = (token: string): Promise<ArrayBuffer> => BookingImageCache.read(token)
  private scroller: Scroller = new Scroller()
  private browser: webview.WebviewController = new webview.WebviewController()
  private venueList: BookingVenueList = new BookingVenueList()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(CampusPreference.KEY) @Watch('systemCampusChanged') systemCampus: string = '邯郸'
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') person: string = ''
  @State private view: string = 'list'
  private venues: BookingVenue[] = []
  @State private visibleCount: number = 0
  @State private detail: BookingDetail = new BookingDetail()
  @State private calendar: BookingCalendar = new BookingCalendar()
  @State private appointments: BookingAppointment[] = []
  @State @Watch('filterChanged') private campus: string = ''
  @State @Watch('filterChanged') private type: string = ''
  @State @Watch('filterChanged') private environment: string = ''
  @State @Watch('filterChanged') private query: string = ''
  @State private day: string = ClassroomPresentation.day(new Date())
  @State private loading: boolean = false
  @State private verifying: boolean = false
  @State private switching: boolean = false
  @State private contentOpacity: number = 1
  @State private paging: boolean = false
  @State private more: boolean = false
  @State private error: string = ''
  @State private verification: boolean = false
  @State private refreshing: boolean = false
  @State private pullOffset: number = 0
  @State private sheet: boolean = false
  @State private sheetKind: string = ''
  @State private period: BookingPeriod = { id: 0, str_time: '', start_time: '', end_time: '' }
  @State private occupants: BookingOccupant[] = []
  @State private occupantsMore: boolean = false
  @State private values: Record<string, string> = {}
  @State private number: number = 1
  @State private sheetBusy: boolean = false
  @State private sheetError: string = ''
  @State private webSheet: boolean = false
  @State private webUrl: string = ''
  @State private cancellation: number = 0
  private active: boolean = false
  private revision: number = 0
  private owner: string = ''
  private page: number = 1
  private occupantPage: number = 1
  private savedOffset: number = 0
  private pendingView: string = ''
  private resume: boolean = false
  private lifetime: number = 0
  private catalogueLoaded: boolean = false
  private filterCampusScope: string = ''
  aboutToAppear(): void { this.lifetime++; this.active = true; this.restoreCampus() }
  private async restoreCampus(): Promise<void> {
    const lifetime: number = this.lifetime, scope: string = CampusPreference.current()
    this.filterCampusScope = scope; this.campus = scope
    const selected: string = await CampusFilterPreference.read('booking', scope, true).catch(() => scope)
    if (!this.active || lifetime !== this.lifetime || scope !== CampusPreference.current()) return
    this.campus = selected; this.load(false)
  }
  systemCampusChanged(): void {
    if (!this.active || this.filterCampusScope === CampusPreference.current()) return
    this.filterCampusScope = CampusPreference.current(); this.campus = this.filterCampusScope
    this.filterChanged()
  }
  private chooseCampus(index: number): void {
    this.campus = index ? CampusPreference.CHOICES[index - 1] : ''
    CampusFilterPreference.remember('booking', this.campus, true).catch(() => {})
  }
  onPageShow(): void {
    this.active = true
    this.systemCampusChanged()
    if (this.owner && this.owner !== this.source.owner()) this.accountChanged()
    else if (this.resume && !this.verifying) { this.resume = false; this.load(true) }
    else if (this.pendingView && !this.verifying) this.commitView(this.pendingView)
  }
  onPageHide(): void { this.resume = this.resume || this.loading; this.active = false; this.revision++; this.loading = false; this.paging = false; this.refreshing = false }
  aboutToDisappear(): void { this.lifetime++; this.active = false; this.revision++; this.pendingView = ''; this.resume = false }
  filterChanged(): void { const rows = SportsBooking.filter(this.venues, this.query, this.campus, this.type, this.environment); this.venueList.update(rows); this.visibleCount = rows.length }
  onBackPress(): boolean { if (this.view !== 'list' || this.pendingView) { this.back(); return true } return false }
  accountChanged(): void {
    if (!this.active || this.owner === this.source.owner()) return
    this.revision++; this.loading = false; this.paging = false; this.switching = false; this.pendingView = ''; this.contentOpacity = 1
    if (this.view === 'detail') this.view = 'list'
    this.venues = []; this.catalogueLoaded = false; this.filterChanged(); this.appointments = []; this.sheet = false; this.webSheet = false; this.resume = false; this.load(false)
  }
  private async load(force: boolean): Promise<void> {
    if (!this.active || this.loading) return
    if (force) BookingBitmapCache.retryFailures()
    const revision: number = ++this.revision, owner = this.source.owner(), view = this.view
    this.owner = owner; this.loading = true; this.error = ''; this.verification = false
    try {
      if (view === 'list') {
        const venues = await this.source.venues(force)
        // Commit to the lazy data source explicitly; do not depend on a State
        // array watch firing after ArkUI's proxy has replaced that array.
        if (this.active && revision === this.revision && owner === this.source.owner()) { this.venues = venues; this.catalogueLoaded = true; this.filterChanged() }
      } else if (view === 'appointments') {
        const result = await this.source.appointments(1, force)
        if (this.active && revision === this.revision && owner === this.source.owner()) { this.appointments = result.rows; this.more = result.hasMore; this.page = 1 }
      } else {
        const id: number = this.detail.id, day: string = this.day
        const detail = await this.source.detail(id, force)
        if (!this.active || revision !== this.revision || owner !== this.source.owner()) return
        this.detail = detail
        const calendar = detail.usable ? await this.source.calendar(id, day, force) : new BookingCalendar()
        if (this.active && revision === this.revision && owner === this.source.owner()) this.calendar = calendar
      }
    } catch (e) { if (this.active && revision === this.revision) { this.error = ErrorDiagnostics.message(e as Object); this.verification = e instanceof HttpError && e.statusCode === -2 } }
    finally { if (revision === this.revision) {
      this.loading = false; this.refreshing = false; this.switching = false
      if (this.active) this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.contentOpacity = 1 })
    } }
  }
  private async verify(): Promise<void> {
    if (this.loading || this.verifying || this.switching) return
    if (this.source instanceof SportsBookingRepository && !AppState.isLoggedIn()) { this.resume = true; await router.pushUrl({ url: 'pages/LoginPage' }); return }
    this.verifying = true
    const lifetime: number = this.lifetime
    let completed: boolean = false
    try { await this.source.verify(); completed = true }
    catch (e) { if (this.active) this.error = ErrorDiagnostics.message(e as Object) }
    finally { this.verifying = false }
    if (completed && lifetime === this.lifetime) { this.resume = true; if (this.active) { this.resume = false; await this.load(true) } }
  }
  private open(venue: BookingVenue): void {
    if (this.switching || this.verifying) return
    this.savedOffset = this.scroller.currentOffset().yOffset
    const detail = new BookingDetail(); detail.id = venue.id; detail.name = venue.name; detail.image = venue.image
    this.detail = detail; this.changeView('detail')
  }
  private myAppointments(): void {
    if (this.switching || this.verifying) return
    this.savedOffset = this.scroller.currentOffset().yOffset; this.changeView('appointments')
  }
  private changeView(view: string): void {
    const revision: number = ++this.revision
    this.pendingView = view; this.loading = false; this.paging = false; this.switching = true; this.more = false
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut, onFinish: () => {
      if (this.active && revision === this.revision && this.pendingView === view) this.commitView(view)
    } }, () => { this.contentOpacity = 0 })
  }
  private commitView(view: string): void {
    // Swap the list only after fade-out; native animation never animates the
    // replacement cards' geometry or the parent page's background.
    this.pendingView = ''; this.view = view; this.error = ''; this.verification = false
    this.scroller.scrollTo({ xOffset: 0, yOffset: view === 'list' ? this.savedOffset : 0 })
    if (view === 'list') {
      if (!this.catalogueLoaded) this.load(false)
      else {
        this.filterChanged(); this.switching = false
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.contentOpacity = 1 })
      }
    } else { this.appointments = []; this.calendar = new BookingCalendar(); this.load(false) }
  }
  private back(): void {
    if (this.view === 'list' && !this.pendingView) { router.back(); return }
    this.changeView('list')
  }
  private async nextAppointments(): Promise<void> {
    if (this.paging || this.loading || !this.more || this.view !== 'appointments') return
    this.paging = true; const revision = this.revision
    try { const result = await this.source.appointments(this.page + 1, false)
      if (this.active && revision === this.revision) { this.appointments = this.appointments.concat(result.rows.filter((row: BookingAppointment) => !this.appointments.some((old: BookingAppointment) => old.id === row.id))); this.page++; this.more = result.hasMore }
    } catch (e) { if (this.active && revision === this.revision) this.error = ErrorDiagnostics.message(e as Object) }
    finally { if (revision === this.revision) this.paging = false }
  }
  private date(): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.day + 'T12:00:00'), start: new Date(), end: ClassroomPresentation.dateOffset(new Date(), 3),
      onDateAccept: (value: Date): void => { const day = ClassroomPresentation.day(value); if (day !== this.day) { this.day = day; this.revision++; this.loading = false; this.load(false) } } })
  }
  private form(period: BookingPeriod): void {
    this.sheetTransition.open(() => { if (this.active) this.loadForm(period) }, () => this.getUIContext())
  }
  private async loadForm(period: BookingPeriod): Promise<void> {
    if (this.sheetBusy || !this.detail.usable || this.calendar.available(this.day, period.id).length === 0) return
    this.period = period; this.sheetError = ''; this.sheetKind = 'form'; this.values = {}; this.number = 1; this.sheet = true
    const id = this.detail.id, owner = this.owner
    try { const contact = await this.source.contact()
      if (this.active && this.sheet && this.sheetKind === 'form' && this.detail.id === id && owner === this.source.owner()) {
        const values: Record<string, string> = {}; for (const key of Object.keys(this.values)) values[key] = this.values[key]
        for (const field of this.detail.fields) if ((field.type === 'mobile' || /手机|联系电话|mobile|phone/i.test(field.name)) && !values[field.name]?.trim()) values[field.name] = contact.mobile
        this.values = values
      }
    } catch (e) { /* Contact prefill is optional; the user can enter the requested fields. */ }
  }
  private async submit(): Promise<void> {
    if (this.sheetBusy || !this.sheet || this.sheetKind !== 'form' || this.detail.captcha) return
    const fields: BookingCollected[] = this.detail.fields.map((field: BookingField): BookingCollected => ({ name: field.name, value: this.values[field.name] ?? '', type: field.type, verify: field.verifyType }))
    if (fields.some((field: BookingCollected) => field.verify === 'required' && !field.value.trim())) { this.sheetError = AppLanguage.text($r('app.string.booking_required')); return }
    const value: BookingLaunch = { group: this.detail.id, resources: this.calendar.resource.map(row => row.id), date: this.day, period: this.period.id, number: this.number, fields }
    this.sheetBusy = true; const owner = this.owner
    try { await this.source.launch(value)
      if (this.active && owner === this.source.owner()) { this.sheet = false; this.load(true); this.getUIContext().getPromptAction().showToast({ message: AppLanguage.text($r('app.string.booking_success')) }) }
    } catch (e) { if (this.active) this.sheetError = ErrorDiagnostics.message(e as Object) }
    finally { this.sheetBusy = false }
  }
  private info(period: BookingPeriod, next: boolean = false): void {
    if (next) { this.loadInfo(period, true); return }
    this.sheetTransition.open(() => { if (this.active) this.loadInfo(period) }, () => this.getUIContext())
  }
  private async loadInfo(period: BookingPeriod, next: boolean = false): Promise<void> {
    if (this.sheetBusy) return
    if (!next) { this.period = period; this.occupantPage = 1; this.occupants = []; this.sheetKind = 'occupants'; this.sheet = true }
    this.sheetBusy = true; this.sheetError = ''; const id = this.detail.id, day = this.day, owner = this.owner
    try { const result = await this.source.occupants(id, this.calendar.resource.map(row => row.id), day, period, this.occupantPage)
      if (this.active && this.sheet && this.sheetKind === 'occupants' && owner === this.source.owner() && id === this.detail.id && this.period.id === period.id && day === this.day) {
        this.occupants = next ? this.occupants.concat(result.rows) : result.rows; this.occupantsMore = result.hasMore; this.occupantPage++
      }
    } catch (e) { if (this.active && this.sheet) this.sheetError = ErrorDiagnostics.message(e as Object) }
    finally { this.sheetBusy = false }
  }
  private confirmCancel(row: BookingAppointment): void {
    if (this.cancellation) return
    this.getUIContext().showAlertDialog({ title: AppLanguage.text($r('app.string.booking_cancel')), message: row.name,
      primaryButton: { value: AppLanguage.text($r('app.string.settings_cancel')), action: () => {} },
      secondaryButton: { value: AppLanguage.text($r('app.string.booking_cancel_confirm')), action: () => { this.cancel(row) } } })
  }
  private async cancel(row: BookingAppointment): Promise<void> {
    if (this.cancellation) return
    this.cancellation = row.id; const owner = this.owner
    try { await this.source.cancel(row.id, row.periods.filter(period => SportsBooking.boolean(period.can_cancel)).map(period => period.detail_id)); if (this.active && owner === this.source.owner()) this.load(true) }
    catch (e) { if (this.active) DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.booking_action_failed'))) }
    finally { this.cancellation = 0 }
  }
  private openWeb(): void { this.webUrl = SportsBooking.page(this.detail.id); this.sheet = false; setTimeout(() => {
    this.webSheetTransition.open(() => { if (this.active) this.webSheet = true }, () => this.getUIContext())
  }, 240) }
  @Builder
  Filters() {
    Row({ space: 12 }) { SymbolGlyph(getSymbolIcon('history')).fontSize(22).fontColor([ThemeColors.primary]); Text($r('app.string.booking_my_reservations')).fontSize(16).fontColor(ThemeColors.textPrimary).layoutWeight(1); SymbolGlyph(getSymbolIcon('forward')).fontSize(14).fontColor([ThemeColors.textSecondary]) }
      .width('100%').padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(20).id('booking-my-reservations').onClick(() => { this.myAppointments() })
    Row({ space: 8 }) {
      TextInput({ text: this.query, placeholder: $r('app.string.booking_search') }).layoutWeight(1).height(44).fontColor(ThemeColors.textPrimary).backgroundColor(Color.Transparent).defaultFocus(false).id('booking-search').onChange((value: string) => { this.query = value })
      if (this.query) Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(20).fontColor([ThemeColors.textSecondary]) }.width(36).height(36).backgroundColor(Color.Transparent).onClick(() => { this.query = '' })
    }.width('100%').padding({ left: 4, right: 8 }).backgroundColor($r('app.color.campus_search_surface')).borderRadius(24)
    Column({ space: 10 }) {
      Row({ space: 10 }) { SymbolGlyph(getSymbolIcon('location')).fontSize(18).fontColor([ThemeColors.primary])
        Text($r('app.string.live_query_campus')).layoutWeight(1).fontColor(ThemeColors.textSecondary)
        Select(['', ...CampusPreference.CHOICES].map((value: string): SelectOption => ({ value: value || AppLanguage.text($r('app.string.reservation_all_campuses')) }))).selected(this.campus ? CampusPreference.CHOICES.indexOf(this.campus) + 1 : 0)
          .value(this.campus || $r('app.string.reservation_all_campuses')).id('booking-campus').onSelect((index: number) => { this.chooseCampus(index) }) }
      Row({ space: 10 }) { SymbolGlyph(getSymbolIcon('sports')).fontSize(18).fontColor([ThemeColors.primary])
        Text($r('app.string.booking_type')).layoutWeight(1).fontColor(ThemeColors.textSecondary)
        Select(['', ...SportsBooking.TYPES].map((value: string): SelectOption => ({ value: value || AppLanguage.text($r('app.string.reservation_all_categories')) }))).selected(this.type ? SportsBooking.TYPES.indexOf(this.type) + 1 : 0)
          .value(this.type || $r('app.string.reservation_all_categories')).id('booking-type').onSelect((index: number) => { this.type = index ? SportsBooking.TYPES[index - 1] : '' }) }
      Row({ space: 10 }) { SymbolGlyph(getSymbolIcon('empty_classroom')).fontSize(18).fontColor([ThemeColors.primary])
        Text($r('app.string.booking_environment')).layoutWeight(1).fontColor(ThemeColors.textSecondary)
        Select([{ value: AppLanguage.text($r('app.string.reservation_all_categories')) }, { value: '室内' }, { value: '室外' }]).selected(this.environment === '室内' ? 1 : this.environment === '室外' ? 2 : 0)
          .value(this.environment || $r('app.string.reservation_all_categories')).id('booking-environment').onSelect((index: number) => { this.environment = index === 1 ? '室内' : index === 2 ? '室外' : '' }) }
    }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
  }
  @Builder
  Venue(row: BookingVenue) {
    Row({ space: 14 }) {
      BookingVenueImage({ token: row.image, name: row.name, imageReader: this.imageReader }).width(96).height(64)
      Column({ space: 6 }) { Text(row.name).fontSize(17).lineHeight(25).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%')
        if (row.introduction) Text(row.introduction).fontSize(13).lineHeight(20).fontColor(ThemeColors.textSecondary).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%') }.layoutWeight(1)
      SymbolGlyph(getSymbolIcon('forward')).fontSize(14).fontColor([ThemeColors.textSecondary])
    }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(22).id('booking-venue-' + row.id).onClick(() => { this.open(row) })
  }
  @Builder
  VenueDetail() {
    BookingVenueImage({ token: this.detail.image, name: this.detail.name, large: true, imageReader: this.imageReader }).width('100%').height(180)
    if (this.detail.introduction || this.detail.rules) Column({ space: 12 }) {
      if (this.detail.introduction) Text(this.detail.introduction).fontSize(14).lineHeight(23).fontColor(ThemeColors.textSecondary).width('100%')
      if (this.detail.rules) Button() { CampusActionLabel({ label: $r('app.string.booking_rules'), symbol: getSymbolIcon('license') }) }
        .height(40).backgroundColor(Color.Transparent).id('booking-rules').onClick(() => { this.sheetTransition.open(() => {
          if (this.active) { this.sheetKind = 'rules'; this.sheetError = ''; this.sheet = true }
        }, () => this.getUIContext()) })
    }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
    Row() { Text($r('app.string.reservation_date')).fontColor(ThemeColors.textSecondary).layoutWeight(1)
      Button() { CampusActionLabel({ label: this.day, symbol: getSymbolIcon('timetable') }) }
        .height(40).backgroundColor(Color.Transparent).id('booking-date').onClick(() => { this.date() }) }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
    if (!this.loading && !this.error && !this.detail.usable) Text(this.detail.limit || $r('app.string.booking_unavailable')).fontColor(ThemeColors.textSecondary).width('100%').padding(16)
    ForEach(this.calendar.time, (period: BookingPeriod) => {
      Row({ space: 12 }) {
        Column({ space: 6 }) { Row({ space: 8 }) { Text(period.str_time).fontSize(19).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          if (this.calendar.available(this.day, period.id).length < this.calendar.resource.length) Button({ type: ButtonType.Circle }) { SymbolGlyph(getSymbolIcon('about')).fontSize(19).fontColor([ThemeColors.textSecondary]) }.width(32).height(32).backgroundColor(Color.Transparent).id('booking-info-' + period.id).onClick(() => { this.info(period) }) }
          Text(AppLanguage.text($r('app.string.booking_available'), this.languageRevision, this.calendar.available(this.day, period.id).length)).fontSize(13).fontColor(this.calendar.available(this.day, period.id).length > 0 ? CampusContentStyle.available : ThemeColors.textSecondary) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button() { CampusActionLabel({ label: this.calendar.available(this.day, period.id).length > 0 ? $r('app.string.booking_reserve') : $r('app.string.booking_full'),
          symbol: this.calendar.available(this.day, period.id).length > 0 ? $r('sys.symbol.plus') : getSymbolIcon('lock'), color: Color.White }) }
          .height(40).backgroundColor(ThemeColors.primary).enabled(this.calendar.available(this.day, period.id).length > 0).id('booking-reserve-' + period.id).onClick(() => { this.form(period) })
      }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
    }, (period: BookingPeriod): string => String(period.id))
    if (!this.loading && !this.error && this.detail.usable && this.calendar.time.length === 0) Text($r('app.string.booking_no_times')).fontColor(ThemeColors.textSecondary).width('100%').padding(16)
  }
  @Builder
  Appointment(row: BookingAppointment) {
    Column({ space: 12 }) {
      Row({ space: 12 }) { Text(row.name).fontSize(17).fontWeight(FontWeight.Bold).lineHeight(25).fontColor(ThemeColors.textPrimary).layoutWeight(1); Text(row.status).fontSize(13).fontColor(ThemeColors.primary) }.width('100%')
      ForEach(row.periods, (period: BookingPeriodDetail) => { Text(period.date + '  ' + period.str_time).fontSize(14).lineHeight(22).fontColor(ThemeColors.textSecondary).width('100%') }, (period: BookingPeriodDetail): string => String(period.detail_id))
      if (row.canCancel && row.periods.some((period: BookingPeriodDetail) => SportsBooking.boolean(period.can_cancel))) Button() {
        CampusActionLabel({ label: $r('app.string.booking_cancel_confirm'), symbol: getSymbolIcon('delete'), color: CampusContentStyle.attention })
      }.height(40).backgroundColor(Color.Transparent).enabled(this.cancellation === 0).opacity(this.cancellation === row.id ? 0.5 : 1).id('booking-cancel-' + row.id).onClick(() => { this.confirmCancel(row) })
    }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(22).alignItems(HorizontalAlign.Start)
  }
  @Builder
  SheetContent() {
    Scroll() {
      Column({ space: 16 }) {
        Text(this.sheetKind === 'rules' ? $r('app.string.booking_rules') : this.period.str_time).fontSize(21).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
        if (this.sheetKind === 'rules') Text(this.detail.rules).fontSize(15).lineHeight(25).fontColor(ThemeColors.textPrimary).width('100%')
        else if (this.sheetKind === 'form') {
          Text(this.detail.name + '\n' + this.day).fontSize(15).lineHeight(24).fontColor(ThemeColors.textSecondary).width('100%')
          ForEach(this.detail.fields, (field: BookingField) => { Column({ space: 6 }) {
            Text(field.name + (field.verifyType === 'required' ? ' *' : '')).fontSize(14).fontColor(ThemeColors.textPrimary).width('100%')
            TextInput({ text: this.values[field.name] ?? '', placeholder: field.name }).height(44).backgroundColor($r('app.color.campus_search_surface')).fontColor(ThemeColors.textPrimary)
              .onChange((value: string) => { const values: Record<string, string> = {}; for (const key of Object.keys(this.values)) values[key] = this.values[key]; values[field.name] = value; this.values = values })
          }.width('100%') }, (field: BookingField): string => field.name)
          Row() { Text($r('app.string.booking_number')).layoutWeight(1).fontColor(ThemeColors.textSecondary)
            Select([{ value: '1' }, { value: '2' }, { value: '3' }, { value: '4' }]).value(String(this.number)).selected(this.number - 1).onSelect((index: number) => { this.number = index + 1 }) }.width('100%')
          if (this.detail.captcha) { Text($r('app.string.booking_captcha_web')).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).width('100%'); Button($r('app.string.booking_web')).onClick(() => { this.openWeb() }) }
          else Button() { CampusActionLabel({ label: $r('app.string.booking_submit'), symbol: getSymbolIcon('check'), color: Color.White }) }
            .id('booking-submit').width('100%').height(44).backgroundColor(ThemeColors.primary).enabled(!this.sheetBusy).opacity(this.sheetBusy ? 0.6 : 1).onClick(() => { this.submit() })
        } else {
          ForEach(this.occupants, (row: BookingOccupant) => { Column({ space: 6 }) { Text(row.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%'); Text([row.department_name ?? '', row.number ?? '', row.mobile ?? ''].filter((value: string) => !!value).join(' · ')).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).width('100%') }.width('100%'); Divider().color(ThemeColors.divider) }, (row: BookingOccupant): string => String(row.id))
          if (this.occupantsMore) Button($r('app.string.books_load_more')).enabled(!this.sheetBusy).onClick(() => { this.info(this.period, true) })
          if (!this.sheetBusy && !this.sheetError && this.occupants.length === 0) Text($r('app.string.ui_no_data')).fontColor(ThemeColors.textSecondary)
        }
        if (this.sheetError) ErrorNotice({ message: this.sheetError, controlId: 'booking-sheet-diagnostics' })
      }.width('100%').padding({ left: 20, right: 20, top: 48, bottom: 24 }).alignItems(HorizontalAlign.Start)
    }.width('100%').constraintSize({ maxHeight: 600 }).align(Alignment.Top)
  }
  @Builder
  WebContent() { Web({ src: this.webUrl, controller: this.browser }).width('100%').height('100%').onPageEnd(() => {}) }
  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.source instanceof SportsBookingRepository) BookingBrowserSession()
      Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        List({ scroller: this.scroller, space: 12 }) {
          ListItem() { Column({ space: 12 }) {
            if (this.view === 'list') this.Filters()
            if (this.error) { ErrorNotice({ message: this.error, controlId: 'booking-diagnostics' }); if (this.verification) FloatingActionButton({ label: $r('app.string.campus_verify_continue'), actionEnabled: !this.loading, onAction: () => { this.verify() } }).width(160) }
          }.width('100%').padding({ top: px2vp(this.topPx) + 76 }) }
          if (this.view === 'list') {
            LazyForEach(this.venueList, (row: BookingVenue) => { ListItem() { this.Venue(row) } }, (row: BookingVenue): string => JSON.stringify(row))
            if (!this.loading && !this.error && this.visibleCount === 0) ListItem() { Text($r('app.string.booking_no_venues')).width('100%').padding(24).fontColor(ThemeColors.textSecondary) }
          } else if (this.view === 'detail') ListItem() { Column({ space: 12 }) { this.VenueDetail() }.width('100%') }
          else {
            ForEach(this.appointments, (row: BookingAppointment) => { ListItem() { this.Appointment(row) } }, (row: BookingAppointment): string => String(row.id))
            if (!this.loading && !this.error && this.appointments.length === 0) ListItem() { Text($r('app.string.booking_no_appointments')).fontColor(ThemeColors.textSecondary).width('100%').padding(24) }
            if (this.more) ListItem() { Button($r('app.string.books_load_more')).enabled(!this.paging).onClick(() => { this.nextAppointments() }) }
          }
        }.width('100%').height('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
          // A viewport bottom padding clips every scrolling row behind a fixed
          // blank strip. Reserve the safe gap only at the end of the content.
          .contentEndOffset(Math.max(20, px2vp(this.bottomPx)) + 24)
          .opacity(this.contentOpacity).enabled(!this.switching && !this.verifying)
          .cachedCount(3).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).onReachEnd(() => { this.nextAppointments() }).onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) })
      }.width('100%').height('100%').onRefreshing(() => { this.load(true) }).onOffsetChange((offset: number) => { this.pullOffset = offset })
      CenterLoadingProgress({ busy: (this.loading || this.verifying) && !this.refreshing })
      TopFade({ extent: px2vp(this.topPx) + 62 })
      FeedRefreshProgress({ topInset: px2vp(this.topPx) + 82, pullOffset: this.pullOffset, refreshing: this.refreshing })
      Row({ space: 12 }) {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 44, onAction: () => { this.back() } }).width(44)
        Text(this.view === 'detail' ? this.detail.name : this.view === 'appointments' ? $r('app.string.booking_my_reservations') : $r('app.string.feature_sports')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).maxLines(2).layoutWeight(1).textAlign(TextAlign.Center)
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44, controlId: 'booking-refresh', actionEnabled: !this.loading && !this.verifying && !this.switching, onAction: () => { this.verification ? this.verify() : this.load(true) } }).width(44)
      }.height(56).width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter }).margin({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
      Row().width(0).height(0).bindSheet($$this.webSheet, this.WebContent(), this.webSheetTransition.options(this.webSheet, { height: '90%', showClose: true, onDisappear: () => { this.load(true) } }))
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgEnd).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.sheet, this.SheetContent(), this.sheetTransition.options(this.sheet, { height: SheetSize.FIT_CONTENT, showClose: true, dragBar: false, keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY }))
  }
}
