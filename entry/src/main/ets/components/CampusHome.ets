import { ReadableText } from '../common/ReadableText'
import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice, DiagnosticLink } from './ErrorNotice'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { settleScrollTouch } from '../common/ScrollTouch'
import { CampusEditFrame } from '../common/CampusEditFrame'
import { HapticFeedback } from '../common/HapticFeedback'
import { router, promptAction } from '@kit.ArkUI'
import { AppState } from '../common/AppState'
import { AppLanguage } from '../common/AppLanguage'
import { CampusPreference } from '../common/CampusPreference'
import { CampusLayout, CampusModule, CampusCardPlacement, CampusGridPlan } from '../common/CampusLayout'
import { CampusPreview, CampusPreviewStore, CampusPreviewSource, DefaultCampusPreviewSource, CampusDetailParams } from '../common/CampusPreview'
import { CampusDestination } from '../common/CampusDestination'
import { CampusLiveServices, CampusLiveSource, DefaultCampusLiveSource } from '../common/CampusLiveServices'
import { CampusLiveServicesPage } from '../pages/CampusLiveServicesPage'
import { CampusUtilityPage } from '../pages/CampusUtilityPage'
import { CampusUtilityPageSource, DefaultCampusUtilityPageSource } from '../common/CampusUtilitySource'
import { ForumRepository } from '../repository/ForumRepository'
import { Constant } from '../common/Constant'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { FloatingActionButton } from './FloatingActionButton'
import { TopFade } from './TopFade'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
import { getSymbolIcon, getSaveIcon } from '../common/DanXiIcons'
import { AnnouncementConfig } from '../common/AnnouncementConfig'
import { AccountIdentity } from '../common/AccountIdentity'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { CampusCategory } from '../common/CampusCategory'
import { CampusAccessCaption, CampusAccessLine } from '../common/CampusAccessCaption'
import { CampusPreviewItem } from '../model/CampusPreviewItem'
import { CampusGreeting } from '../common/CampusGreeting'
import { CampusCardMotion, CampusDropPosition, CampusDragPosition } from '../model/CampusCardMotion'
import { CampusMovingCard, CampusDragCard } from './CampusMovingCard'
import { CampusDropIndicator } from './CampusDropIndicator'
import { LibraryBooksRepository } from '../repository/LibraryBooksRepository'

export interface CampusHomeLayout { read(): CampusModule[]; save(rows: CampusModule[]): Promise<void> }
export class DefaultCampusHomeLayout implements CampusHomeLayout {
  read(): CampusModule[] { return AppState.getDashboardLayout() }
  save(rows: CampusModule[]): Promise<void> { return AppState.setDashboardLayout(rows) }
}

interface CampusPreviewFlight { promise: Promise<void>; forced: boolean; epoch: number }
interface CampusCardBounds { id: string; x: number; y: number; width: number; height: number }

@Component
export struct CampusHome {
  private showElectricityTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private showAccessTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private showAddTransition: SheetTransitionGuard = new SheetTransitionGuard()
  @StorageLink(AppLanguage.KEY_REVISION) @Watch('languageChanged') languageRevision: number = 0
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') personJson: string = ''
  @StorageLink(AppState.KEY_IS_LOGGED_IN) @Watch('accountChanged') loggedIn: boolean = false
  @StorageLink(ForumRepository.KEY_SESSION_REVISION) @Watch('accountChanged') forumRevision: number = 0
  @StorageLink(AppState.KEY_DASHBOARD_ORDER) @Watch('layoutChanged') layoutJson: string = ''
  @StorageLink(CampusPreference.REVISION_KEY) @Watch('accountChanged') campusRevision: number = 0
  @StorageLink(CampusPreference.KEY) currentCampus: string = '邯郸'
  @StorageLink(CampusPreviewStore.REVISION) @Watch('previewChanged') previewRevision: number = 0
  @StorageLink(CampusLiveServices.REVISION) @Watch('liveChanged') liveRevision: number = 0
  @StorageLink(LibraryBooksRepository.PIN_REVISION) @Watch('booksChanged') booksRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(AnnouncementConfig.KEY_REVISION) @Watch('configurationChanged') configRevision: number = 0
  @StorageLink(AccountIdentity.KEY_REVISION) identityRevision: number = 0
  @StorageLink('main_active_tab') @Watch('resume') activeTab: number = 0
  @StorageLink('campus_feature_request') @Watch('desktopRequested') desktopRequest: string = ''
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @State rows: CampusModule[] = []
  @State previews: CampusPreview[] = []
  @State loadingIds: string[] = []
  @State @Watch('editingChanged') editing: boolean = false
  @State saving: boolean = false
  @State showAdd: boolean = false
  @State showElectricity: boolean = false
  @State showAccess: boolean = false
  @State refreshing: boolean = false
  @State clock: number = Date.now()
  @State greetingWords: string = ''
  @State greetingOpacity: number = 1
  @State draggingId: string = ''
  private dropTarget: string = ''
  private dropRow: number = -1
  private dropColumn: number = -1
  private dropPosition: CampusDropPosition = new CampusDropPosition()
  private heldPosition: CampusDragPosition = new CampusDragPosition()
  private dragX: number = 0
  private dragY: number = 0
  private cardMotions: Map<string, CampusCardMotion> = new Map<string, CampusCardMotion>()
  @State headerExtent: number = 136
  private headerTimer: number = -1
  private greetingTimer: number = -1
  private greetingVersion: number = 0
  private greetingRotation: number = 0
  private greetingPeriod: string = ''
  private homeWasVisible: boolean = false
  source: CampusPreviewSource = new DefaultCampusPreviewSource()
  electricitySource: CampusLiveSource = new DefaultCampusLiveSource()
  accessSource: CampusUtilityPageSource = new DefaultCampusUtilityPageSource()
  layoutSource: CampusHomeLayout = new DefaultCampusHomeLayout()
  private active: boolean = false
  private epoch: number = 0
  private refreshVersion: number = 0
  private requests: Map<string, number> = new Map<string, number>()
  private flights: Map<string, CampusPreviewFlight> = new Map<string, CampusPreviewFlight>()
  private timer: number = -1
  private publishing: boolean = false
  private boundOwner: string = CampusPreviewStore.owner()
  private boundForum: number = 0
  private restoreFlight: Promise<void> | null = null
  private greetingDay: string = ''
  private scroller: Scroller = new Scroller()
  // Untouched native Scroll drives inertia while the other finger holds a card.
  // The visible Scroll cannot fling during an active native touch session.
  private momentumScroller: Scroller = new Scroller()
  private momentumOffset: number = 0
  private nativeDragScrollReady: boolean = false
  private hitPointer: number = -1
  private hitY: number = 0
  private dragBounds: CampusCardBounds[] = []
  private dragPointer: number = -1
  private scrollPointer: number = -1
  private scrollPointerY: number = 0
  private scrollPointerTime: number = 0
  private scrollVelocity: number = 0
  private dragMomentum: boolean = false
  private autoScrollLast: number = 0
  private dragFramePosted: boolean = false
  private dragFrameRevision: number = 0
  private pendingScroll: number = 0
  private pendingPointer: number = -1
  private pendingId: string = ''
  private pendingX: number = 0
  private pendingY: number = 0
  private pendingTimer: number = -1
  private pendingRevision: number = 0
  private dragStartX: number = 0
  private dragStartY: number = 0
  private dragStartScroll: number = 0
  private pointerX: number = 0
  private pointerY: number = 0
  private viewportY: number = 0
  private viewportX: number = 0
  private viewportHeight: number = 0
  private autoScrollSpeed: number = 0
  private autoScrollTimer: number = -1
  private boardX: number = 0
  private boardY: number = 0
  private boardWidth: number = 0
  private previewFailures: Map<string, string> = new Map<string, string>()
  private packedRows: CampusModule[] | null = null
  private packedPlan: CampusGridPlan = new CampusGridPlan()
  private boardPacked: CampusGridPlan | null = null
  private boardEditing: boolean = false
  private boardCache: CampusGridPlan = new CampusGridPlan()

