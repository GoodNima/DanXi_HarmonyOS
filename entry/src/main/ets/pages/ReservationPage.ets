import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { router } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { AppLanguage } from '../common/AppLanguage'
import { AppState } from '../common/AppState'
import { CampusCookies } from '../common/CampusCookies'
import { CampusPreference } from '../common/CampusPreference'
import { Constant } from '../common/Constant'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { getSymbolIcon } from '../common/DanXiIcons'
import { FduAuthPolicy } from '../model/FduAuth'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { TeachingCalendar } from '../model/TeachingCalendar'
import { Playground, ReservationSlot, ReservationParser } from '../model/Reservation'
import { ReservationBrowser, ReservationBrowserDocument } from '../model/ReservationBrowser'
import { ReservationIcons } from '../common/ReservationIcons'
import { DefaultReservationSource, ReservationSource, CallbackReservationDocumentReader } from '../repository/ReservationRepository'
import { HttpError } from '../util/HttpUtil'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { TopFade } from '../components/TopFade'
import { ErrorNotice } from '../components/ErrorNotice'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { settleScrollTouch } from '../common/ScrollTouch'

@Entry
@Component
export struct ReservationPage {
  private browserSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private bookingTransition: SheetTransitionGuard = new SheetTransitionGuard()
  source: ReservationSource = new DefaultReservationSource()
  private scroller: Scroller = new Scroller()
  private controller: webview.WebviewController = new webview.WebviewController()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') personJson: string = ''
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @State private places: Playground[] = []
  @State private selected: Playground | undefined = undefined
  @State private times: ReservationSlot[] = []
  @State private campus: string = ''
  @State private category: string = ''
  @State private date: string = TeachingCalendar.iso(new Date())
  @State private availableOnly: boolean = false
  @State private loading: boolean = false
  @State private refreshing: boolean = false
  @State private pullOffset: number = 0
  @State private error: string = ''
  @State private verification: boolean = false
  @State private verifying: boolean = false
  @State private booking: boolean = false
  @State private bookingUrl: string = ''
  @State private webError: string = ''
  @State private webLoading: boolean = false
  @State private headerHeight: number = 0
  @State private browserSheet: boolean = false
  @State private browserUrl: string = ''
  @State private browserBusy: boolean = false
  @State private browserError: string = ''
  private browserController: webview.WebviewController = new webview.WebviewController()
  private browserAttached: boolean = false
  private browserTimer: number = -1
  private browserReadRevision: number = 0
  private browserResolve: ((html: string) => void) | null = null
  private browserReject: ((error: Error) => void) | null = null
  private active: boolean = false
  private revision: number = 0
  private boundOwner: string = ''
  private flight: Promise<void> | null = null
  private flightKey: string = ''
  private resumeVerified: boolean = false