  aboutToAppear(): void {
    this.active = true; this.clock = Date.now(); this.homeWasVisible = this.activeTab === 0
    this.boundOwner = CampusPreviewStore.owner(); this.boundForum = this.forumRevision
    this.greetingDay = new Date(this.clock).toDateString()
    this.updateGreeting(false, false); this.rows = this.layoutSource.read(); this.refresh(false)
    this.getUIContext().postFrameCallback({ onFrame: () => { this.desktopRequested() }, onIdle: () => {} })
    AccountIdentity.syncName(AppState.getPerson()).catch(() => {})
    AnnouncementConfig.load().then(() => { if (this.active) this.configurationChanged() }).catch(() => {})
    this.timer = setInterval(() => {
      if (!this.active || this.activeTab !== 0) return
      this.clock = Date.now(); if (!this.editing) this.updateGreeting(false, true)
      const day: string = new Date(this.clock).toDateString()
      if (day !== this.greetingDay) {
        this.greetingDay = day
        // Today's summary is local timetable data; a clock tick must never
        // poll every protected card or start identity verification.
        if (!this.editing && this.visible().some(row => row.id === 'timetable')) this.read('timetable', false)
      }
    }, 60000)
  }
  aboutToDisappear(): void {
    AppStorage.setOrCreate<boolean>('campus_layout_editing', false)
    this.active = false; this.endDrag(); this.epoch++; this.flights.clear()
    this.cancelGreeting()
    if (this.timer >= 0) clearInterval(this.timer)
    if (this.headerTimer >= 0) clearTimeout(this.headerTimer)
    this.headerTimer = -1
  }
  layoutChanged(): void { if (!this.editing) { this.rows = this.layoutSource.read(); this.loadMissing() } }
  booksChanged(): void {
    if (this.active && !this.editing && this.visible().some((row: CampusModule) => row.id === 'library_books')) this.read('library_books', false)
  }
  languageChanged(): void {
    this.previewFailures.clear()
    this.epoch++; this.requests.clear(); this.flights.clear(); this.loadingIds = []; this.refreshing = false
    this.boundOwner = CampusPreviewStore.owner()
    this.cancelGreeting(); this.greetingRotation = 0
    if (this.active) { this.updateGreeting(false, false); this.restorePreviews() }
  }
  accountChanged(): void {
    // AppState commits the profile and its status consecutively. Ignore the
    // intermediate pair so one sign-in causes only one account-scoped refresh.
    if (AppState.getPerson().isLoggedIn() !== AppState.isLoggedIn()) return
    if (this.active) AccountIdentity.syncName(AppState.getPerson()).catch(() => {})
    const owner: string = CampusPreviewStore.owner()
    if (owner === this.boundOwner) {
      // Profile/name enrichment and independent forum state are not a new
      // campus account. Only DanKe's card belongs to the latter session.
      if (this.boundForum !== this.forumRevision) {
        this.boundForum = this.forumRevision
        this.previews = this.previews.filter(row => row.id !== 'evaluation')
        if (this.active && this.activeTab === 0 && !this.editing) this.loadMissing()
      }
      if (this.active) this.updateGreeting(false, false)
      return
    }
    this.boundOwner = owner; this.boundForum = this.forumRevision
    this.previewFailures.clear()
    this.endDrag(); this.epoch++; this.requests.clear(); this.flights.clear(); this.loadingIds = []; this.previews = []; this.refreshing = false
    this.cancelGreeting(); this.greetingRotation = 0
    if (this.active) { this.updateGreeting(false, false); if (this.activeTab === 0) this.refresh(false) }
  }
  configurationChanged(): void { if (this.active && this.activeTab === 0 && !this.editing) this.updateGreeting(false, false) }
  resume(): void {
    const visible: boolean = this.active && this.activeTab === 0
    AppStorage.setOrCreate<boolean>('campus_layout_editing', visible && this.editing)
    if (!visible) { this.endDrag(); this.cancelGreeting() }
    if (visible && !this.editing) {
      this.clock = Date.now()
      this.updateGreeting(!this.homeWasVisible, true)
    }
    this.homeWasVisible = visible
    if (visible && !this.editing) { this.restorePreviews(); this.desktopRequested() }
  }
  previewChanged(): void { if (this.active && this.activeTab === 0 && !this.editing) this.restorePreviews() }
  private liveChanged(): void {
    if (!this.active || this.activeTab !== 0 || this.editing) return
    const epoch: number = this.epoch; const owner: string = CampusPreviewStore.owner()
    this.source.cached('electricity').then((row: CampusPreview | undefined) => {
      if (!this.active || epoch !== this.epoch || owner !== CampusPreviewStore.owner() || row === undefined) return
      if (row.status === 'ready' && row.updatedAt >= this.preview(row.id).updatedAt) {
        this.previewFailures.delete(row.id); this.replace(row)
        this.source.publish(row, owner).catch(() => {})
      }
    }).catch(() => {})
  }
  private editingChanged(): void {
    AppStorage.setOrCreate<boolean>('campus_layout_editing', this.active && this.activeTab === 0 && this.editing)
  }
  private loadMissing(): void {
    if (!this.active || this.editing || this.activeTab !== 0) return
    for (const row of this.visible()) if (!this.previews.some(value => value.id === row.id)) this.read(row.id, false)
  }
  private restorePreviews(): Promise<void> {
    if (this.restoreFlight !== null) return this.restoreFlight
    const task: Promise<void> = this.restoreRows()
    this.restoreFlight = task
    task.finally(() => { if (this.restoreFlight === task) this.restoreFlight = null })
    return task
  }
  private async restoreRows(): Promise<void> {
    const epoch: number = this.epoch; const owner: string = CampusPreviewStore.owner()
    const rows = await Promise.all(this.visible().map(row => this.source.cached(row.id).catch(() => undefined)))
    if (!this.active || epoch !== this.epoch || owner !== CampusPreviewStore.owner()) return
    for (const row of rows) {
      if (row === undefined) continue
      const prior = this.preview(row.id)
      if (row.status === 'ready') this.previewFailures.delete(row.id)
      if (row.updatedAt >= prior.updatedAt && (row.value !== prior.value || row.description !== prior.description ||
        row.secondary !== prior.secondary || row.status !== prior.status || row.updatedAt !== prior.updatedAt)) this.replace(row)
    }
  }
  private visible(): CampusModule[] { return this.rows.filter(row => row.enabled) }
  private packed(): CampusGridPlan {
    if (this.packedRows !== this.rows) { this.packedRows = this.rows; this.packedPlan = CampusLayout.pack(this.rows) }
    return this.packedPlan
  }
  private boardPlan(): CampusGridPlan {
    const packed = this.packed()
    if (this.boardPacked !== packed || this.boardEditing !== this.editing) {
      this.boardPacked = packed; this.boardEditing = this.editing
      this.boardCache = new CampusGridPlan()
      this.boardCache.cards = packed.cards; this.boardCache.rowCount = packed.rowCount + (this.editing ? 2 : 0)
    }
    return this.boardCache
  }
  private recordBoard(area: Area): void {
    if (this.draggingId) return
    this.boardX = Number(area.globalPosition.x); this.boardY = Number(area.globalPosition.y) + this.scrollOffset()
    this.boardWidth = Number(area.width)
  }
  private preview(id: string): CampusPreview { return this.previews.find(row => row.id === id) ?? new CampusPreview() }
  private keyValue(id: string): string {
    const unit: Resource | undefined = CampusLayout.unit(id)
    return CampusLayout.metric(this.preview(id).value, unit === undefined ? '' : AppLanguage.text(unit, this.languageRevision))
  }
  private compactCaption(id: string): string {
    if (id === 'dining' && this.preview(id).status === 'outside') {
      return AppLanguage.text($r('app.string.campus_dining_compact_hint'), this.languageRevision)
    }
    if (id === 'academic' && this.preview(id).calculation === 'local-v1') return this.academicCompactCaption()
    if (id === 'sports') return AppLanguage.text($r('app.string.campus_sports_short_hint'), this.languageRevision)
    if (id === 'empty_classroom') return this.preview(id).description.split('\n').slice(-1)[0]?.split(' · ')[0] || AppLanguage.text(CampusLayout.hint(id), this.languageRevision)
    const description: string = (this.preview(id).description || '').split('\n')[0].trim()
    return description || AppLanguage.text(CampusLayout.hint(id), this.languageRevision)
  }
  private cardKeyValue(row: CampusModule): string {
    if (row.id === 'bus' && !CampusLayout.large(row) && this.preview(row.id).status === 'ready' &&
      this.preview(row.id).items.length > 0 && !this.preview(row.id).items[0].value) {
      return AppLanguage.text($r('app.string.campus_bus_closed'), this.languageRevision)
    }
    if (row.id === 'academic' && !this.preview(row.id).gpa && this.preview(row.id).calculation === 'local-v1') {
      return AppLanguage.text($r('app.string.campus_academic_gpa_pending'), this.languageRevision)
    }
    if (row.id === 'dining' && CampusLayout.compact(row)) {
      if (this.preview(row.id).status === 'outside') return AppLanguage.text($r('app.string.campus_dining_outside_short'), this.languageRevision)
      if (this.preview(row.id).items.length > 0) return this.preview(row.id).items[0].value
    }
    return this.keyValue(row.id)
  }
  private previewUnavailable(row: CampusModule): boolean {
    const value: CampusPreview = this.preview(row.id)
    return value.status === 'pending' || (!value.value && !value.gpa)
  }
  private informationKey(row: CampusModule): string {
    const value: CampusPreview = this.preview(row.id)
    if (value.status === 'error') return 'error:' + (this.previewFailures.get(row.id) ?? '')
    if (this.previewUnavailable(row)) return JSON.stringify([
      this.loadingIds.includes(row.id), this.waitingCaption(row.id, CampusLayout.compact(row))])
    // Refresh timestamps and the footer do not change the information body.
    return JSON.stringify([value.value, value.description, value.gpa, value.credits,
      value.examCount, value.gradeCount, value.items, value.total, value.tone])
  }
  private waitingCaption(id: string, compact: boolean = false): string {
    if (compact) {
      if (id === 'empty_classroom') return AppLanguage.text($r('app.string.campus_preview_classroom_compact'), this.languageRevision)
      if (id === 'library_books') return AppLanguage.text($r('app.string.campus_preview_books_compact'), this.languageRevision)
      if (id === 'sports') return AppLanguage.text($r('app.string.campus_preview_sports_compact'), this.languageRevision)
    }
    return (this.preview(id).description || '').split('\n')[0].trim() || AppLanguage.text(CampusLayout.hint(id), this.languageRevision)
  }
  private inset(): number { return this.headerExtent + 20 }
  private updateHeader(size: SizeOptions): void {
    const height: number = Number(size.height)
    if (!Number.isFinite(height) || height <= 0) return
    if (this.headerTimer >= 0) clearTimeout(this.headerTimer)
    this.headerTimer = -1
    if (height === this.headerExtent) return
    this.headerTimer = setTimeout(() => { this.headerTimer = -1; if (this.active) this.headerExtent = height }, 0)
  }
  private greeting(): string {
    return this.greetingWords || CampusGreeting.text(new Date(this.clock), this.languageRevision + this.configRevision, this.greetingRotation)
  }
  private cancelGreeting(): void {
    if (this.greetingTimer >= 0) clearTimeout(this.greetingTimer)
    this.greetingTimer = -1; this.greetingVersion++; this.greetingOpacity = 1
  }
  private updateGreeting(advance: boolean, animate: boolean): void {
    const now: Date = new Date(this.clock)
    const period: string = CampusGreeting.period(now)
    const changedPeriod: boolean = period !== this.greetingPeriod
    if (changedPeriod) { this.greetingPeriod = period; this.greetingRotation = 0 }
    else if (advance) this.greetingRotation++
    const words: string[] = CampusGreeting.pool(now, this.languageRevision + this.configRevision)
    // A late public-config response may add choices, but never interrupts the
    // sentence already being read. Expired/no-longer-valid choices are replaced.
    if (!changedPeriod && !advance && words.includes(this.greetingWords)) return
    const next: string = words[this.greetingRotation % words.length]
    if (next === this.greetingWords) return
    this.cancelGreeting()
    if (!animate || !this.greetingWords || !this.active || this.activeTab !== 0 || this.editing) {
      this.greetingWords = next; return
    }
    const version: number = this.greetingVersion
    const epoch: number = this.epoch
    this.getUIContext().animateTo({ duration: 110, curve: Curve.EaseOut }, () => { this.greetingOpacity = 0 })
    this.greetingTimer = setTimeout(() => {
      this.greetingTimer = -1
      if (!this.active || this.activeTab !== 0 || this.editing || epoch !== this.epoch || version !== this.greetingVersion) return
      this.greetingWords = next
      this.getUIContext().animateTo({ duration: 190, curve: Curve.EaseIn }, () => { this.greetingOpacity = 1 })
    }, 110)
  }
  private welcome(): string {
    const revision: number = this.identityRevision
    const person = AppState.getPerson()
    return CampusGreeting.welcome(AccountIdentity.cachedName(person) || AccountIdentity.id(person),
      AppState.isLoggedIn(), this.languageRevision + revision)
  }

  private async refresh(force: boolean, rotate: boolean = true): Promise<void> {
    if (!this.active || this.activeTab !== 0 || this.editing) { this.refreshing = false; return }
    if (force) {
      if (rotate && !this.refreshing) { this.clock = Date.now(); this.updateGreeting(true, true) }
      this.refreshVersion++; this.refreshing = true
    }
    const version: number = this.refreshVersion
    const epoch: number = this.epoch
    try { await Promise.all(this.visible().map(row => this.read(row.id, force))) }
    finally { if (force && epoch === this.epoch && version === this.refreshVersion) this.refreshing = false }
  }
  private read(id: string, force: boolean): Promise<void> {
    const pending: CampusPreviewFlight | undefined = this.flights.get(id)
    if (pending !== undefined && pending.epoch === this.epoch) {
      if (!force || pending.forced) return pending.promise
      pending.forced = true
      const prior: Promise<void> = pending.promise
      const queued: Promise<void> = prior.then(() => {
        if (!this.active || pending.epoch !== this.epoch) return
        return this.performRead(id, true)
      })
      pending.promise = queued
      this.finishFlight(id, pending, queued)
      return queued
    }
    const task: Promise<void> = this.performRead(id, force)
    const flight: CampusPreviewFlight = { promise: task, forced: force, epoch: this.epoch }
    this.flights.set(id, flight)
    this.finishFlight(id, flight, task)
    return task
  }
  private finishFlight(id: string, flight: CampusPreviewFlight, task: Promise<void>): void {
    task.then(() => {
      if (this.flights.get(id) === flight && flight.promise === task) this.flights.delete(id)
    }).catch(() => {
      if (this.flights.get(id) === flight && flight.promise === task) this.flights.delete(id)
    })
  }
  private async performRead(id: string, force: boolean): Promise<void> {
    const epoch: number = this.epoch
    const startedAt: number = Date.now()
    const owner: string = CampusPreviewStore.owner()
    const request: number = (this.requests.get(id) ?? 0) + 1
    this.requests.set(id, request)
    this.loadingIds = this.loadingIds.concat([id])
    try {
      const cache: CampusPreview | undefined = await this.source.cached(id)
      if (cache !== undefined && this.active && epoch === this.epoch) this.replace(cache)
      const row: CampusPreview = await this.source.read(id, force)
      if (!this.active || epoch !== this.epoch || owner !== CampusPreviewStore.owner() || this.requests.get(id) !== request) return
      this.previewFailures.delete(id)
      this.replace(row)
      if (row.updatedAt > 0 && (cache === undefined || cache.updatedAt !== row.updatedAt || cache.value !== row.value ||
        cache.description !== row.description || cache.secondary !== row.secondary)) {
        this.publishing = true
        try { await this.source.publish(row, owner) } catch (e) {} finally { this.publishing = false }
      }
    } catch (e) {
      // A detail may have completed while this older passive read was failing.
      // Reuse only a success newer than this read, not an arbitrary old cache.
      const recovered: CampusPreview | undefined = id === 'electricity' ? await this.source.cached(id).catch(() => undefined) : undefined
      if (!this.active || epoch !== this.epoch || owner !== CampusPreviewStore.owner() || this.requests.get(id) !== request) return
      if (recovered !== undefined && recovered.status === 'ready' && recovered.updatedAt >= startedAt) {
        this.previewFailures.delete(id); this.replace(recovered); return
      }
      this.previewFailures.set(id, ErrorDiagnostics.message(e as Object))
      const prior: CampusPreview = this.preview(id)
      const row: CampusPreview = new CampusPreview()
      row.id = id; row.value = prior.value || AppLanguage.text($r('app.string.campus_preview_retry'), this.languageRevision)
      row.description = prior.description || AppLanguage.text($r('app.string.campus_preview_failed'), this.languageRevision)
      row.secondary = prior.secondary; row.updatedAt = prior.updatedAt; row.status = 'error'
      this.replace(row)
    } finally {
      if (epoch === this.epoch && this.requests.get(id) === request) this.loadingIds = this.loadingIds.filter(value => value !== id)
    }
  }
  private replace(row: CampusPreview): void { this.previews = this.previews.filter(item => item.id !== row.id).concat([row]) }
  private edit(): void {
    if (this.saving) return
    this.rows = this.layoutSource.read()
    this.endDrag(); this.cancelGreeting()
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => { this.editing = true })
  }
  private cancel(): void {
    if (this.saving) return
    this.endDrag()
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => {
      this.editing = false; this.rows = this.layoutSource.read(); this.showAdd = false
    })
    this.loadMissing()
  }
  private async save(): Promise<void> {
    if (this.saving) return
    this.endDrag()
    this.saving = true
    const committed: CampusModule[] = this.rows.map(row => CampusLayout.copy(row))
    try {
      await this.layoutSource.save(committed)
      if (!this.active) return
      this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => { this.rows = committed; this.editing = false; this.showAdd = false })
      this.loadMissing()
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.layout_save_failed'))) }
    finally { this.saving = false }
  }
  private restore(): void {
    if (!this.editing || this.saving) return
    this.endDrag()
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => {
      this.rows = CampusLayout.defaults(); this.showAdd = false
    })
  }
  private move(id: string, offset: number): void {
    if (this.saving) return
    const visible: CampusModule[] = this.visible()
    const position: number = visible.findIndex(row => row.id === id)
    if (position + offset < 0 || position + offset >= visible.length) return
    const from: number = this.rows.findIndex(row => row.id === id)
    const to: number = this.rows.findIndex(row => row.id === visible[position + offset].id)
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => { this.rows = CampusLayout.move(this.rows, from, to) })
  }
  private toggle(id: string): void {
    if (this.saving) return
    this.endDrag()
    if (this.visible().length === 1 && this.rows.some(row => row.id === id && row.enabled)) {
      promptAction.showToast({ message: $r('app.string.layout_keep_one') }); return
    }
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.rows = this.rows.map(row => { const copy: CampusModule = CampusLayout.copy(row); if (copy.id === id) copy.enabled = !copy.enabled; return copy })
    })
  }
  private resize(id: string): void {
    if (this.saving) return
    const selected: CampusModule | undefined = this.rows.find(row => row.id === id)
    if (selected === undefined || !CampusLayout.supportsSize(id, CampusLayout.large(selected) ? 'small' : 'large')) return
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.rows = this.rows.map(row => { const copy: CampusModule = CampusLayout.copy(row); if (copy.id === id) copy.size = CampusLayout.large(copy) ? 'small' : 'large'; return copy })
    })
  }
  private add(): void {
    this.showAddTransition.open(() => {
      if (this.active && !this.saving && this.editing) { this.endDrag(); this.showAdd = true; this.restoreCatalogPreviews() }
    }, () => this.getUIContext())
  }
  private async restoreCatalogPreviews(): Promise<void> {
    const epoch: number = this.epoch; const owner: string = CampusPreviewStore.owner()
    const rows = await Promise.all(this.rows.filter(row => !this.previews.some(value => value.id === row.id))
      .map(row => this.source.cached(row.id).catch(() => undefined)))
    if (!this.active || !this.showAdd || epoch !== this.epoch || owner !== CampusPreviewStore.owner()) return
    for (const row of rows) if (row !== undefined) this.replace(row)
  }
  private choose(id: string, size: string): void {
    if (this.saving || !this.editing) return
    this.endDrag()
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.rows = CampusLayout.choose(this.rows, id, size)
    })
  }
  private templates(size: string): CampusModule[] {
    return this.rows.filter(row => CampusLayout.supportsSize(row.id, size))
      .map((row: CampusModule): CampusModule => ({ id: row.id, enabled: row.enabled, size: size }))
  }
  private selected(row: CampusModule): boolean {
    return this.rows.some(item => item.id === row.id && item.enabled && CampusLayout.size(item) === CampusLayout.size(row))
  }
  private catalogStatus(row: CampusModule): Resource {
    return this.selected(row) ? $r('app.string.campus_catalog_selected') :
      this.rows.some(item => item.id === row.id && item.enabled) ? $r('app.string.campus_catalog_resize') :
        $r('app.string.campus_catalog_available')
  }
  private sizeLabel(row: CampusModule): Resource {
    return CampusLayout.compact(row) ? $r('app.string.campus_size_compact') :
      CampusLayout.large(row) ? $r('app.string.campus_size_large') : $r('app.string.campus_size_small')
  }
  private scrollOffset(): number {
    const offset: OffsetResult | undefined = this.scroller.currentOffset()
    return offset !== undefined && Number.isFinite(offset.yOffset) ? offset.yOffset : 0
  }
  private motion(id: string): CampusCardMotion {
    let value: CampusCardMotion | undefined = this.cardMotions.get(id)
    if (value === undefined) { value = new CampusCardMotion(); this.cardMotions.set(id, value) }
    return value
  }
  private finger(event: GestureEvent): FingerInfo | undefined {
    const fingers: FingerInfo[] = event.fingerList.filter(info => info !== undefined)
    const finger: FingerInfo | undefined = this.dragPointer >= 0 ? fingers.find(info => info.id === this.dragPointer) :
      fingers.length === 1 ? fingers[0] : undefined
    return finger !== undefined && Number.isFinite(finger.globalX) && Number.isFinite(finger.globalY) ? finger : undefined
  }
  private beginLocalDrag(id: string, event: GestureEvent): void {
    this.endDrag()
    const finger: FingerInfo | undefined = this.finger(event)
    if (finger !== undefined) this.beginDragPoint(id, finger.id, finger.globalX, finger.globalY)
  }
  private beginDragPoint(id: string, pointer: number, x: number, y: number): void {
    const nativeScroll: boolean = this.nativeDragScrollReady && !this.draggingId
    const nativePointer: number = this.scrollPointer
    this.endDrag()
    if (!this.active || !this.editing || this.saving || this.showAdd ||
      !this.rows.some(row => row.id === id && row.enabled)) return
    this.dragBounds = []
    // Card dimensions and cell positions are fixed by the packed grid. One
    // board measurement replaces per-card area callbacks on every scroll.
    if (this.boardWidth <= 0) return
    for (const placement of this.packed().cards) {
        const width: number = (this.boardWidth - CampusLayout.CARD_GAP) / 2
        this.dragBounds.push({ id: placement.module.id, x: this.boardX + placement.column * (width + CampusLayout.CARD_GAP),
          y: this.boardY + placement.row * (CampusLayout.HALF_HEIGHT + CampusLayout.CARD_GAP),
          width: placement.columnSpan === 2 ? this.boardWidth : width,
          height: placement.rowSpan === 2 ? CampusLayout.FULL_HEIGHT : CampusLayout.HALF_HEIGHT })
    }
    const held: CampusCardBounds | undefined = this.dragBounds.find(bounds => bounds.id === id)
    if (held === undefined) return
    if (nativeScroll) { this.nativeDragScrollReady = true; this.scrollPointer = nativePointer }
    HapticFeedback.selection()
    this.dragStartX = x; this.dragStartY = y; this.dragPointer = pointer
    this.appliedPointerX = NaN; this.appliedPointerY = NaN; this.appliedScroll = NaN
    this.dragStartScroll = this.scrollOffset()
    this.pointerX = x; this.pointerY = y
    this.heldPosition.width = held.width; this.heldPosition.height = held.height
    this.heldPosition.x = held.x - this.viewportX
    this.heldPosition.y = held.y - this.dragStartScroll - this.viewportY
    this.motion(id).held = true
    this.draggingId = id
  }
  private updateLocalDrag(id: string, event: GestureEvent): void {
    if (this.draggingId !== id || !this.editing || this.saving || !this.active || this.activeTab !== 0) { this.endDrag(); return }
    const finger: FingerInfo | undefined = this.finger(event)
    if (finger === undefined || finger.id !== this.dragPointer) { this.endDrag(); return }
    this.pointerX = finger.globalX; this.pointerY = finger.globalY
    this.applyDragPosition()
    this.updateAutoScroll()
  }
  private appliedPointerX: number = NaN
  private appliedPointerY: number = NaN
  private appliedScroll: number = NaN
  private applyDragPosition(): void {
    if (!this.draggingId) return
    const offset: number = this.scrollOffset()
    if (this.pointerX === this.appliedPointerX && this.pointerY === this.appliedPointerY && offset === this.appliedScroll) return
    this.appliedPointerX = this.pointerX; this.appliedPointerY = this.pointerY; this.appliedScroll = offset
    const held: CampusCardBounds | undefined = this.dragBounds.find(bounds => bounds.id === this.draggingId)
    if (held === undefined) return
    const left: number = this.boardWidth > 0 ? this.boardX : held.x
    const right: number = this.boardWidth > 0 ? this.boardX + this.boardWidth : held.x + held.width
    const top: number = this.viewportY + this.inset()
    const bottom: number = Math.max(top + held.height, this.viewportY + this.viewportHeight - Math.max(16, px2vp(this.bottomPx)) - 112)
    // Bound the held rectangle, not only its pointer. It cannot cover the
    // editor toolbar, bottom tabs or slide beyond the two-column board.
    this.dragX = Math.max(left - held.x, Math.min(right - held.x - held.width, this.pointerX - this.dragStartX))
    // Content scrolls underneath the held card; this compensation keeps the
    // card at the finger rather than letting it drift as targets are revealed.
    const desired: number = this.pointerY - this.dragStartY + offset - this.dragStartScroll
    this.dragY = this.viewportHeight > 0 ? Math.max(top - held.y + offset,
      Math.min(bottom - held.height - held.y + offset, desired)) : desired
    // Offset compensation is only needed for drop hit testing. The painted
    // card lives outside Scroll, so a stationary first finger does not repaint
    // its cached content on every second-finger scroll frame.
    const layerX: number = held.x + this.dragX - this.viewportX
    const layerY: number = held.y + this.dragY - offset - this.viewportY
    // Subpixel scroll compensation can differ through floating-point rounding.
    // A stationary finger must not dirty its layer for those tiny differences.
    this.heldPosition.move(layerX, layerY)
    const target: CampusCardBounds | undefined = this.dragBounds.find(bounds => bounds.id !== this.draggingId &&
      this.pointerX >= bounds.x && this.pointerX <= bounds.x + bounds.width &&
      this.pointerY >= bounds.y - offset && this.pointerY <= bounds.y + bounds.height - offset)
    this.setDropTarget(target?.id ?? '')
    let nextRow: number = -1; let nextColumn: number = -1
    if (target === undefined && this.boardWidth > 0 && this.pointerX >= left && this.pointerX <= right &&
      this.pointerY >= top && this.pointerY <= bottom) {
      const card = this.packed().cards.find(item => item.module.id === this.draggingId)
      const row: number = Math.floor((this.pointerY + offset - this.boardY) / (CampusLayout.HALF_HEIGHT + CampusLayout.CARD_GAP))
      const column: number = card?.columnSpan === 2 ? 0 : Math.min(1, Math.floor((this.pointerX - left) / ((this.boardWidth + CampusLayout.CARD_GAP) / 2)))
      if (card !== undefined && row >= 0 && row + card.rowSpan <= this.boardPlan().rowCount &&
        !this.packed().cards.some(item => item.module.id !== this.draggingId && row < item.row + item.rowSpan &&
          row + card.rowSpan > item.row && column < item.column + item.columnSpan && column + card.columnSpan > item.column)) {
        nextRow = row; nextColumn = column
      }
    }
    if (this.dropRow !== nextRow) this.dropRow = nextRow
    if (this.dropColumn !== nextColumn) this.dropColumn = nextColumn
    this.dropPosition.visible = nextRow >= 0
    if (nextRow >= 0) {
      this.dropPosition.width = held.width; this.dropPosition.height = held.height
      this.dropPosition.x = nextColumn * (this.boardWidth + CampusLayout.CARD_GAP) / 2
      this.dropPosition.y = nextRow * (CampusLayout.HALF_HEIGHT + CampusLayout.CARD_GAP)
    }
  }
  private setDropTarget(id: string): void {
    if (id === this.dropTarget) return
    if (this.dropTarget) this.motion(this.dropTarget).target = false
    this.dropTarget = id
    if (id) this.motion(id).target = true
  }
  /** TouchObject window coordinates are vp, matching Area/FingerInfo globals. */
  private dragTouch(event: TouchEvent): void {
    if (this.editing) event.stopPropagation()
    if (!this.draggingId) { this.editTouch(event); return }
    if (!this.active || !this.editing || this.saving || this.activeTab !== 0 || event.type === TouchType.Cancel) {
      this.endDrag(); return
    }
    // ArkUI changedTouches are resampled to display frames; touches retain
    // device-rate samples and can lag behind them during multi-touch.
    const held: TouchObject | undefined = event.changedTouches.find(touch => touch.id === this.dragPointer) ??
      (event.type === TouchType.Move ? undefined : event.touches.find(touch => touch.id === this.dragPointer))
    if (held !== undefined && Number.isFinite(held.windowX) && Number.isFinite(held.windowY)) {
      this.pointerX = held.windowX; this.pointerY = held.windowY
    }
    if (event.type === TouchType.Up && event.changedTouches.some(touch => touch.id === this.dragPointer)) {
      this.scrollDragBy(this.pendingScroll); this.pendingScroll = 0
      this.applyDragPosition(); this.commitDrag(); return
    }
    // A Scroll mounted after the first pointer is captured sees only subsequent
    // pointers. Its recognizer owns the second finger and native fling directly.
    // Do not synthesize its velocity or send a second scrollBy from this stream.
    if (this.nativeDragScrollReady) {
      if (held !== undefined) this.applyDragPosition()
      this.updateAutoScroll()
      return
    }
    if (event.type === TouchType.Up && event.changedTouches.some(touch => touch.id === this.scrollPointer)) {
      const velocity: number = this.touchTime(event) - this.scrollPointerTime < 100 ? this.scrollVelocity : 0
      this.scrollDragBy(this.pendingScroll); this.pendingScroll = 0
      this.scrollPointer = -1; this.scrollVelocity = 0
      this.autoScrollSpeed = 0
      if (Math.abs(velocity) >= 80) this.startDragMomentum(velocity)
    }
    const changedOther: TouchObject | undefined = event.changedTouches.find(touch => touch.id !== this.dragPointer &&
      !(event.type === TouchType.Up && event.changedTouches.some(changed => changed.id === touch.id))) ??
      (event.type === TouchType.Move ? undefined : event.touches.find(touch => touch.id === this.scrollPointer &&
      !(event.type === TouchType.Up && event.changedTouches.some(changed => changed.id === touch.id))) ??
      event.touches.find(touch => touch.id !== this.dragPointer &&
      !(event.type === TouchType.Up && event.changedTouches.some(changed => changed.id === touch.id))))
    const other: TouchObject | undefined = changedOther
    if (other !== undefined && Number.isFinite(other.windowY)) {
      const now: number = this.touchTime(event)
      if (this.scrollPointer !== other.id) {
        this.stopDragMomentum()
        this.scrollVelocity = 0; this.scrollPointerTime = now
      } else if (event.type === TouchType.Move && Math.abs(other.windowY - this.scrollPointerY) > 0.1) {
        this.pendingScroll += this.scrollPointerY - other.windowY
        const elapsed: number = now - this.scrollPointerTime
        if (elapsed > 0) {
          const sample: number = Math.max(-6000, Math.min(6000, (other.windowY - this.scrollPointerY) * 1000 / elapsed))
          this.scrollVelocity = elapsed > 100 ? sample : this.scrollVelocity * 0.35 + sample * 0.65
        }
        this.scrollPointerTime = now
      }
      this.scrollPointer = other.id; this.scrollPointerY = other.windowY
    } else if (!event.touches.some(touch => touch.id === this.scrollPointer)) this.scrollPointer = -1
    // changedTouches already arrives resampled to the display frame. Apply it
    // in this frame; posting it again adds latency and a second UI callback.
    if (this.pendingScroll !== 0) {
      this.scrollDragBy(this.pendingScroll); this.pendingScroll = 0
    }
    this.applyDragPosition()
    this.updateAutoScroll()
  }
  private touchTime(event: TouchEvent): number {
    return Number.isFinite(event.timestamp) && event.timestamp > 0 ? event.timestamp / 1000000 : Date.now()
  }
  /** Edit gestures share a pointer session, so a second finger cannot cancel
   * the held card through the system's one-finger scroll recognizer. */
  private editTouch(event: TouchEvent): void {
    if (!this.editing || !this.active || this.saving || this.showAdd || this.activeTab !== 0 || event.type === TouchType.Cancel) {
      this.clearPendingTouch(); return
    }
    if (event.type === TouchType.Down && this.pendingPointer < 0) {
      const touch: TouchObject | undefined = event.changedTouches[0]
      if (touch === undefined || !Number.isFinite(touch.windowX) || !Number.isFinite(touch.windowY)) return
      this.pendingPointer = touch.id; this.pendingX = touch.windowX; this.pendingY = touch.windowY
      const offset: number = this.scrollOffset()
      const width: number = (this.boardWidth - CampusLayout.CARD_GAP) / 2
      const placement = this.packed().cards.find(item => {
        const x: number = this.boardX + item.column * (width + CampusLayout.CARD_GAP)
        const y: number = this.boardY + item.row * (CampusLayout.HALF_HEIGHT + CampusLayout.CARD_GAP) - offset
        return this.boardWidth > 0 && touch.windowX >= x &&
          touch.windowX <= x + (item.columnSpan === 2 ? this.boardWidth : width) && touch.windowY >= y &&
          touch.windowY <= y + (item.rowSpan === 2 ? CampusLayout.FULL_HEIGHT : CampusLayout.HALF_HEIGHT)
      })
      this.pendingId = placement?.module.id ?? ''
      if (this.pendingId) {
        const revision: number = ++this.pendingRevision
        this.pendingTimer = setTimeout(() => {
          if (this.pendingRevision !== revision) return
          this.pendingTimer = -1
          const id: string = this.pendingId; const pointer: number = this.pendingPointer
          if (id && pointer >= 0) this.beginDragPoint(id, pointer, this.pendingX, this.pendingY)
        }, 450)
      }
      return
    }
    if (event.type === TouchType.Up && event.changedTouches.some(touch => touch.id === this.pendingPointer)) {
      this.clearPendingTouch()
      return
    }
    const touch: TouchObject | undefined = event.touches.find(touch => touch.id === this.pendingPointer)
    if (event.type !== TouchType.Move || touch === undefined) return
    if (this.pendingId && Math.hypot(touch.windowX - this.pendingX, touch.windowY - this.pendingY) > 8) {
      if (this.pendingTimer >= 0) clearTimeout(this.pendingTimer)
      this.pendingTimer = -1; this.pendingId = ''
    }
    // Ordinary swipes, velocity tracking, fling and spring edges are all owned
    // by the same native Scroll recognizer used outside layout editing.
  }
  private clearPendingTouch(): void {
    this.pendingRevision++
    if (this.pendingTimer >= 0) clearTimeout(this.pendingTimer)
    this.pendingTimer = -1; this.pendingId = ''; this.pendingPointer = -1
  }
  private scrollDragBy(delta: number): void {
    if (!Number.isFinite(delta)) return
    const before: number = this.scrollOffset()
    const max: number = this.scrollLimit()
    const next: number = Math.max(0, Math.min(max, before + delta))
    if (Math.abs(next - before) > 0.1) this.scroller.scrollBy(0, next - before)
  }
  private scrollLimit(): number {
    return Math.max(0, this.boardY - this.viewportY + this.boardPlan().height() +
      Math.max(16, px2vp(this.bottomPx)) + 112 - this.viewportHeight)
  }
  private recordViewport(area: Area): void {
    // ArkUI area notifications can include the held child's render transform.
    // Keep the measured viewport fixed for the lifetime of a pointer session.
    if (this.draggingId) return
    const x: number = Number(area.globalPosition.x)
    const y: number = Number(area.globalPosition.y)
    const height: number = Number(area.height)
    if (Number.isFinite(x) && Number.isFinite(y) && Number.isFinite(height) && height > 0) {
      this.viewportX = x; this.viewportY = y; this.viewportHeight = height
    }
  }
  private updateAutoScroll(): void {
    this.autoScrollSpeed = 0
    if (this.viewportHeight > 0 && this.scrollPointer < 0 && !this.dragMomentum) {
      const top: number = this.viewportY + this.inset() + 44
      const bottom: number = this.viewportY + this.viewportHeight - Math.max(16, px2vp(this.bottomPx)) - 112 - 44
      if (bottom > top) {
        if (this.pointerY < top) this.autoScrollSpeed = -Math.min(18, Math.max(3, (top - this.pointerY) / 4))
        else if (this.pointerY > bottom) this.autoScrollSpeed = Math.min(18, Math.max(3, (this.pointerY - bottom) / 4))
      }
    }
    if (this.autoScrollSpeed !== 0) this.requestDragFrame()
    else this.autoScrollLast = 0
  }
  private stopDragMomentum(): void {
    if (!this.dragMomentum) return
    this.dragMomentum = false
    const offset: OffsetResult | undefined = this.momentumScroller.currentOffset()
    if (offset !== undefined) this.momentumScroller.scrollTo({ xOffset: 0, yOffset: offset.yOffset, animation: false })
  }
  private startDragMomentum(velocity: number): void {
    // The compact native controller shares the board's real scroll range.
    // Seed a fallback fling at that offset so either direction can continue.
    this.dragMomentum = false
    this.momentumOffset = this.scrollOffset()
    this.momentumScroller.scrollTo({ xOffset: 0, yOffset: this.momentumOffset, animation: false })
    this.dragMomentum = true
    this.momentumScroller.fling(velocity)
  }
  private advanceDragMomentum(): void {
    if (!this.nativeDragScrollReady && !this.dragMomentum) return
    if (!this.draggingId || !this.active || !this.editing || this.saving || this.activeTab !== 0) { this.stopDragMomentum(); return }
    const offset: OffsetResult | undefined = this.momentumScroller.currentOffset()
    if (offset === undefined) return
    const delta: number = offset.yOffset - this.momentumOffset
    this.momentumOffset = offset.yOffset
    const before: number = this.scrollOffset()
    if ((before <= 0.1 && delta < 0) || (before >= this.scrollLimit() - 0.1 && delta > 0)) {
      this.stopDragMomentum(); return
    }
    this.scrollDragBy(delta)
    this.applyDragPosition()
  }
  private requestDragFrame(): void {
    if (this.dragFramePosted || !this.draggingId) return
    this.dragFramePosted = true
    const revision: number = this.dragFrameRevision
    this.getUIContext().postFrameCallback(new CampusEditFrame(() => {
      if (revision !== this.dragFrameRevision) return
      this.dragFramePosted = false
      this.stepAutoScroll()
    }))
  }
  private stepAutoScroll(): void {
    if (!this.draggingId || !this.active || !this.editing || this.saving || this.activeTab !== 0) { this.endDrag(); return }
    const now: number = Date.now()
    const elapsed: number = this.autoScrollLast > 0 ? Math.max(0, Math.min(40, now - this.autoScrollLast)) : 16
    this.autoScrollLast = now
    this.scrollDragBy(this.pendingScroll + this.autoScrollSpeed * elapsed / 16)
    this.pendingScroll = 0
    this.applyDragPosition()
    if (this.autoScrollSpeed !== 0) this.requestDragFrame()
  }
  private finishLocalDrag(id: string, event: GestureEvent): void {
    if (this.draggingId !== id) return
    // A release can have an empty fingerList; retain the last valid position.
    if (event.fingerList.some(info => info !== undefined)) this.updateLocalDrag(id, event)
    this.commitDrag()
  }
  private commitDrag(): void {
    const id: string = this.draggingId
    const from: number = this.rows.findIndex(row => row.id === this.draggingId && row.enabled)
    const to: number = this.rows.findIndex(row => row.id === this.dropTarget && row.enabled)
    const blankRow: number = this.dropRow; const blankColumn: number = this.dropColumn
    if (!this.active || !this.editing || this.saving || this.activeTab !== 0 || from < 0 || (to < 0 && blankRow < 0)) {
      this.endDrag(); return
    }
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.endDrag()
      this.rows = blankRow >= 0 ? CampusLayout.place(this.rows, id, blankRow, blankColumn) : CampusLayout.move(this.rows, from, to)
    })
  }
  private endDrag(): void {
    this.nativeDragScrollReady = false
    this.stopDragMomentum()
    this.dragFrameRevision++; this.dragFramePosted = false; this.pendingScroll = 0
    this.clearPendingTouch()
    if (this.autoScrollTimer >= 0) clearInterval(this.autoScrollTimer)
    this.autoScrollTimer = -1; this.autoScrollSpeed = 0
    this.scrollPointer = -1; this.scrollPointerY = 0; this.scrollPointerTime = 0; this.scrollVelocity = 0; this.autoScrollLast = 0
    if (this.draggingId) { this.motion(this.draggingId).reset(); this.motion(this.draggingId).held = false }
    this.draggingId = ''; this.setDropTarget(''); this.dropRow = -1; this.dropColumn = -1; this.dropPosition.visible = false
    this.dragX = 0; this.dragY = 0; this.dragPointer = -1; this.dragBounds = []
  }
  private open(id: string): void {
    if (this.editing) return
    if (id === 'campus_access') {
      this.showAccessTransition.open(() => { if (this.active) this.showAccess = true }, () => this.getUIContext())
      return
    }
    if (id === 'electricity') {
      this.showElectricityTransition.open(() => {
        if (this.active) this.showElectricity = true
      }, () => this.getUIContext())
      return
    }
    if (id === 'timetable') { AppStorage.setOrCreate<number>('main_tab_request', 1); return }
    router.pushUrl({ url: CampusDestination.page(id), params: new CampusDetailParams(id) })
      .catch((diagnosticFailure: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.ui_could_not_open_details'))) })
  }

  private desktopRequested(): void {
    if (!this.active || !this.desktopRequest || this.editing) return
    const feature = this.desktopRequest; this.desktopRequest = ''
    if (['card', 'electricity', 'bus'].includes(feature)) this.open(feature)
  }

  @Builder
  ElectricityDetails() {
    CampusLiveServicesPage({ source: this.electricitySource, initialFeature: 'electricity', sheetMode: true,
      onSheetClose: () => { this.showElectricity = false } })
  }
  @Builder
  AccessDetails() {
    CampusUtilityPage({ source: this.accessSource, initialFeature: 'campus_access', sheetMode: true,
      onSheetClose: () => { this.showAccess = false } })
  }
  private tint(id: string): ResourceColor { return this.featureColor(id) }
  private keyColor(id: string): ResourceColor {
    const row: CampusPreview = this.preview(id)
    if (row.status === 'error') return CampusContentStyle.attention
    if (row.tone) return CampusContentStyle.signalColor(row.tone, ThemeColors.textPrimary)
    return ThemeColors.textPrimary
  }
  private featureColor(id: string): ResourceColor {
    return CampusCategory.color(id)
  }

  @Builder
  NoticePreview(row: CampusModule, catalog: boolean = false) {
    if (row.id === 'announcement') {
      Column({ space: 4 }) {
        Text(ReadableText.keepWords(this.keyValue(row.id) || AppLanguage.text(catalog ? $r('app.string.campus_preview_open') : $r('app.string.campus_preview_loading'), this.languageRevision)))
          .draggable(false).fontSize(18).minFontSize(14).maxFontSize(18).maxLines(4)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.LAYOUT_CONSTRAINT_FIRST)
          .fontWeight(FontWeight.Bold).fontColor(this.keyColor(row.id))
          .lineBreakStrategy(LineBreakStrategy.GREEDY)
          .width('100%').layoutWeight(1).id('campus-announcement-headline')
        ForEach(this.preview(row.id).description.split('\n').filter(value => value.trim().length > 0)
          .slice(0, this.keyValue(row.id).length > 40 ? 1 : 2), (title: string) => {
          Text(ReadableText.keepWords(title)).draggable(false).fontSize(13).lineHeight(19).fontColor(ThemeColors.textSecondary)
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }, (title: string, index: number): string => String(index) + title)
      }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
    } else {
    Column({ space: 3 }) {
      Text(ReadableText.keepWords(this.keyValue(row.id) || AppLanguage.text(catalog ? $r('app.string.campus_preview_open') : $r('app.string.campus_preview_loading'), this.languageRevision)))
        .draggable(false).fontSize(18).lineHeight(24).fontWeight(FontWeight.Bold).fontColor(this.keyColor(row.id))
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      ForEach(this.preview(row.id).description.split('\n').filter(value => value.trim().length > 0).slice(0, 3), (title: string) => {
        Text(ReadableText.keepWords(title)).draggable(false).fontSize(13).lineHeight(19).fontColor(ThemeColors.textSecondary)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }, (title: string, index: number): string => String(index) + title)
    }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  DeveloperNoticePreview(row: CampusModule) {
    Column() {
      Text(ReadableText.keepWords(this.keyValue(row.id).replace(/\s+/g, ' ').trim()))
        .draggable(false).fontSize(15).lineHeight(22).fontColor(ThemeColors.textPrimary)
        .lineBreakStrategy(LineBreakStrategy.GREEDY).maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        .id('campus-developer-notice-body')
    }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start)
  }

  @Builder
  TimetablePreview(row: CampusModule) {
    if (CampusLayout.large(row) && this.preview(row.id).items.length > 0) {
      Column({ space: 3 }) {
        ForEach(this.preview(row.id).items.slice(0, 3), (item: CampusPreviewItem, index: number) => {
          Row({ space: 8 }) {
            Text($r('app.string.campus_course_periods', item.value)).width(56).fontSize(13)
              .minFontSize(11).maxFontSize(13).maxLines(1).fontColor(ThemeColors.textSecondary)
              .id('campus-course-period-' + String(index))
            Text(ReadableText.keepWords(item.label)).layoutWeight(1).fontSize(14).minFontSize(12).maxFontSize(14)
              .lineHeight(14).maxLines(2).fontWeight(FontWeight.Medium).fontColor(this.keyColor(row.id))
              .lineBreakStrategy(LineBreakStrategy.GREEDY)
              .id('campus-course-name-' + String(index))
            Text(item.detail || '—').width('27%').fontSize(12).minFontSize(10).maxFontSize(12)
              .lineHeight(14).maxLines(2).fontColor(ThemeColors.textSecondary)
              .id('campus-course-room-' + String(index))
          }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Center)
        }, (item: CampusPreviewItem, index: number) => String(index) + ':' + item.label + ':' + item.value + ':' + item.detail)
      }.width('100%').layoutWeight(1)
    } else {
      Column({ space: CampusLayout.compact(row) ? 5 : CampusLayout.large(row) ? 12 : 6 }) {
        Text(this.keyValue(row.id)).width('100%').fontSize(CampusLayout.compact(row) ? 15 : CampusLayout.large(row) ? 20 : 18)
          .minFontSize(CampusLayout.compact(row) ? 11 : 16).maxFontSize(CampusLayout.compact(row) ? 15 : CampusLayout.large(row) ? 20 : 18)
          .lineHeight(CampusLayout.compact(row) ? 16 : CampusLayout.large(row) ? 24 : 20).maxLines(2)
          .fontWeight(FontWeight.Bold).fontColor(this.keyColor(row.id)).id('campus-course-name-0')
        if (this.preview(row.id).items.length > 0) {
          Column({ space: CampusLayout.compact(row) || CampusLayout.large(row) ? 6 : 3 }) {
            if (!CampusLayout.compact(row)) {
              Text($r('app.string.campus_course_periods', this.preview(row.id).items[0].value))
                .fontSize(12).lineHeight(14).maxLines(1).fontColor(ThemeColors.textSecondary).id('campus-course-period-0')
            }
            Text(this.preview(row.id).items[0].detail || '—').width('100%')
              .fontSize(CampusLayout.compact(row) ? 10 : 12).minFontSize(CampusLayout.compact(row) ? 9 : 11)
              .maxFontSize(CampusLayout.compact(row) ? 10 : 12).lineHeight(CampusLayout.compact(row) ? 12 : CampusLayout.large(row) ? 17 : 14)
              .maxLines(CampusLayout.compact(row) ? 1 : 2).fontColor(ThemeColors.textSecondary)
              .id('campus-course-room-0')
          }.width('100%').alignItems(HorizontalAlign.Start)
            .padding({ right: CampusLayout.compact(row) ? 24 : 0 })
        }
      }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
        .padding({ bottom: !CampusLayout.compact(row) && !CampusLayout.large(row) ? 6 : 0 })
    }
  }

  private academicGpa(): string {
    const value: string = this.preview('academic').gpa
    return value && Number.isFinite(Number(value)) ? Number(value).toFixed(2) : value
  }
  private academicCaption(exams: boolean): string {
    const row: CampusPreview = this.preview('academic')
    const count: number = exams ? row.examCount : row.gradeCount
    return AppLanguage.text(exams ? $r('app.string.campus_academic_exam_count') :
      $r('app.string.campus_academic_grade_count')).replace('{count}',
      Number.isInteger(count) && count >= 0 ? String(count) : '—')
  }
  private academicCompactCaption(): string {
    const row: CampusPreview = this.preview('academic')
    return AppLanguage.text($r('app.string.campus_academic_counts_compact'), this.languageRevision)
      .replace('{exams}', Number.isInteger(row.examCount) && row.examCount >= 0 ? String(row.examCount) : '—')
      .replace('{grades}', Number.isInteger(row.gradeCount) && row.gradeCount >= 0 ? String(row.gradeCount) : '—')
  }
  @Builder
  AcademicPreview(row: CampusModule) {
    Column({ space: CampusLayout.compact(row) ? 7 : CampusLayout.large(row) ? 8 : 4 }) {
      if (!CampusLayout.large(row) && !CampusLayout.compact(row)) {
        Column({ space: 2 }) {
          Text('GPA ' + this.academicGpa()).fontSize(22).lineHeight(28).fontWeight(FontWeight.Bold)
            .fontColor(this.keyColor(row.id)).width('100%').maxLines(1).minFontSize(18).maxFontSize(22)
            .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          Text(this.preview(row.id).credits + ' ' + AppLanguage.text($r('app.string.academic_gpa_credits')))
            .fontSize(20).lineHeight(25).fontWeight(FontWeight.Bold).fontColor(this.keyColor(row.id))
            .width('100%').maxLines(1).minFontSize(16).maxFontSize(20).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        }.width('100%').alignItems(HorizontalAlign.Start)
      } else {
        Text('GPA ' + this.academicGpa() + ' · ' + this.preview(row.id).credits + ' ' +
          AppLanguage.text($r('app.string.academic_gpa_credits'))).fontSize(CampusLayout.compact(row) ? 19 : 28)
          .fontWeight(FontWeight.Bold).fontColor(this.keyColor(row.id))
          .width('100%').minFontSize(CampusLayout.compact(row) ? 12 : 15).maxFontSize(CampusLayout.compact(row) ? 19 : 28)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).maxLines(1)
          .lineHeight(CampusLayout.compact(row) ? 22 : 36)
      }
      if (CampusLayout.compact(row)) {
        Text(this.academicCompactCaption()).fontSize(11).minFontSize(9).maxFontSize(11)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).lineHeight(14).fontColor(ThemeColors.textSecondary)
          .minFontSize(9).maxFontSize(11).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          .width('100%').maxLines(1).id('campus-academic-compact-counts')
      } else if (!CampusLayout.large(row)) {
        Column({ space: 2 }) {
          Text(this.academicCaption(true)).fontSize(12).lineHeight(16).fontColor(ThemeColors.textSecondary)
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.academicCaption(false)).fontSize(12).lineHeight(16).fontColor(ThemeColors.textSecondary)
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').alignItems(HorizontalAlign.Start)
      } else {
        Text(this.preview(row.id).description).fontSize(13).lineHeight(22).fontColor(ThemeColors.textSecondary)
          .width('100%').maxLines(CampusLayout.large(row) ? 2 : 1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .justifyContent(CampusLayout.compact(row) ? FlexAlign.Start : FlexAlign.Center).layoutWeight(1)
  }
  private accessCaptionFont(row: CampusModule): number {
    return CampusLayout.compact(row) ? 11 : 13
  }
  private accessCaptionHeight(row: CampusModule): number {
    return CampusLayout.compact(row) ? 15 : 18
  }
  @Builder
  AccessCampusName(row: CampusModule, name: string, lineIndex: number, columnIndex: number) {
    Text(name).draggable(false).fontSize(this.accessCaptionFont(row))
      .minFontSize(CampusLayout.compact(row) ? 9 : 10).maxFontSize(this.accessCaptionFont(row))
      .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
      .lineHeight(this.accessCaptionHeight(row)).fontColor(ThemeColors.textSecondary)
      .constraintSize({ maxWidth: CampusLayout.compact(row) ? 30 : 26 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .id('campus-access-campus-' + CampusLayout.size(row) + '-' + lineIndex + '-' + columnIndex)
  }
  @Builder
  AccessCampusRows(row: CampusModule) {
        Column() {
          ForEach(CampusAccessCaption.smallLines(this.keyValue(row.id), CampusLayout.compact(row) ? 3 : 4), (line: CampusAccessLine, index: number) => {
            if (line.fallback) {
              Text(line.fallback).draggable(false).fontSize(this.accessCaptionFont(row))
                .lineHeight(this.accessCaptionHeight(row)).fontColor(ThemeColors.textSecondary)
                .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .id('campus-access-extra-' + CampusLayout.size(row) + '-' + index)
            } else {
              Row({ space: 8 }) {
                Text(line.permission).draggable(false).fontSize(this.accessCaptionFont(row))
                  .fontWeight(FontWeight.Medium).lineHeight(this.accessCaptionHeight(row))
                  .fontColor(CampusContentStyle.signalColor(line.permission === '是' ? 'normal' : line.permission === '否' ? 'critical' : '', ThemeColors.textSecondary))
                  .width(this.accessCaptionFont(row)).maxLines(1)
                  .id('campus-access-permission-' + CampusLayout.size(row) + '-' + index)
                this.AccessCampusName(row, line.campuses[0] ?? '', index, 0)
                this.AccessCampusName(row, line.campuses[1] ?? '', index, 1)
              }.width('100%').alignItems(VerticalAlign.Center).id('campus-access-line-' + CampusLayout.size(row) + '-' + index)
            }
          }, (line: CampusAccessLine, index: number): string => index + ':' + line.permission + ':' + line.campuses.join(';') + ':' + line.fallback)
        }.width('100%').alignItems(HorizontalAlign.Start).id('campus-access-caption-' + CampusLayout.size(row))
  }
  @Builder
  AccessStatusSymbol(row: CampusModule) {
    SymbolGlyph(this.preview(row.id).tone === 'normal' ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.xmark_circle'))
      .fontSize(CampusLayout.compact(row) ? 28 : 36).fontColor([this.keyColor(row.id)])
      .id('campus-access-status-' + CampusLayout.size(row)).accessibilityText(this.keyValue(row.id))
  }
  @Builder
  AccessSmallPreview(row: CampusModule) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        this.AccessStatusSymbol(row)
        Column() { this.AccessCampusRows(row) }.layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Center)
      if (!CampusLayout.compact(row) && this.preview(row.id).description) {
        this.AccessAccountStatus(row)
      }
    }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
  }
  @Builder
  AccessAccountStatus(row: CampusModule) {
    Text() {
      Span(AppLanguage.text($r('app.string.utility_card_status'), this.languageRevision) + ' · ')
        .fontSize(11).fontColor(ThemeColors.textSecondary)
      Span(this.preview(row.id).description).fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
    }.draggable(false).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
      .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .id('campus-access-account-status-small')
  }

  @Builder
  BusLargePreview(row: CampusModule) {
    Row({ space: 16 }) {
      ForEach(this.preview(row.id).items.slice(0, 2), (item: CampusPreviewItem, index: number) => {
        if (index > 0) { Divider().vertical(true).height(76).color(ThemeColors.divider).strokeWidth(0.5) }
        Column({ space: 3 }) {
          Text(ReadableText.keepWords(item.label)).draggable(false).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).id('campus-bus-route-' + index)
          Text(item.value || AppLanguage.text($r('app.string.campus_bus_closed'), this.languageRevision))
            .draggable(false).fontSize(item.value ? 26 : 15).lineHeight(34).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary).width('100%').maxLines(1).id('campus-bus-departure-' + index)
          Text(item.detail ? AppLanguage.text($r('app.string.campus_bus_following'), this.languageRevision, item.detail) :
            AppLanguage.text(item.value ? $r('app.string.campus_bus_last') : $r('app.string.campus_bus_timetable'), this.languageRevision))
            .draggable(false).fontSize(12).lineHeight(18).fontWeight(FontWeight.Medium)
            .fontColor(this.tint(row.id)).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .id('campus-bus-following-' + index)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }, (item: CampusPreviewItem): string => item.label)
    }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Center)
  }

  @Builder
  ClassroomPreviewItem(row: CampusModule, index: number) {
    Row({ space: 5 }) {
      Text(this.preview(row.id).items[index].label).draggable(false).fontSize(12).lineHeight(20).fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.textPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 56 }).id('campus-classroom-room-' + index)
      if (this.preview(row.id).items[index].value) {
        Text(AppLanguage.text($r('app.string.campus_room_seats'), this.languageRevision, this.preview(row.id).items[index].value))
          .draggable(false).fontSize(10).lineHeight(16).fontColor(ThemeColors.textSecondary).maxLines(1)
          .id('campus-classroom-seats-' + index)
      }
    }.width('100%').alignItems(VerticalAlign.Center)
  }
  @Builder
  ClassroomLargePreview(row: CampusModule) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(this.keyValue(row.id)).draggable(false).fontSize(26).lineHeight(34).fontWeight(FontWeight.Bold)
          .minFontSize(18).maxFontSize(26).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          .fontColor(this.keyColor(row.id)).width('100%').maxLines(1).id('campus-classroom-count')
        Text(AppLanguage.text($r('app.string.campus_classroom_current'), this.languageRevision))
          .draggable(false).fontSize(11).lineHeight(16).fontColor(ThemeColors.textSecondary).width('100%').maxLines(1)
        Text(AppLanguage.text($r('app.string.campus_classroom_scope'), this.languageRevision, this.preview(row.id).total))
          .draggable(false).fontSize(11).lineHeight(16).fontColor(ThemeColors.textSecondary).width('100%').maxLines(2)
          .id('campus-classroom-total')
      }.width('34%').alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        if (this.preview(row.id).items.length === 0) {
          Text(AppLanguage.text($r('app.string.campus_classroom_none'), this.languageRevision))
            .draggable(false).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%').maxLines(3)
        } else {
          ForEach([0, 1, 2, 3], (line: number) => {
            if (line * 2 < this.preview(row.id).items.length) {
              Row({ space: 6 }) {
                Column() { this.ClassroomPreviewItem(row, line * 2) }.layoutWeight(1)
                Column() {
                  if (line * 2 + 1 < this.preview(row.id).items.length) this.ClassroomPreviewItem(row, line * 2 + 1)
                }.layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Center)
            }
          }, (line: number): string => String(line))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Center)
  }

  @Builder
  LibraryPreviewItem(row: CampusModule, index: number) {
    Column({ space: 0 }) {
      Row({ space: 5 }) {
        Text(this.preview(row.id).items[index].label).draggable(false).fontSize(12).lineHeight(20).fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1).id('campus-library-name-' + index)
        Text(this.preview(row.id).items[index].value ? CampusLayout.metric(this.preview(row.id).items[index].value,
          AppLanguage.text($r('app.string.campus_unit_people'), this.languageRevision)) : '—')
          .draggable(false).fontSize(17).lineHeight(20).fontWeight(FontWeight.Bold)
          .fontColor(CampusContentStyle.signalColor(this.preview(row.id).items[index].tone, ThemeColors.textPrimary))
          .maxLines(1).minFontSize(14).maxFontSize(17).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          .width(62).textAlign(TextAlign.End)
          .id('campus-library-visitors-' + index)
      }.width('100%').alignItems(VerticalAlign.Center)
      if (this.preview(row.id).items[index].detail) {
        Text(AppLanguage.text($r('app.string.campus_library_hours'), this.languageRevision, this.preview(row.id).items[index].detail))
          .draggable(false).fontSize(10).lineHeight(12).fontColor(ThemeColors.textSecondary)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).id('campus-library-hours-' + index)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).id('campus-library-row-' + index)
  }
  @Builder
  LibraryLargePreview(row: CampusModule) {
    Column({ space: 0 }) {
      ForEach([0, 1, 2], (line: number) => {
        if (line * 2 < this.preview(row.id).items.length) {
        Row({ space: 12 }) {
          Column() { this.LibraryPreviewItem(row, line * 2) }.layoutWeight(1)
          Column() {
            if (line * 2 + 1 < this.preview(row.id).items.length) this.LibraryPreviewItem(row, line * 2 + 1)
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Center)
        }
      }, (line: number): string => String(line))
    }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
  }

  private cardFooter(row: CampusModule): string {
    const preview: CampusPreview = this.preview(row.id)
    if (row.id === 'developer_notice') return preview.secondary
    if (row.id === 'dining' && preview.items.length === 2) return AppLanguage.text($r('app.string.campus_dining_reference'), this.languageRevision)
    if (row.id === 'empty_classroom' && CampusLayout.large(row) && preview.status === 'ready' && preview.total >= 0) {
      return preview.description.split('\n').slice(-1)[0] || preview.secondary
    }
    if (row.id === 'library' && CampusLayout.large(row) && preview.status === 'ready' && preview.items.length > 6) {
      return AppLanguage.text($r('app.string.campus_library_more'), this.languageRevision, preview.items.length - 6)
    }
    return preview.secondary || AppLanguage.text(CampusPreference.title(this.currentCampus), this.languageRevision)
  }

  @Builder
  DiningSummaryItem(row: CampusModule, index: number) {
    Column({ space: 3 }) {
      Text(this.preview(row.id).items[index].label).fontSize(12).minFontSize(10).maxFontSize(12)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).maxLines(1).lineHeight(17).fontColor(ThemeColors.textSecondary).width('100%')
      Text(ReadableText.keepWords(this.preview(row.id).items[index].value)).draggable(false).fontSize(CampusLayout.large(row) ? 20 : 18).lineHeight(CampusLayout.large(row) ? 24 : 23)
        .fontWeight(FontWeight.Bold).fontColor(CampusContentStyle.signalColor(this.preview(row.id).items[index].tone, ThemeColors.textPrimary))
        .minFontSize(14).maxFontSize(CampusLayout.large(row) ? 20 : 18)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).maxLines(CampusLayout.large(row) ? 2 : 1)
        .lineBreakStrategy(LineBreakStrategy.GREEDY)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        .id('campus-dining-relative-' + String(index))
      if (CampusLayout.large(row)) {
        Text(this.preview(row.id).items[index].detail).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  DiningPreview(row: CampusModule) {
    if (CampusLayout.large(row)) {
      Row({ space: 16 }) {
        Column() { this.DiningSummaryItem(row, 0) }.layoutWeight(1)
        Divider().vertical(true).height(54).color($r('app.color.input_surface'))
        Column() { this.DiningSummaryItem(row, 1) }.layoutWeight(1)
      }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Center)
    } else {
      Column({ space: 8 }) {
        this.DiningSummaryItem(row, 0)
        this.DiningSummaryItem(row, 1)
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
    }
  }
  @Builder
  CardRefresh(row: CampusModule) {
    FloatingActionButton({ label: this.preview(row.id).status === 'error' ? $r('app.string.ui_reload') : $r('app.string.campus_card_refresh'),
      icon: 'refresh', iconSize: 16, onCard: true, labelColor: ThemeColors.primary, controlHeight: 28, controlId: 'campus-card-refresh-' + row.id,
      actionEnabled: !this.loadingIds.includes(row.id), onAction: () => { this.read(row.id, true) } })
      .width(28).opacity(this.loadingIds.includes(row.id) ? 0.5 : 1)
      .onTouch((event: TouchEvent) => { event.stopPropagation() })
  }

  @Builder
  WaitingPreview(row: CampusModule) {
    Column({ space: CampusLayout.compact(row) ? 9 : 10 }) {
      Text(AppLanguage.text(this.loadingIds.includes(row.id) ? $r('app.string.campus_preview_loading') :
        $r('app.string.campus_preview_unavailable'), this.languageRevision))
        .draggable(false).fontSize(CampusLayout.compact(row) ? 15 : 18).fontWeight(FontWeight.Medium)
        .lineHeight(CampusLayout.compact(row) ? 20 : 26).fontColor(ThemeColors.textSecondary)
        .minFontSize(CampusLayout.compact(row) ? 12 : 15).maxFontSize(CampusLayout.compact(row) ? 15 : 18)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).maxLines(1).width('100%')
        .id('campus-preview-state-' + row.id)
      Text(this.waitingCaption(row.id, CampusLayout.compact(row))).draggable(false).fontSize(CampusLayout.compact(row) ? 11 : 13)
        .lineHeight(CampusLayout.compact(row) ? 14 : 20).fontColor(ThemeColors.textSecondary)
        .minFontSize(CampusLayout.compact(row) ? 9 : 12).maxFontSize(CampusLayout.compact(row) ? 11 : 13)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).maxLines(CampusLayout.compact(row) ? 1 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').id('campus-preview-hint-' + row.id)
    }.width('100%').alignItems(HorizontalAlign.Start).layoutWeight(1)
      .justifyContent(CampusLayout.compact(row) ? FlexAlign.Start : FlexAlign.Center)
  }
  @Builder
  CardContent(row: CampusModule, catalog: boolean = false) {
    Column({ space: CampusLayout.compact(row) ? 2 : (row.id === 'academic' && !CampusLayout.large(row)) || (row.id === 'library' && CampusLayout.large(row)) ? 4 : ThemeDimens.cardContentGap }) {
      Row({ space: CampusLayout.compact(row) ? 5 : 8 }) {
        if (row.id === 'sports') {
          Image($r('app.media.reservation_court')).width(CampusLayout.compact(row) ? 17 : 23)
            .height(CampusLayout.compact(row) ? 17 : 23).fillColor(this.tint(row.id))
        } else if (row.id === 'empty_classroom' || row.id === 'library' || row.id === 'library_books') {
          Image(row.id === 'empty_classroom' ? $r('app.media.classroom_buildings') : row.id === 'library' ? $r('app.media.library_columns') : $r('app.media.library_books'))
            .width(CampusLayout.compact(row) ? 17 : 23).height(CampusLayout.compact(row) ? 17 : 23).fillColor(this.tint(row.id))
        } else {
          SymbolGlyph(getSymbolIcon(row.id === 'academic' ? 'gpa' : row.id)).fontSize(CampusLayout.compact(row) ? 17 : 23).fontColor([this.tint(row.id)])
        }
          Text(AppLanguage.text(CampusLayout.title(row.id), this.languageRevision)).draggable(false)
            .fontSize(CampusLayout.compact(row) ? 14 : 17).fontWeight(FontWeight.Bold)
            .lineHeight(CampusLayout.compact(row) ? 20 : 24)
            .minFontSize(row.id === 'dining' ? (CampusLayout.compact(row) ? 11 : 14) : (CampusLayout.compact(row) ? 14 : 17))
            .maxFontSize(CampusLayout.compact(row) ? 14 : 17).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
            .fontColor(this.tint(row.id)).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (row.id === 'timetable' && CampusLayout.compact(row) && this.preview(row.id).items.length > 0) {
          Text($r('app.string.campus_course_periods', this.preview(row.id).items[0].value)).fontSize(10)
            .fontColor(ThemeColors.textSecondary).maxLines(1).id('campus-course-period-header')
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
        }
        if (catalog) {
          Stack() {
            SymbolGlyph(this.selected(row) ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'))
              .fontSize(CampusLayout.compact(row) ? 14 : 10).fontColor([this.selected(row) ? Color.White : ThemeColors.primary])
          }.width(14).height(14)
            .borderRadius(7).backgroundColor(this.selected(row) ? ThemeColors.primary : Color.Transparent)
            .id('campus-catalog-marker-' + row.id + '-' + CampusLayout.size(row)).hitTestBehavior(HitTestMode.None)
        }
        else { SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([ThemeColors.textSecondary])
          .width(14)
          .id('campus-card-detail-' + row.id) }
      }.width('100%').height(CampusLayout.compact(row) ? 28 : 24)
        .alignItems(VerticalAlign.Center).padding({ right: this.editing && !catalog ? 26 : 0 })
      Stack({ alignContent: Alignment.TopStart }) {
      ForEach([this.informationKey(row)], (_key: string) => {
      Column() {
      if (this.preview(row.id).status === 'error') {
        if (CampusLayout.compact(row)) {
          Column() {
            Text(DiagnosticNavigation.brief(this.previewFailures.get(row.id) ?? AppLanguage.text($r('app.string.campus_preview_failed'), this.languageRevision)))
              .fontSize(11).lineHeight(14).fontColor(ThemeColors.textSecondary).maxLines(1).width('100%').textOverflow({ overflow: TextOverflow.Ellipsis })
            DiagnosticLink({ message: this.previewFailures.get(row.id) ?? 'Error: Campus preview unavailable',
              controlId: 'campus-card-' + row.id + '-diagnostics', controlHeight: 24, interactive: !catalog && !this.editing })
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else {
          Column() {
            ErrorNotice({ message: this.previewFailures.get(row.id) ?? 'Error: Campus preview unavailable',
              controlId: 'campus-card-' + row.id + '-diagnostics', textMaxLines: 2, diagnosticHeight: 24,
              diagnosticInteractive: !catalog && !this.editing })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }
      } else if (this.previewUnavailable(row)) {
        this.WaitingPreview(row)
      } else if (row.id === 'timetable') {
        this.TimetablePreview(row)
      } else if (row.id === 'developer_notice') {
        this.DeveloperNoticePreview(row)
      } else if (row.id === 'announcement' && !CampusLayout.compact(row)) {
        this.NoticePreview(row, catalog)
      } else if (row.id === 'academic' && this.preview(row.id).gpa && this.preview(row.id).credits) {
        this.AcademicPreview(row)
      } else if (row.id === 'campus_access' && this.preview(row.id).status === 'ready' &&
        (this.preview(row.id).tone === 'normal' || this.preview(row.id).tone === 'critical')) {
        this.AccessSmallPreview(row)
      } else if (row.id === 'bus' && CampusLayout.large(row) && this.preview(row.id).status === 'ready' && this.preview(row.id).items.length > 0) {
        this.BusLargePreview(row)
      } else if (row.id === 'empty_classroom' && CampusLayout.large(row) && this.preview(row.id).status === 'ready' && this.preview(row.id).total > 0) {
        this.ClassroomLargePreview(row)
      } else if (row.id === 'library' && CampusLayout.large(row) && this.preview(row.id).status === 'ready' && this.preview(row.id).items.length > 0) {
        this.LibraryLargePreview(row)
      } else if (row.id === 'dining' && !CampusLayout.compact(row) && this.preview(row.id).status === 'ready' && this.preview(row.id).items.length === 2) {
        this.DiningPreview(row)
      } else {
      Column({ space: row.id === 'dining' && CampusLayout.compact(row) && this.cardKeyValue(row).length > 10 ? 1 : CampusLayout.compact(row) ? 7 : 6 }) {
      Text(ReadableText.keepWords(this.cardKeyValue(row) || AppLanguage.text(catalog ? $r('app.string.campus_preview_open') : $r('app.string.campus_preview_loading'), this.languageRevision)))
        .draggable(false).fontSize(CampusLayout.keyFont(row, this.keyValue(row.id))).fontWeight(FontWeight.Bold)
        .minFontSize(row.id === 'dining' && CampusLayout.compact(row) ? 11 : 14)
        .maxFontSize(row.id === 'dining' && CampusLayout.compact(row) && this.cardKeyValue(row).length > 10 ? 13 : CampusLayout.keyFont(row, this.keyValue(row.id)))
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .lineHeight(row.id === 'dining' && CampusLayout.compact(row) && this.cardKeyValue(row).length > 10 ? 14 : CampusLayout.compact(row) ? 22 : CampusLayout.keyFont(row, this.keyValue(row.id)) + 8).fontColor(this.keyColor(row.id))
        .maxLines(row.id === 'dining' && CampusLayout.compact(row) && this.cardKeyValue(row).length > 10 ? 2 : 1)
        .lineBreakStrategy(LineBreakStrategy.GREEDY).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (CampusLayout.compact(row) && !(row.id === 'campus_access' && this.preview(row.id).status === 'ready')) {
        Text(this.compactCaption(row.id)).draggable(false).fontSize(11).minFontSize(9).maxFontSize(11)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).lineHeight(14).fontColor(ThemeColors.textSecondary)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      } else if (row.id === 'campus_access' && this.preview(row.id).status === 'ready' && !CampusLayout.compact(row) && this.preview(row.id).description) {
        this.AccessAccountStatus(row)
      } else if (row.id === 'academic' && this.preview(row.id).calculation === 'local-v1' && !CampusLayout.large(row)) {
        Column({ space: 2 }) {
          Text(this.academicCaption(true)).fontSize(12).lineHeight(16).fontColor(ThemeColors.textSecondary).maxLines(1)
          Text(this.academicCaption(false)).fontSize(12).lineHeight(16).fontColor(ThemeColors.textSecondary).maxLines(1)
        }.width('100%').alignItems(HorizontalAlign.Start)
      } else if (row.id === 'sports' && !CampusLayout.large(row)) {
        Text($r('app.string.campus_sports_short_hint')).fontSize(12).minFontSize(10).maxFontSize(12)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).lineHeight(20)
          .fontColor(ThemeColors.textSecondary).width('100%').maxLines(1)
      } else if (this.preview(row.id).description && !(row.id === 'campus_access' && this.preview(row.id).status === 'ready')) {
        Text(ReadableText.keepWords(row.id === 'empty_classroom' ? this.preview(row.id).description.split(' · ')[0] : this.preview(row.id).description)).draggable(false).fontSize(13).lineHeight(22).fontColor(ThemeColors.textSecondary).width('100%')
          .maxLines(CampusLayout.large(row) ? 3 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      }.width('100%').alignItems(HorizontalAlign.Start).layoutWeight(1)
        .justifyContent(CampusLayout.compact(row) ? FlexAlign.Start : FlexAlign.Center)
      }
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }, (key: string) => key)
      }.width('100%').layoutWeight(1).clip(true).id('campus-information-' + row.id)
        // Match the normal card's refresh clearance in the catalogue as well.
        .padding({ right: CampusLayout.compact(row) && row.id !== 'timetable' ? 24 : 0 })
      if (!CampusLayout.compact(row)) {
      Stack({ alignContent: Alignment.Start }) {
        ForEach([this.cardFooter(row)], (caption: string) => {
        if (row.id === 'sports') {
          Column() {
            ForEach(caption.split(' · ').slice(0, 2), (name: string) => {
              Text(name).draggable(false).fontSize(11).minFontSize(9).maxFontSize(11)
                .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
                .lineHeight(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(ThemeColors.textSecondary).width('100%')
            }, (name: string) => name)
          }.width('100%').alignItems(HorizontalAlign.Start)
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
        } else {
        Text(ReadableText.keepWords(caption))
          .draggable(false).fontSize(11).lineHeight(14)
          .lineBreakStrategy(LineBreakStrategy.GREEDY)
          .fontColor(ThemeColors.textSecondary).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
        }
        }, (caption: string) => caption)
      }.width('100%').height(28).clip(true).id('campus-footer-' + row.id)
        .padding({ right: 28 })
      }
    }.width('100%').height('100%').constraintSize({ minHeight: CampusLayout.compact(row) ? CampusLayout.HALF_HEIGHT : CampusLayout.FULL_HEIGHT,
      maxHeight: CampusLayout.compact(row) ? CampusLayout.HALF_HEIGHT : CampusLayout.FULL_HEIGHT })
      .padding({ left: ThemeDimens.cardInset, right: ThemeDimens.cardInset,
        top: CampusLayout.compact(row) ? ThemeDimens.compactCardTopInset : ThemeDimens.cardInset,
        bottom: CampusLayout.compact(row) ? ThemeDimens.compactCardVerticalInset : ThemeDimens.cardInset })
      .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start).borderRadius(CampusLayout.compact(row) ? 20 : 24)
      .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(this.editing && !catalog ? undefined : adaptiveMaterial(this.materialRevision))
      .onClick(() => { if (catalog) this.choose(row.id, CampusLayout.size(row)); else this.open(row.id) }).accessibilityRole(AccessibilityRoleType.BUTTON)
      .accessibilityText(AppLanguage.text(CampusLayout.title(row.id), this.languageRevision))
  }
  @Builder
  CardBody(row: CampusModule) {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.CardContent(row)
      if (!this.editing) {
        // A 14vp control radius shares the card's corner centre: R - 14 inset.
        Row() { this.CardRefresh(row) }.width(28).height(28)
          .position({ right: CampusLayout.compact(row) ? 6 : 10, bottom: CampusLayout.compact(row) ? 6 : 10 })
      }
      if (this.editing) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([Color.White])
        }.width(28).height(28).padding(0).backgroundColor(ThemeColors.error).stateEffect(false)
          .enabled(!this.saving).margin({ top: 6, right: 6 })
          .onTouch((event: TouchEvent) => { event.stopPropagation() })
          .onClick(() => { this.toggle(row.id) }).accessibilityText($r('app.string.campus_remove_card'))
          .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
      }
    }.width('100%').height('100%').draggable(false).renderGroup(true)
  }
  @Builder
  Card(row: CampusModule) {
    Stack() {
      ForEach([this.motion(row.id)], (motion: CampusCardMotion) => {
        CampusMovingCard({ motion: motion, cardId: row.id, radius: CampusLayout.compact(row) ? 20 : 24, content: () => { this.CardBody(row) } })
      }, (_motion: CampusCardMotion) => row.id)
    }.width('100%').height('100%')
      .onGestureJudgeBegin((info: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
        if (info.type === GestureControl.GestureType.DRAG) return GestureJudgeResult.REJECT
        if ((info.type === GestureControl.GestureType.LONG_PRESS_GESTURE || info.type === GestureControl.GestureType.PAN_GESTURE) &&
          (!this.editing || this.saving || this.showAdd)) return GestureJudgeResult.REJECT
        return GestureJudgeResult.CONTINUE
      })
      // Reordering can connect moved slots; mode changes keep the same native nodes.
      .geometryTransition(this.editing && !this.draggingId ? 'campus-card-' + row.id : '')
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.96, y: 0.96 })).animation({ duration: 260, curve: Curve.Friction }))
  }
  @Builder
  CatalogCard(row: CampusModule) {
    Column() {
      Stack() {
        this.CardContent(row, true)
        if (this.selected(row)) {
          Column().width('100%').height('100%').border({ width: 2, color: ThemeColors.primary })
            .borderRadius(CampusLayout.compact(row) ? 20 : 24).hitTestBehavior(HitTestMode.None)
        }
      }.width('100%').height(CampusLayout.compact(row) ? CampusLayout.HALF_HEIGHT : CampusLayout.FULL_HEIGHT)
    }
      .width('100%')
      .id('campus-catalog-' + row.id + '-' + CampusLayout.size(row))
      .accessibilityText(AppLanguage.text(CampusLayout.title(row.id), this.languageRevision) + ' · ' +
        AppLanguage.text(this.sizeLabel(row), this.languageRevision) + ' · ' + AppLanguage.text(this.catalogStatus(row), this.languageRevision))
      .accessibilityRole(AccessibilityRoleType.BUTTON)
  }
  @Builder
  AddSheet() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Text($r('app.string.campus_add_card')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        FloatingActionButton({ label: $r('app.string.campus_restore_layout'), controlHeight: 40,
          controlId: 'campus-catalog-restore', actionEnabled: !this.saving, onAction: () => { this.restore() } }).width(132)
        this.IconAction($r('sys.symbol.xmark'), $r('app.string.forum_cancel'), () => { this.showAdd = false }, false, 'campus-catalog-close')
      }.width('100%')
      Text($r('app.string.campus_catalog_note')).fontSize(13).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%')
      Scroll() {
        Column({ space: 16 }) {
          ForEach(['compact', 'small', 'large'], (size: string) => {
            Text(size === 'compact' ? $r('app.string.campus_size_compact') :
              size === 'large' ? $r('app.string.campus_size_large') : $r('app.string.campus_size_small'))
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
            GridRow({ columns: 2, gutter: { x: 12, y: 12 } }) {
              ForEach(this.templates(size), (row: CampusModule) => {
                GridCol({ span: CampusLayout.large(row) ? 2 : 1 }) { this.CatalogCard(row) }
              }, (row: CampusModule) => row.id + ':' + size + ':' + this.selected(row))
            }.width('100%')
          }, (size: string) => size)
        }.width('100%').padding({ bottom: 24 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: 20, bottom: 20 }).width('100%').height('100%')
  }
  @Builder
  IconAction(icon: Resource, label: Resource, action: () => void, media: boolean = false, controlId: string = '') {
    FloatingActionButton({ label: label, icon: 'campus-action', iconResource: icon, iconResourceIsMedia: media,
      controlHeight: 48, controlId: controlId, actionEnabled: !this.saving, onAction: action }).width(48)
  }
  @Builder
  CardGrid() {
    Stack({ alignContent: Alignment.TopStart }) {
    Grid() {
      ForEach(this.packed().cards, (placement: CampusCardPlacement) => {
        GridItem() { this.Card(placement.module) }
          .rowStart(placement.row).rowEnd(placement.row + placement.rowSpan - 1)
          .columnStart(placement.column).columnEnd(placement.column + placement.columnSpan - 1)
          .zIndex(this.draggingId === placement.module.id ? 2 : 0)
      // Plain placement objects are not observed. Recreate only moved slots so
      // reused GridItems cannot keep captured coordinates after reordering.
      // Card geometry IDs remain stable to connect their position animation.
      }, (placement: CampusCardPlacement) => placement.module.id + ':' + CampusLayout.size(placement.module) +
        ':' + placement.row + ':' + placement.column)
    }.columnsTemplate('1fr 1fr').rowsTemplate(this.boardPlan().template())
      .columnsGap(CampusLayout.CARD_GAP).rowsGap(CampusLayout.CARD_GAP)
      .width('100%').height(this.boardPlan().height()).clip(false)
    ForEach([this.dropPosition], (position: CampusDropPosition) => {
        CampusDropIndicator({ dropModel: position })
    }, () => 'campus-drop-indicator')
    }.width('100%').height(this.boardPlan().height())
      .onAreaChange((_old: Area, area: Area) => { this.recordBoard(area) })
  }
  @Builder
  CardScroll() {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            this.CardGrid()
          }.width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: this.inset(), bottom: Math.max(16, px2vp(this.bottomPx)) + 112 })
        }.width('100%').height('100%').scrollBar(BarState.Off)
          .edgeEffect(this.draggingId ? EdgeEffect.None : EdgeEffect.Spring, { alwaysEnabled: !this.draggingId })
          .enableScrollInteraction(!this.draggingId)
          .onGestureJudgeBegin((info: GestureInfo) => {
            // The held-card pointer and the forwarded native scroll stay separate.
            // Reject Scroll's competing pan recognizer, not the touch stream.
            if (this.draggingId && info.type === GestureControl.GestureType.PAN_GESTURE) return GestureJudgeResult.REJECT
            return GestureJudgeResult.CONTINUE
          })
          .onTouch((event: TouchEvent) => { if (!this.draggingId) settleScrollTouch(this.scroller, event) })
          .onAreaChange((_old: Area, area: Area) => { this.recordViewport(area) })
          // Match the committed native offset directly, without scheduling
          // another scroll frame or invalidating the whole board.
          .onDidScroll(() => { if (this.draggingId) this.applyDragPosition() })
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
      Row().width(0).height(0)
        .bindSheet($$this.showAccess, this.AccessDetails(), this.showAccessTransition.options(this.showAccess, { height: SheetSize.FIT_CONTENT,
          showClose: false, dragBar: true, backgroundColor: $r('app.color.surface_fallback'), systemMaterial: adaptiveMaterial(this.materialRevision) }))
      // A native node has one sheet binding. Keep electricity separate from
      // the root's card catalogue so its hidden binding cannot hide that sheet.
      Row().width(0).height(0)
        .bindSheet($$this.showElectricity, this.ElectricityDetails(), this.showElectricityTransition.options(this.showElectricity, { height: SheetSize.FIT_CONTENT,
          showClose: false, dragBar: true,
          backgroundColor: $r('app.color.surface_fallback'), systemMaterial: adaptiveMaterial(this.materialRevision) }))
      // Mounted beneath the real board, so both simultaneous and later second
      // pointers can be forwarded here without reparenting an active gesture.
      Scroll(this.momentumScroller) {
        Column().height(Math.max(1, this.scrollLimit()) + 1).width(1)
      }.width(1).height(1).opacity(0).scrollBar(BarState.Off)
        .responseRegion({ x: 0, y: 0, width: this.boardWidth + ThemeDimens.cardGutter * 2, height: this.viewportHeight })
        .accessibilityLevel('no-hide-descendants').edgeEffect(EdgeEffect.None)
        .id('campus-native-drag-scroll')
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.nativeDragScrollReady = false
            this.momentumOffset = this.scrollOffset()
            this.momentumScroller.scrollTo({ xOffset: 0, yOffset: this.momentumOffset, animation: false })
            this.nativeDragScrollReady = true
            this.scrollPointer = event.changedTouches[0]?.id ?? -1
            this.autoScrollSpeed = 0; this.dragMomentum = false
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.scrollPointer = -1; this.dragMomentum = event.type === TouchType.Up
          }
        })
        .onWillScroll((xOffset: number, yOffset: number) => {
          // Forward before layout, so both native surfaces commit in one frame.
          // Forwarding in onDidScroll instead introduces a second layout frame.
          if (this.nativeDragScrollReady && this.draggingId) this.scrollDragBy(yOffset)
          return { xOffset: xOffset, yOffset: yOffset }
        })
        .onDidScroll(() => { if (!this.nativeDragScrollReady) this.advanceDragMomentum() })
        .onScrollStop(() => { this.dragMomentum = false; this.updateAutoScroll() })
      this.CardScroll()

      if (this.draggingId) {
        ForEach(this.rows.filter(row => row.id === this.draggingId && row.enabled), (row: CampusModule) => {
          ForEach([this.heldPosition], (dragPosition: CampusDragPosition) => {
            CampusDragCard({ dragPosition: dragPosition, cardId: row.id, content: () => { this.CardBody(row) } })
          })
        }, (row: CampusModule) => row.id)
      }
      TopFade({ extent: this.headerExtent })
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.editing ? AppLanguage.text($r('app.string.campus_edit_layout'), this.languageRevision) : this.welcome())
            .draggable(false).fontSize(29).minFontSize(23).maxFontSize(29).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary).maxLines(2).layoutWeight(1)
            .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).lineHeight(36)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.editing) {
            this.IconAction($r('sys.symbol.plus'), $r('app.string.campus_add_card'), () => { this.add() }, false, 'campus-layout-add')
            this.IconAction(getSaveIcon(), $r('app.string.save_settings'), () => { this.save() }, true, 'campus-layout-save')
            this.IconAction($r('sys.symbol.xmark'), $r('app.string.forum_cancel'), () => { this.cancel() }, false, 'campus-layout-cancel')
          } else {
            this.IconAction(getSymbolIcon('refresh'), $r('app.string.campus_card_refresh'), () => { this.refresh(true) }, false, 'campus-home-refresh')
            this.IconAction($r('sys.symbol.square_and_pencil'), $r('app.string.campus_edit_layout'), () => { this.edit() }, false, 'campus-layout-edit')
          }
        }.width('100%').constraintSize({ minHeight: 48 }).alignItems(VerticalAlign.Center)
        // Hidden siblings reserve one stable header slot during edit/return.
        Stack({ alignContent: Alignment.TopStart }) {
          Text(this.greeting()).draggable(false).fontSize(21).fontWeight(FontWeight.Medium)
            .lineHeight(29).fontColor(ThemeColors.textPrimary).width('100%')
            .opacity(this.editing ? 0 : this.greetingOpacity).renderGroup(true)
          Text($r('app.string.campus_edit_note')).fontSize(13).lineHeight(20)
            .fontColor(ThemeColors.textSecondary).width('100%').opacity(this.editing ? 1 : 0)
        }.width('100%').hitTestBehavior(HitTestMode.None)
        Row() {
          Text(AppLanguage.text(CampusPreference.title(this.currentCampus), this.languageRevision)).fontSize(12).fontColor(ThemeColors.primary)
          Blank()
          Text(AppLanguage.weekday(new Date(this.clock).getDay() || 7, this.languageRevision)).fontSize(12).fontColor(ThemeColors.textSecondary)
        }.width('100%')
      }.width('100%').padding({ top: Math.max(0, px2vp(this.topPx)) + 4, left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => { this.updateHeader(size) })
        .hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onTouchIntercept((event: TouchEvent): HitTestMode => {
        this.hitPointer = event.changedTouches[0]?.id ?? -1
        this.hitY = event.changedTouches[0]?.windowY ?? 0
        return HitTestMode.Default
      })
      .onChildTouchTest((): TouchResult => {
        const first: number = this.draggingId ? this.dragPointer : this.pendingPointer
        if (this.editing && !this.saving && !this.showAdd && (this.draggingId || this.pendingId) &&
          first >= 0 && this.hitPointer >= 0 && this.hitPointer !== first &&
          this.hitY >= this.viewportY + this.inset() &&
          this.hitY < this.viewportY + this.viewportHeight - Math.max(16, px2vp(this.bottomPx)) - 112) {
          return { strategy: TouchTestStrategy.FORWARD, id: 'campus-native-drag-scroll' }
        }
        return { strategy: TouchTestStrategy.DEFAULT }
      })
      .onAreaChange((_old: Area, area: Area) => { this.recordViewport(area) })
      .onTouch((event: TouchEvent) => { this.dragTouch(event) })
      .bindSheet($$this.showAdd, this.AddSheet(), this.showAddTransition.options(this.showAdd, { height: SheetSize.LARGE, showClose: false, dragBar: false }))
  }
}