  aboutToAppear(): void {
    this.active = true
    if (this.source instanceof DefaultReservationSource) {
      this.source.setDocumentReader(new CallbackReservationDocumentReader((url: string): Promise<string> => this.readBrowser(url)))
    }
    this.load(false)
  }
  onPageShow(): void {
    this.active = true
    if (this.resumeVerified && !this.verifying) { this.resumeVerified = false; this.load(true) }
    else if (this.boundOwner && this.boundOwner !== this.source.owner()) this.accountChanged()
  }
  onPageHide(): void { this.active = false; this.refreshing = false }
  aboutToDisappear(): void { this.active = false; this.revision++; this.cancelBrowser('ReservationPageDisposed') }
  accountChanged(): void {
    if (!this.active || this.boundOwner === this.source.owner()) return
    this.cancelBrowser('ReservationAccountChanged')
    this.revision++; this.places = []; this.selected = undefined; this.times = []; this.booking = false
    this.campus = ''; this.category = ''; this.load(false)
  }
  onBackPress(): boolean {
    if (this.browserSheet) { this.cancelBrowser('ReservationBrowserCancelled'); return true }
    if (this.booking) { this.booking = false; return true }
    if (this.selected !== undefined) { this.back(); return true }
    return false
  }
  private back(): void {
    if (this.selected === undefined) { router.back(); return }
    this.revision++
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.selected = undefined; this.times = []; this.error = ''; this.loading = false; this.verification = false
    })
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 })
  }
  private load(force: boolean): Promise<void> {
    if (!this.active || this.verifying) return Promise.resolve()
    const key: string = this.source.owner() + '/' + (this.selected?.id ?? 'catalog') + '/' + this.date
    if (this.flight !== null && key === this.flightKey) return this.flight
    this.flightKey = key
    const task: Promise<void> = this.read(force)
    this.flight = task
    task.finally(() => { if (this.flight === task) this.flight = null })
    return task
  }
  private async read(force: boolean): Promise<void> {
    const revision: number = ++this.revision
    const owner: string = this.source.owner()
    const place: Playground | undefined = this.selected
    const date: string = this.date
    this.boundOwner = owner; this.loading = true; this.error = ''; this.verification = false
    try {
      if (place !== undefined) {
        const times: ReservationSlot[] = await this.source.slots(place, date, force)
        if (this.active && revision === this.revision && owner === this.source.owner()) {
          this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.times = times })
        }
      } else {
        const places: Playground[] = await this.source.playgrounds(force)
        if (this.active && revision === this.revision && owner === this.source.owner()) {
          this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.places = places })
          const preferred: string = CampusPreference.current()
          if (!this.campus && places.some((row: Playground) => row.campus.includes(preferred))) {
            this.campus = places.find((row: Playground) => row.campus.includes(preferred))?.campus ?? ''
          }
        }
      }
    } catch (e) {
      if (this.active && revision === this.revision && owner === this.source.owner()) {
        this.error = ErrorDiagnostics.message(e as Object)
        this.verification = e instanceof HttpError && e.statusCode === -2
      }
    } finally {
      if (revision === this.revision) { this.loading = false; this.refreshing = false; this.browserSheet = false }
    }
  }
  private async verify(): Promise<void> {
    if (!this.active || this.verifying || this.loading) return
    this.verifying = true
    const owner: string = this.source.owner()
    try {
      if (this.needsLogin()) { await router.pushUrl({ url: 'pages/LoginPage' }); return }
      await this.source.verify()
      if (owner !== this.source.owner()) return
      this.verifying = false
      if (this.active) await this.load(true)
      else this.resumeVerified = true
    } catch (e) { if (this.active) this.error = ErrorDiagnostics.message(e as Object) }
    finally { this.verifying = false }
  }
  private needsLogin(): boolean { return this.source instanceof DefaultReservationSource && !AppState.isLoggedIn() }
  private open(place: Playground): void {
    this.revision++
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.selected = place; this.times = []; this.error = ''; this.date = TeachingCalendar.iso(new Date())
    })
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); this.load(false)
  }
  private chooseDate(): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.date + 'T00:00:00'),
      onDateAccept: (value: Date): void => {
        const date: string = TeachingCalendar.iso(value)
        if (date === this.date) return
        this.date = date; this.times = []; this.load(false)
      } })
  }
  private campuses(): string[] { return Array.from(new Set<string>(this.places.map((row: Playground) => row.campus))).sort().reverse() }
  private categories(): string[] { return Array.from(new Set<string>(this.places.filter((row: Playground) => !this.campus || row.campus === this.campus)
    .map((row: Playground) => row.category))).sort().reverse() }
  private filteredPlaces(): Playground[] { return this.places.filter((row: Playground) => (!this.campus || row.campus === this.campus) &&
    (!this.category || row.category === this.category)) }
  private filteredTimes(): ReservationSlot[] { return this.times.filter((row: ReservationSlot) => !this.availableOnly || ReservationParser.available(row)) }
  private headerExtent(): number { return this.headerHeight || this.getUIContext().px2vp(this.topPx) + 60 }
  private reserve(slot: ReservationSlot): void {
    if (this.loading || this.booking || this.browserSheet) return
    const url: string = ReservationParser.bookingUrl(slot)
    if (!url) return
    this.bookingTransition.open(() => {
      if (!this.active || this.loading || this.booking || this.browserSheet) return
      this.bookingUrl = url; this.webError = ''; this.webLoading = true; this.booking = true
    }, () => this.getUIContext())
  }
  private bookingClosed(): void {
    this.bookingUrl = ''; this.webError = ''; this.webLoading = false
    // A submitted booking changes capacity; refresh this one day only.
    if (this.active && this.selected !== undefined) this.load(true)
  }

  private readBrowser(url: string): Promise<string> {
    if (!this.active || !ReservationBrowser.allowed(url)) return Promise.reject(new Error('ReservationBrowserTargetInvalid'))
    if (this.browserResolve !== null) return Promise.reject(new Error('ReservationBrowserReadAlreadyActive'))
    this.browserUrl = url; this.browserBusy = true; this.browserError = ''; this.browserSheet = true
    const task: Promise<string> = new Promise<string>((resolve, reject) => { this.browserResolve = resolve; this.browserReject = reject })
    this.browserReadRevision++
    this.browserTimer = setTimeout(() => {
      this.browserTimer = -1
      this.browserBusy = false
      this.browserError = AppLanguage.text($r('app.string.reservation_browser_incomplete')) + ' (ReservationBrowserReadPending; HTTP 412)'
    }, 30000)
    if (this.browserAttached) {
      try { this.browserController.loadUrl(url) } catch (e) { this.cancelBrowser('ReservationBrowserLoadFailed') }
    }
    return task
  }
  private async collectBrowser(): Promise<void> {
    if (!this.active || !this.browserAttached || this.browserResolve === null) return
    const revision: number = this.browserReadRevision
    const requested: string = this.browserUrl
    try {
      const raw: string = await this.browserController.runJavaScript(ReservationBrowser.SCRIPT)
      let result: Object = JSON.parse(raw) as Object
      if (typeof result === 'string') result = JSON.parse(result) as Object
      const document: ReservationBrowserDocument = result as ReservationBrowserDocument
      if (revision !== this.browserReadRevision || !this.active || !ReservationBrowser.ready(requested, document)) return
      await CampusCookies.persist()
      if (revision !== this.browserReadRevision || !this.active) return
      const resolve: ((html: string) => void) | null = this.browserResolve
      this.releaseBrowserRead()
      if (resolve !== null) resolve(document.html)
    } catch (e) {
      if (revision === this.browserReadRevision) this.browserError = ErrorDiagnostics.message(e as Object)
    } finally { if (revision === this.browserReadRevision) this.browserBusy = false }
  }
  private releaseBrowserRead(): void {
    if (this.browserTimer >= 0) clearTimeout(this.browserTimer)
    this.browserTimer = -1; this.browserReadRevision++
    this.browserResolve = null; this.browserReject = null; this.browserBusy = false
  }
  private cancelBrowser(reason: string): void {
    const reject: ((error: Error) => void) | null = this.browserReject
    this.releaseBrowserRead(); this.browserSheet = false
    if (reject !== null) reject(new HttpError(412, 0, AppLanguage.text($r('app.string.reservation_browser_incomplete')) + ' (' + reason + ')', '') as Error)
  }

  @Builder
  CampusChoices() {
    Menu() {
      MenuItem({ content: $r('app.string.reservation_all_campuses') }).selected(!this.campus)
        .onClick(() => { this.campus = ''; this.category = '' })
      ForEach(this.campuses(), (campus: string) => {
        MenuItem({ content: campus }).selected(campus === this.campus)
          .onClick(() => { this.campus = campus; this.category = '' })
      })
    }
  }
  @Builder
  CategoryChoices() {
    Menu() {
      MenuItem({ content: $r('app.string.reservation_all_categories') }).selected(!this.category)
        .onClick(() => { this.category = '' })
      ForEach(this.categories(), (category: string) => {
        MenuItem({ content: category }).selected(category === this.category).onClick(() => { this.category = category })
      })
    }
  }
  @Builder
  Filters() {
    Row({ space: 12 }) {
      Row({ space: 6 }) {
        SymbolGlyph(getSymbolIcon('location')).fontSize(18).fontColor([ThemeColors.primary])
        Text(this.campus || $r('app.string.reservation_all_campuses')).fontSize(14).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        SymbolGlyph(getSymbolIcon('expand')).fontSize(16).fontColor([ThemeColors.textSecondary])
      }.layoutWeight(1).padding(14).borderRadius(16).backgroundColor(ThemeColors.cardBg).bindMenu(this.CampusChoices)
        .id('reservation-campus').accessibilityRole(AccessibilityRoleType.BUTTON)
      Row({ space: 6 }) {
        Text(this.category || $r('app.string.reservation_all_categories')).fontSize(14).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        SymbolGlyph(getSymbolIcon('expand')).fontSize(16).fontColor([ThemeColors.textSecondary])
      }.layoutWeight(1).padding(14).borderRadius(16).backgroundColor(ThemeColors.cardBg).bindMenu(this.CategoryChoices)
        .id('reservation-category').accessibilityRole(AccessibilityRoleType.BUTTON)
    }.width('100%')
  }
  @Builder
  DateFilters() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Image(ReservationIcons.category(this.selected?.category ?? '')).width(24).height(24).fillColor(ThemeColors.primary)
        Text((this.selected?.campus ?? '') + ' · ' + (this.selected?.category ?? '')).fontSize(14).fontColor(ThemeColors.textSecondary).layoutWeight(1)
      }.width('100%')
      Row({ space: 8 }) {
        Text($r('app.string.reservation_date')).fontSize(14).fontColor(ThemeColors.textSecondary)
        Text(this.date).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.primary).layoutWeight(1)
        SymbolGlyph(getSymbolIcon('expand')).fontSize(16).fontColor([ThemeColors.textSecondary])
      }.width('100%').padding({ top: 8, bottom: 8 }).onClick(() => { this.chooseDate() }).id('reservation-date')
      Row() {
        Text($r('app.string.reservation_available_only')).fontSize(14).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.availableOnly }).onChange((value: boolean) => { this.availableOnly = value })
          .id('reservation-available-only')
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(ThemeDimens.cardInset).borderRadius(20).backgroundColor(ThemeColors.cardBg)
  }
  @Builder
  PlaceCard(place: Playground) {
    Row({ space: 12 }) {
      Image(ReservationIcons.category(place.category)).width(28).height(28).fillColor(ThemeColors.primary)
      Column({ space: 8 }) {
        Text(place.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%')
        Text(place.campus + ' · ' + place.category).fontSize(13).fontColor(ThemeColors.textSecondary).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph(getSymbolIcon('forward')).fontSize(18).fontColor([ThemeColors.textSecondary])
    }.width('100%').padding(18).backgroundColor(ThemeColors.cardBg).borderRadius(20)
      .onClick(() => { this.open(place) }).id('reservation-place-' + place.id).accessibilityRole(AccessibilityRoleType.BUTTON)
  }
  @Builder
  SlotCard(slot: ReservationSlot) {
    Column({ space: 12 }) {
      if (slot.name) Text(slot.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%')
      Row({ space: 12 }) {
        Column({ space: 7 }) {
          Text(slot.begin + ' – ' + slot.end).fontSize(18).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Text(AppLanguage.text($r('app.string.reservation_capacity'), this.languageRevision, String(slot.reserved), String(slot.total)))
            .fontSize(13).fontColor(ThemeColors.textSecondary)
          if (ReservationParser.available(slot)) Text(AppLanguage.text($r('app.string.reservation_remaining'), this.languageRevision,
            String(Math.max(0, slot.total - slot.reserved)), String(slot.total))).fontSize(13).fontColor(ThemeColors.primary)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (ReservationParser.available(slot)) {
          FloatingActionButton({ label: $r('app.string.reservation_book'), emphasized: true, controlHeight: 40,
            controlId: 'reservation-book-' + slot.reserveId, onAction: () => { this.reserve(slot) } }).width(76)
        } else {
          Text(slot.reserved >= slot.total ? $r('app.string.reservation_full') : $r('app.string.reservation_unavailable'))
            .fontSize(14).fontColor(ThemeColors.textHint).textAlign(TextAlign.Center).width(76)
        }
      }.width('100%')
    }.width('100%').padding(18).backgroundColor(ThemeColors.cardBg).borderRadius(20)
  }
  @Builder
  BrowserContents() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text($r('app.string.reservation_browser_title')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 44,
          controlId: 'reservation-browser-close', onAction: () => { this.cancelBrowser('ReservationBrowserCancelled') } }).width(44)
      }.width('100%')
      Text($r('app.string.reservation_browser_hint')).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).width('100%')
      if (this.browserError) ErrorNotice({ message: this.browserError, controlId: 'reservation-browser-diagnostics' }).width('100%')
      Stack() {
        Web({ src: this.browserUrl || 'about:blank', controller: this.browserController }).javaScriptAccess(true).domStorageAccess(true)
          .mixedMode(MixedMode.None).onControllerAttached(() => { this.browserAttached = true })
          .onPageEnd(() => { this.collectBrowser() })
          .onLoadIntercept((event) => event.data.isMainFrame() && event.data.getRequestUrl() !== 'about:blank' && !FduAuthPolicy.isCampusUrl(event.data.getRequestUrl()))
          .onErrorReceive((event) => {
            if (event.request.isMainFrame()) { this.browserBusy = false; this.browserError = 'WebViewError (code=' +
              String(event.error.getErrorCode()) + '): ' + event.error.getErrorInfo() }
          }).onHttpErrorReceive((event) => {
            if (event.request.isMainFrame()) { this.browserBusy = false; this.browserError = 'WebViewHttpError: HTTP ' +
              String(event.response.getResponseCode()) + ' ' + event.response.getReasonMessage() }
          }).width('100%').height('100%')
          .onDisAppear(() => { this.browserAttached = false })
        CenterLoadingProgress({ busy: this.browserBusy })
      }.width('100%').layoutWeight(1)
      Button($r('app.string.reservation_browser_continue')).onClick(() => { this.collectBrowser() }).width('100%').height(42)
        .id('reservation-browser-continue').backgroundColor(ThemeColors.primary).fontColor(Color.White)
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 12, bottom: 20 }).backgroundColor(ThemeColors.bgStart)
  }
  @Builder
  BookingContents() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text($r('app.string.reservation_booking_form')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlId: 'reservation-booking-back',
          onAction: () => { this.booking = false } }).width(40)
      }.width('100%').padding({ left: 16, right: 16 })
      if (this.webError) { ErrorNotice({ message: this.webError, controlId: 'reservation-web-diagnostics' }).padding({ left: 16, right: 16 }) }
      Stack() {
        Web({ src: this.bookingUrl || 'about:blank', controller: this.controller }).javaScriptAccess(true).domStorageAccess(true)
          .zoomAccess(true).mixedMode(MixedMode.None)
          .onLoadIntercept((event) => event.data.isMainFrame() && event.data.getRequestUrl() !== 'about:blank' &&
            !FduAuthPolicy.isCampusUrl(event.data.getRequestUrl()))
          .onPageEnd(() => { this.webLoading = false; CampusCookies.persist() })
          .onErrorReceive((event) => {
            if (event.request.isMainFrame()) { this.webLoading = false; this.webError = 'WebViewError (code=' +
              String(event.error.getErrorCode()) + '): ' + event.error.getErrorInfo() }
          })
          .onHttpErrorReceive((event) => {
            if (event.request.isMainFrame()) { this.webLoading = false; this.webError = 'WebViewHttpError: HTTP ' +
              String(event.response.getResponseCode()) + ' ' + event.response.getReasonMessage() }
          }).width('100%').height('100%')
        CenterLoadingProgress({ busy: this.webLoading })
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').padding({ top: 12, bottom: this.getUIContext().px2vp(this.bottomPx) })
      .backgroundColor(ThemeColors.bgStart)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        List({ space: 12, scroller: this.scroller }) {
          ListItem() { Row().height(this.headerExtent() + 12) }
          ListItem() { if (this.selected === undefined) { this.Filters() } else { this.DateFilters() } }
          if (this.error) {
            ListItem() {
              Column({ space: 14 }) {
                ErrorNotice({ message: this.error, controlId: 'reservation-diagnostics' }).width('100%')
                FloatingActionButton({ label: this.verification ? (this.needsLogin() ? $r('app.string.ui_log_in_to_campus_account') :
                    $r('app.string.campus_verify_continue')) : $r('app.string.ui_reload'),
                  icon: this.verification ? '' : 'refresh', controlHeight: 44, actionEnabled: !this.loading && !this.verifying,
                  controlId: 'reservation-reload', onAction: () => { if (this.verification) this.verify(); else this.load(true) } })
                  .width(this.verification ? 168 : 44)
              }.padding(18).width('100%').backgroundColor(ThemeColors.cardBg).borderRadius(20)
            }
          }
          if (this.selected === undefined) {
            if (this.places.length > 0) ListItem() { Text($r('app.string.reservation_places_title')).fontSize(14).fontColor(ThemeColors.textSecondary).width('100%').padding({ left: 4, top: 6 }) }
            ForEach(this.filteredPlaces(), (place: Playground) => { ListItem() { this.PlaceCard(place) } }, (place: Playground) => place.id)
          } else {
            ForEach(this.filteredTimes(), (slot: ReservationSlot) => { ListItem() { this.SlotCard(slot) } }, (slot: ReservationSlot) => slot.id)
          }
          if (!this.loading && !this.error && (this.selected === undefined ? this.filteredPlaces().length === 0 : this.filteredTimes().length === 0)) {
            ListItem() { Text(this.selected === undefined ? $r('app.string.reservation_no_places') : $r('app.string.reservation_no_slots'))
              .fontSize(14).lineHeight(22).fontColor(ThemeColors.textSecondary).padding(18).width('100%') }
          }
          ListItem() { Text($r('app.string.reservation_booking_hint')).fontSize(12).lineHeight(18)
            .fontColor(ThemeColors.textSecondary).width('100%').padding({ top: 8, bottom: 24 }) }
          ListItem() { Row().height(this.getUIContext().px2vp(this.bottomPx) + 20) }
        }.width('100%').height('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
          .onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) })
      }.width('100%').height('100%').onOffsetChange((value: number) => { this.pullOffset = value })
        .onRefreshing(() => { this.load(true) })
      FeedRefreshProgress({ pullOffset: this.pullOffset, refreshing: this.refreshing, topInset: this.headerExtent() })
      CenterLoadingProgress({ busy: this.loading && !this.refreshing })
      TopFade({ extent: this.headerExtent(), trailingEdge: 24 })
      Row({ space: 14 }) {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 44, onAction: () => { this.back() } }).width(44)
        Text(this.selected?.name ?? $r('app.string.feature_sports')).fontSize(this.selected === undefined ? 24 : 20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .layoutWeight(1).maxLines(2).textAlign(TextAlign.Center)
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44, controlId: 'reservation-refresh',
          actionEnabled: !this.loading && !this.verifying, onAction: () => { if (this.verification) this.verify(); else this.load(true) } }).width(44)
      }.width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter,
        top: this.getUIContext().px2vp(this.topPx) + 8, bottom: 12 })
        .onAreaChange((_old: Area, next: Area) => { const height: number = Number(next.height); if (Math.abs(height - this.headerHeight) > 0.5) this.headerHeight = height })
      // A node supports one sheet binding. Keep the read-only website sheet
      // separate from the booking form so an inactive form cannot dismiss it.
      Row().width(0).height(0).id('reservation-browser-anchor')
        .bindSheet($$this.browserSheet, this.BrowserContents(), this.browserSheetTransition.options(this.browserSheet, { height: '90%', showClose: false,
          backgroundColor: ThemeColors.bgStart, onDisappear: () => { this.cancelBrowser('ReservationBrowserDismissed') } }))
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgStart)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.booking, this.BookingContents(), this.bookingTransition.options(this.booking, { height: '90%', showClose: false,
        backgroundColor: ThemeColors.bgStart, onDisappear: () => { this.bookingClosed() } }))
  }
}
