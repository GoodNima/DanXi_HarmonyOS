import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice } from '../components/ErrorNotice'
import { settleScrollTouch } from '../common/ScrollTouch'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { ReviewVoteState } from '../model/ReviewVoteState'
import { ReviewVoteControls } from '../components/ReviewVoteControls'
import { ReviewPresentation } from '../common/ReviewPresentation'
import { router, promptAction, window, display } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { Constant } from '../common/Constant'
import { AppState } from '../common/AppState'
import { AppLanguage } from '../common/AppLanguage'
import { CampusService } from '../common/CampusService'
import { CampusUtilities, CampusUtilitySnapshot } from '../common/CampusUtilities'
import { CampusUtilityPageSource, DefaultCampusUtilityPageSource } from '../common/CampusUtilitySource'
import { BrowserLink } from '../common/BrowserLink'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
import { CampusSignal } from '../common/CampusSignal'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { ForumRepository } from '../repository/ForumRepository'
import { FduRepository } from '../repository/FduRepository'
import { HttpError } from '../util/HttpUtil'
import { ForumRoute } from '../common/ForumRoute'
import { CampusUtilityRepository } from '../repository/CampusUtilityRepository'
import { CampusUtilityParams, CampusAccessCard, ExerciseItem, ExerciseRecord, LifeCodeTermsError } from '../model/CampusUtility'
import { CourseReviewGroup, CourseReview, CourseReviewDraft, ReviewCourse, ReviewRating } from '../model/CourseReview'
import { TopFade } from '../components/TopFade'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { getSymbolIcon } from '../common/DanXiIcons'
import { ForumContentView } from '../components/ForumContentView'
import { ForumListSource } from '../common/ForumListSource'
import { CourseReviewSummaryLoader } from '../common/CourseReviewSummaryLoader'
import { CourseReviewRepository } from '../repository/CourseReviewRepository'
import { CourseReviewSummary } from '../model/CourseReview'
import { CourseReviewSummaryState } from '../model/CourseReviewSummaryState'
import { CourseReviewSummaryView } from '../components/CourseReviewSummaryView'
import { LiveSearch } from '../common/LiveSearch'
import { SearchClearButton } from '../components/SearchClearButton'

/** Campus services use compact cards and a shared floating header. DanKe uses
 * the original search → course → teacher/term-filtered reviews → editor flow. */
@Entry
@Component
export struct CampusUtilityPage {
  private editorTransition: SheetTransitionGuard = new SheetTransitionGuard()
  initialFeature: string = ''
  mainTab: boolean = false
  sheetMode: boolean = false
  onSheetClose: () => void = () => {}
  source: CampusUtilityPageSource = new DefaultCampusUtilityPageSource()
  canVerify: () => boolean = () => FduRepository.getInstance().canLoginOnDemand()
  verifyService: (service: string) => Promise<string> = (service: string) => FduRepository.getInstance().verifyService(service)
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink('app_dark_mode') dark: boolean = false
  @StorageLink(AppLanguage.KEY_REVISION) @Watch('languageChanged') languageRevision: number = 0
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') personJson: string = ''
  @StorageLink(ForumRepository.KEY_SESSION_REVISION) @Watch('accountChanged') forumRevision: number = 0
  @StorageLink('app_foreground') @Watch('foregroundChanged') foreground: boolean = true
  @StorageLink('main_active_tab') @Watch('activate') activeTab: number = 0
  @StorageLink('main_route_visible') @Watch('activate') mainVisible: boolean = true
  @StorageLink('evaluation_back_request') @Watch('requestedBack') backRequest: number = 0
  @State feature: string = 'sports'
  @State refreshing: boolean = false
  @State loading: boolean = false
  @State error: string = ''
  @State termsRequired: boolean = false
  @State verificationRequired: boolean = false
  @State verifying: boolean = false
  @State snapshot: CampusUtilitySnapshot = new CampusUtilitySnapshot()
  @State query: string = ''
  @State searchKeyword: string = ''
  private liveSearch: LiveSearch = new LiveSearch(() => { if (this.active) this.search() })
  @State @Watch('groupsChanged') groups: CourseReviewGroup[] = []
  private courseGroups: ForumListSource<CourseReviewGroup> = new ForumListSource<CourseReviewGroup>()
  private courseSummaries: Map<number, CourseReviewSummaryState> = new Map<number, CourseReviewSummaryState>()
  private detailSummary: CourseReviewSummaryState | null = null
  private detailSummaryId: number = 0
  private summaryFirst: number = 0
  private summaryLast: number = 3
  private catalogUnsubscribe: (() => void) | null = null
  private catalogPending: boolean = false
  private catalogScrolling: boolean = false
  private summaryLoader: CourseReviewSummaryLoader = new CourseReviewSummaryLoader(
    (id: number) => this.source.summary(id),
    (id: number, value: CourseReviewSummary) => { this.publishSummary(id, value) })
  @State private moreError: string = ''
  private reviewVotes: Map<number, ReviewVoteState> = new Map()
  private detailReviews: ForumListSource<CourseReview> = new ForumListSource<CourseReview>()
  @State recommendations: CourseReview[] = []
  @State randomReview: CourseReview | null = null
  @State @Watch('groupChanged') group: CourseReviewGroup | null = null
  @State page: number = 1
  @State more: boolean = false
  @State loadingMore: boolean = false
  @State private navigationLoading: boolean = false
  @State private readPending: boolean = false
  @State private contentOpacity: number = 1
  private contentRevision: number = 0
  private revealRevision: number = 0
  private listReturnOffset: number = 0
  @State @Watch('reviewsChanged') teacher: string = ''
  @State @Watch('reviewsChanged') term: string = ''
  @State editor: boolean = false
  @State editing: CourseReview | null = null
  @State draft: CourseReviewDraft = new CourseReviewDraft()
  @State sending: boolean = false
  @State mutating: number = 0
  private generation: number = 0
  private active: boolean = false
  private mounted: boolean = false
  @State private loaded: boolean = false
  private routeVisible: boolean = false
  private boundScope: string = ''
  private readFlight: Promise<void> | null = null
  private refreshAfterVote: boolean = false
  private readKey: string = ''
  private writeRevision: number = 0
  private needsRead: boolean = false
  private brightnessRevision: number = 0
  private brightnessQueue: Promise<void> = Promise.resolve()
  private brightWindow: window.Window | null = null
  private previousBrightness: number = -1
  private scroller: Scroller = new Scroller()
  private viewportHeight: number = 0
  private contentHeight: number = 0

  // Native List owns its terminal scroll boundary even when the footer has no content.
  private listBottomInset(): number { return Math.max(22, px2vp(this.bottomPx) + (this.mainTab ? 108 : 22)) }
  private contentInset(): number { return px2vp(this.topPx) + (this.feature === 'evaluation' ? 72 : 84) }
  private headerExtent(): number { return px2vp(this.topPx) + (this.feature === 'evaluation' ? 52 : 64) }

  aboutToAppear(): void {
    this.mounted = true
    this.routeVisible = true; this.active = this.foreground
    if (CampusUtilities.supported(this.initialFeature)) this.feature = this.initialFeature
    if (this.feature === 'evaluation' && this.source instanceof DefaultCampusUtilityPageSource) {
      this.catalogUnsubscribe = CourseReviewRepository.subscribeCatalog(() => {
        this.catalogPending = true; this.applyCatalogUpdate()
      })
    }
    if (this.mainTab) { this.active = false; this.activate(); return }
    const params = router.getParams() as CampusUtilityParams
    if (!CampusUtilities.supported(this.initialFeature) && params !== undefined && CampusUtilities.supported(params.feature)) this.feature = params.feature
    if (this.feature === 'sports' && this.source instanceof DefaultCampusUtilityPageSource) {
      router.replaceUrl({ url: 'pages/ReservationPage' }); return
    }
    this.reload(false)
  }
  aboutToDisappear(): void {
    this.catalogUnsubscribe?.(); this.catalogUnsubscribe = null
    this.catalogPending = false; this.catalogScrolling = false
    this.liveSearch.cancel()
    this.summaryLoader.pause(); this.summaryLoader.reset()
    this.mounted = false
    if (this.mainTab) AppStorage.setOrCreate<boolean>('evaluation_detail_open', false)
    this.contentRevision++
    this.routeVisible = false; this.active = false; this.generation++; this.writeRevision++
    this.restoreBrightness(); this.snapshot = new CampusUtilitySnapshot()
    this.editor = false; this.draft = new CourseReviewDraft(); this.group = null; this.groups = []; this.randomReview = null; this.recommendations = []; this.reviewVotes.clear()
  }
  onPageHide(): void {
    this.liveSearch.pause()
    this.summaryLoader.pause()
    this.catalogScrolling = false
    if (this.mainTab) { this.active = false; this.contentRevision++; this.contentOpacity = 1; return }
    this.contentRevision++; this.contentOpacity = 1
    this.routeVisible = false; this.active = false; this.restoreBrightness()
    if (this.feature === 'life_code') this.snapshot = new CampusUtilitySnapshot()
  }
  onPageShow(): void {
    if (this.mainTab) { this.activate(); return }
    this.routeVisible = true; this.active = this.foreground
    if (!this.active) return
    if (this.verifying) return
    if (this.boundScope !== this.source.scope(this.feature)) { this.accountChanged(); return }
    this.liveSearch.resume()
    this.loadSummaries()
    this.applyCatalogUpdate()
    // A service verification route may return before its original read settles.
    // Keep that read alive rather than opening a second verification request.
    if (this.readFlight !== null) return
    // A failed code request or consent decision waits for the visible Retry/
    // verification action. Returning from another route is not a retry request.
    // Successful codes are cleared on hide and still obtain a fresh code below.
    if (this.feature === 'life_code' && (this.error || this.termsRequired || this.verificationRequired)) {
      this.loading = false; this.refreshing = false; return
    }
    if (this.needsRead || this.loading || (this.feature === 'life_code' && !this.snapshot.code.value && !this.verificationRequired)) this.reload(false)
  }
  private foregroundChanged(): void {
    if (this.mainTab) { this.activate(); return }
    if (!this.foreground) {
      this.summaryLoader.pause()
      this.active = false; this.restoreBrightness()
      if (this.feature === 'life_code') this.snapshot = new CampusUtilitySnapshot()
    } else if (this.routeVisible) this.onPageShow()
  }
  private activate(): void {
    if (!this.mainTab || !this.mounted) return
    const visible: boolean = this.foreground && this.mainVisible && this.activeTab === 3
    if (!visible) {
      this.liveSearch.pause()
      this.summaryLoader.pause()
      this.catalogScrolling = false
      if (this.active) { this.contentRevision++; this.contentOpacity = 1 }
      this.active = false; return
    }
    const entered: boolean = !this.active
    this.active = true
    if (entered) this.focusReviewList()
    if (this.boundScope !== this.source.scope(this.feature)) { this.accountChanged(); return }
    this.liveSearch.resume()
    this.loadSummaries()
    this.applyCatalogUpdate()
    if (this.readFlight !== null || this.verifying) return
    if (this.needsRead || (!this.loaded && !this.error)) this.reload(false)
  }
  private focusReviewList(): void {
    if (this.feature !== 'evaluation' || this.group !== null || !this.active) return
    // Tabs may restore a previously focused child. Entering selects the list;
    // clicking the input still uses native editing and automatic LiveSearch.
    try { this.getUIContext().getFocusController().requestFocus('course-feed-list') }
    catch (e) { console.warn('CourseReview: list focus is not mounted yet') }
  }
  private groupChanged(): void {
    if (this.group !== null) {
      // Never assign a property of the watched @State object here: a pending
      // detail has no reviews yet and would synchronously re-enter this watch.
      this.summaryState(this.group).update(this.group, this.group.summary)
    } else { this.detailSummary = null; this.detailSummaryId = 0 }
    this.reviewsChanged()
    if (this.mainTab) AppStorage.setOrCreate<boolean>('evaluation_detail_open', this.group !== null)
  }
  private reviewsChanged(): void {
    this.detailReviews.update(this.group?.filtered(this.teacher, this.term) ?? [])
  }
  private groupsChanged(): void {
    // Pagination must retain failed/in-flight summaries. Re-deriving them here
    // erased diagnostics while the loader correctly suppressed failed retries.
    const ids = new Set<number>(this.groups.map(group => group.id))
    for (const id of this.courseSummaries.keys()) if (!ids.has(id)) this.courseSummaries.delete(id)
    this.courseGroups.update(this.groups); this.loadSummaries()
  }
  private applyCatalogUpdate(): void {
    if (!this.catalogPending || !this.active || !this.mounted || this.feature !== 'evaluation' ||
      !(this.source instanceof DefaultCampusUtilityPageSource) || this.boundScope !== this.source.scope(this.feature) ||
      !this.loaded || this.searchKeyword || this.group !== null || this.readPending || this.loading || this.loadingMore ||
      this.navigationLoading || this.catalogScrolling) return
    const result = CourseReviewRepository.cachedCatalogPages(this.page)
    if (result === null) return
    this.catalogPending = false
    // Update data in the existing lazy list. Do not restart the page's loading
    // transition or replace rows while a gesture/retained detail is active.
    this.groups = result.items
    this.page = Math.max(1, Math.ceil(result.items.length / result.pageSize))
    this.more = result.items.length >= result.page * result.pageSize
  }
  private summaryState(group: CourseReviewGroup): CourseReviewSummaryState {
    if (this.group !== null && this.group.id === group.id) {
      if (this.detailSummary === null || this.detailSummaryId !== group.id) {
        this.detailSummary = new CourseReviewSummaryState(group); this.detailSummaryId = group.id
      }
      return this.detailSummary
    }
    let state = this.courseSummaries.get(group.id)
    if (state === undefined) { state = new CourseReviewSummaryState(group); this.courseSummaries.set(group.id, state) }
    return state
  }
  private loadSummaries(): void {
    if (this.active && this.feature === 'evaluation' && this.group === null) {
      this.summaryLoader.update(this.groups, this.summaryFirst, this.summaryLast, this.source.scope(this.feature))
    } else this.summaryLoader.pause()
  }
  private publishSummary(id: number, value: CourseReviewSummary): void {
    if (!this.active || this.group !== null) return
    const index: number = this.groups.findIndex(group => group.id === id)
    // The repository may have already filled the shared directory row. Commit
    // a local snapshot without replacing the lazy row or its static content.
    if (index < 0) return
    this.groups[index].summary = value
    this.summaryState(this.groups[index]).update(this.groups[index], value)
  }
  private requestedBack(): void { if (this.mainTab && this.active && this.group !== null) this.back() }
  private accountChanged(): void {
    if (!this.active) return
    if (this.boundScope === this.source.scope(this.feature)) return
    this.liveSearch.cancel()
    this.summaryLoader.pause(); this.summaryLoader.reset(); this.summaryFirst = 0; this.summaryLast = 3
    this.catalogPending = false; this.catalogScrolling = false
    this.loaded = false
    this.contentRevision++; this.contentOpacity = 1; this.navigationLoading = false; this.readPending = false; this.listReturnOffset = 0
    this.generation++; this.writeRevision++; this.group = null; this.groups = []; this.randomReview = null; this.recommendations = []; this.reviewVotes.clear()
    this.snapshot = new CampusUtilitySnapshot(); this.draft = new CourseReviewDraft(); this.editor = false
    this.restoreBrightness(); this.error = ''; this.loading = false; this.refreshing = false
    this.loadingMore = false; this.sending = false; this.mutating = 0
    this.refreshAfterVote = false
    this.reload(false)
  }
  private languageChanged(): void {
    if (!this.active) return
    // Theme/language are display preferences. They must not restart a read,
    // lose a payment credential, or repeat an in-flight review submission.
  }
  private text(resource: Resource, ...args: (string | number)[]): string { return AppLanguage.text(resource, this.languageRevision, ...args) }
  private current(version: number, scope: string): boolean {
    // A tab keeps an already-started read when another tab or verification route
    // covers it. Its owner and generation still guard every completion.
    return (this.active || (this.mainTab && this.mounted)) && version === this.generation && scope === this.source.scope(this.feature)
  }
  private reload(force: boolean = true): Promise<void> {
    if (!this.active || this.verifying) return Promise.resolve()
    if (this.hasPendingVote()) { this.refreshAfterVote = true; return Promise.resolve() }
    const key: string = this.source.scope(this.feature) + '/' + this.feature + '/' + String(this.group?.id ?? 0) + '/' + this.searchKeyword
    if (this.readFlight !== null && this.readKey === key) return this.readFlight
    this.readKey = key
    const task = this.read(force)
    this.readFlight = task
    task.finally(() => {
      if (this.readFlight === task) {
        this.readFlight = null
        if (this.mainTab && this.active && this.boundScope !== this.source.scope(this.feature)) this.accountChanged()
      }
    })
    return task
  }
  private async read(force: boolean): Promise<void> {
    if (this.feature === 'evaluation' && this.group === null) {
      this.summaryLoader.pause()
      if (force) this.summaryLoader.reset()
      this.summaryFirst = 0; this.summaryLast = 3
    }
    const version = ++this.generation; const scope = this.source.scope(this.feature)
    this.readPending = true
    this.boundScope = scope; this.needsRead = false
    this.error = ''; this.termsRequired = false; this.verificationRequired = false; this.loading = this.snapshot.updatedAt <= 0 && this.randomReview === null && this.groups.length === 0
    this.loadingMore = false
    this.moreError = ''
    if (this.feature === 'life_code') { this.snapshot = new CampusUtilitySnapshot(); this.restoreBrightness() }
    try {
      if (this.feature === 'evaluation') {
        if (this.group !== null) {
          const result = await this.source.group(this.group.id, force)
          if (this.current(version, scope)) {
            if (!result.summary.ready && !result.summary.error) result.summary = CourseReviewSummary.from(result)
            for (const course of result.courses) for (const review of course.reviews) {
              const state = this.reviewVotes.get(review.id)
              if (state !== undefined && !state.pending) state.update(review)
            }
            await this.revealLoaded(() => { this.group = result }, version, scope)
          }
        } else {
          const result = await this.source.search(this.searchKeyword, 1, force)
          for (const row of result.items) if (!row.summary.ready && !row.summary.error) row.summary = CourseReviewSummary.from(row)
          if (this.current(version, scope)) await this.revealLoaded(() => { this.groups = result.items; this.page = 1; this.more = result.items.length >= result.pageSize }, version, scope)
        }
      } else {
        const result = await this.source.load(this.feature, force)
        if (this.current(version, scope)) {
          await this.revealLoaded(() => { this.snapshot = result }, version, scope)
          if (this.feature === 'life_code') this.brighten(version, scope)
        }
      }
      if (this.current(version, scope)) this.loaded = true
    } catch (e) {
      // Retain a same-owner code failure that settles while hidden, so return
      // cannot silently restart that failed HTTP request. Never retain a code.
      if (this.current(version, scope) || (this.feature === 'life_code' &&
        version === this.generation && scope === this.source.scope(this.feature))) {
        this.error = ErrorDiagnostics.message(e as Object)
        this.termsRequired = e instanceof LifeCodeTermsError
        this.verificationRequired = e instanceof HttpError && e.statusCode === -2
      }
    } finally {
      if (version === this.generation && scope === this.source.scope(this.feature)) {
        this.readPending = false; this.navigationLoading = false
        if (!this.active && !this.mainTab && this.feature !== 'life_code') this.needsRead = true
      }
      if (this.current(version, scope) || (this.feature === 'life_code' &&
        version === this.generation && scope === this.source.scope(this.feature))) {
        this.loading = false; this.refreshing = false; this.navigationLoading = false; this.readPending = false
        this.applyCatalogUpdate()
      }
    }
  }
  private async verify(): Promise<void> {
    if (!this.active || this.verifying || this.feature === 'sports') return
    if (!this.canVerify()) { router.pushUrl({ url: 'pages/LoginPage' }); return }
    const scope: string = this.source.scope(this.feature)
    const version: number = this.generation
    const service: string = this.feature === 'evaluation' ? ForumRoute.LOGIN_URL :
      this.feature === 'life_code' ? CampusService.LIFE_CODE : CampusService.MY_FUDAN
    this.verifying = true
    try {
      await this.verifyService(service)
      if (scope === this.source.scope(this.feature) && version === this.generation) {
        this.verifying = false; this.verificationRequired = false; this.error = ''; this.termsRequired = false
        this.needsRead = true
        if (this.active) { this.needsRead = false; await this.reload(true) }
      }
    } catch (e) {
      if (scope === this.source.scope(this.feature) && version === this.generation) this.error = ErrorDiagnostics.message(e as Object)
    } finally { this.verifying = false }
  }
  private manualReload(): void {
    if (this.verificationRequired) this.verify()
    else this.reload(true)
  }
  private async brighten(version: number, scope: string): Promise<void> {
    const lease = ++this.brightnessRevision
    const task = this.brightnessQueue.catch(() => {}).then(async () => {
      if (lease !== this.brightnessRevision || !this.current(version, scope)) return
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const host = await window.getLastWindow(context)
      if (lease !== this.brightnessRevision || !this.current(version, scope) || !this.snapshot.code.value) return
      this.previousBrightness = host.getWindowProperties().brightness
      this.brightWindow = host
      await host.setWindowBrightness(1)
      // Hide/refresh enqueues the restoration behind this exact lease. Never
      // restore a newer window lease from an older asynchronous completion.
    })
    this.brightnessQueue = task.catch(() => {})
    await this.brightnessQueue
  }
  private restoreBrightness(): void {
    this.brightnessRevision++
    const task = this.brightnessQueue.catch(() => {}).then(async () => {
      const host = this.brightWindow; const previous = this.previousBrightness
      this.brightWindow = null; this.previousBrightness = -1
      if (host !== null) await host.setWindowBrightness(previous)
    })
    this.brightnessQueue = task.catch(() => {})
  }
  private search(): void {
    const keyword: string = this.query.trim()
    if (keyword === this.searchKeyword && this.group === null && this.loaded && !this.error) return
    this.changeContent(() => {
      this.searchKeyword = keyword; this.group = null; this.teacher = ''; this.term = ''
      this.groups = []; this.randomReview = null; this.recommendations = []; this.reviewVotes.clear(); this.page = 1; this.more = false
      this.navigationLoading = true; this.reload(false)
    }, 0)
  }
  private async nextPage(): Promise<void> {
    if (!this.active || this.feature !== 'evaluation' || this.loadingMore || this.loading || this.readPending ||
      this.navigationLoading || !this.more || this.group !== null) return
    const version = this.generation; const scope = this.source.scope(this.feature); const page = this.page + 1
    this.loadingMore = true
    this.moreError = ''
    try {
      const result = await this.source.search(this.searchKeyword, page)
      if (!this.current(version, scope)) return
      for (const row of result.items) if (!row.summary.ready && !row.summary.error) row.summary = CourseReviewSummary.from(row)
      const ids = new Set<number>(this.groups.map(group => group.id))
      // iOS preserves the search endpoint's order. Deduplicate overlapping
      // pages without sorting or replacing already visible card objects.
      this.groups = this.groups.concat(result.items.filter(group => {
        if (ids.has(group.id)) return false
        ids.add(group.id); return true
      }))
      this.page = page; this.more = result.items.length >= result.pageSize
    } catch (e) { if (this.current(version, scope)) this.moreError = ErrorDiagnostics.message(e as Object) }
    finally {
      // A pagination response completed while this route was hidden is not
      // displayed. Release its own busy state and re-read on route return.
      if (version === this.generation) {
        this.loadingMore = false
        if (!this.current(version, scope)) this.needsRead = true
        this.applyCatalogUpdate()
      }
    }
  }
  private openGroup(id: number): void {
    if (!Number.isSafeInteger(id) || id <= 0) return
    this.liveSearch.cancel()
    this.listReturnOffset = this.scroller.currentOffset().yOffset
    this.summaryLoader.pause()
    this.changeContent(() => {
      const pending = new CourseReviewGroup(); pending.id = id
      this.group = pending; this.teacher = ''; this.term = ''
      this.navigationLoading = true; this.reload(false)
    }, 0)
  }
  private filterReviews(teacher: string, term: string): void {
    const offset: number = this.scroller.currentOffset().yOffset
    this.changeContent(() => { this.teacher = teacher; this.term = term }, offset)
  }
  private back(): void {
    if (this.group !== null) this.changeContent(() => {
      // Returning reveals the retained list, not another random/search request.
      this.generation++; this.group = null; this.teacher = ''; this.term = ''
      this.loading = false; this.loadingMore = false; this.navigationLoading = false; this.readPending = false; this.error = ''
      this.loadSummaries()
      this.applyCatalogUpdate()
    }, this.listReturnOffset)
    else if (!this.mainTab) router.back()
  }
  onBackPress(): boolean {
    if (this.group === null) return false
    this.back(); return true
  }
  private changeContent(commit: () => void, offset: number): void {
    this.revealRevision++
    const revision: number = ++this.contentRevision
    this.getUIContext().animateTo({ duration: 100, curve: Curve.EaseOut, onFinish: () => {
      if (!this.active || revision !== this.contentRevision) return
      commit()
      setTimeout(() => {
        if (!this.active || revision !== this.contentRevision) return
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false })
        this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.contentOpacity = 1 })
      }, 16)
    } }, () => { this.contentOpacity = 0 })
  }
  private revealLoaded(commit: () => void, version: number, scope: string): Promise<void> {
    if (this.mainTab && !this.active) {
      if (this.current(version, scope)) commit()
      return Promise.resolve()
    }
    // Swap data only after fading the old body; layout changes stay outside animation.
    const revision: number = ++this.revealRevision
    const navigation: number = this.contentRevision
    return new Promise<void>((resolve: () => void) => {
      this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut, onFinish: () => {
        if (this.mainTab && !this.active && this.current(version, scope)) { commit(); resolve(); return }
        if (revision !== this.revealRevision || (!this.mainTab && navigation !== this.contentRevision) || !this.current(version, scope)) {
          if (revision === this.revealRevision && navigation === this.contentRevision) this.contentOpacity = 1
          resolve(); return
        }
        commit()
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.contentOpacity = 1 })
        resolve()
      } }, () => { this.contentOpacity = 0 })
    })
  }
  private openEditor(review: CourseReview | null = null): void {
    if (this.group === null || this.group.courses.length === 0 || this.sending) return
    if (review !== null && (!review.isMe || review.deleted)) return
    const draft = new CourseReviewDraft()
    draft.courseId = review?.courseId ?? 0
    if (review !== null) {
      draft.title = review.title; draft.content = review.content
      draft.rank.overall = review.rank.overall; draft.rank.content = review.rank.content
      draft.rank.workload = review.rank.workload; draft.rank.assessment = review.rank.assessment
    }
    this.editorTransition.open(() => {
      if (this.active && !this.sending) { this.editing = review; this.draft = draft; this.editor = true }
    }, () => this.getUIContext())
  }
  private setRating(index: number, value: number): void {
    const next = this.copyDraft()
    if (index === 0) next.rank.overall = value
    else if (index === 1) next.rank.content = value
    else if (index === 2) next.rank.workload = value
    else next.rank.assessment = value
    this.draft = next
  }
  private copyDraft(): CourseReviewDraft {
    const next = new CourseReviewDraft(); next.courseId = this.draft.courseId; next.title = this.draft.title; next.content = this.draft.content
    next.rank.overall = this.draft.rank.overall; next.rank.content = this.draft.rank.content
    next.rank.workload = this.draft.rank.workload; next.rank.assessment = this.draft.rank.assessment; return next
  }
  private draftCourse(id: number): void { const next = this.copyDraft(); next.courseId = id; this.draft = next }
  private draftTitle(value: string): void { const next = this.copyDraft(); next.title = value; this.draft = next }
  private draftContent(value: string): void { const next = this.copyDraft(); next.content = value; this.draft = next }
  private prefetch(): void {
    if (this.contentHeight - this.scroller.currentOffset().yOffset - this.viewportHeight < 180) this.nextPage()
  }
  private async sendReview(): Promise<void> {
    if (this.sending || this.mutating || !this.draft.valid()) return
    const version = this.generation; const scope = this.source.scope(this.feature)
    const write = ++this.writeRevision
    this.sending = true
    try {
      if (this.editing !== null) await this.source.modify(this.editing, this.draft)
      else await this.source.add(this.draft)
      if (write !== this.writeRevision) return
      this.editor = false; this.draft = new CourseReviewDraft(); this.editing = null; this.needsRead = true
    } catch (e) { if (this.current(version, scope)) DiagnosticNavigation.feedback(this.getUIContext(), ErrorDiagnostics.message(e as Object)) }
    finally {
      if (write === this.writeRevision) {
        this.sending = false
        if (this.active && (this.needsRead || !this.current(version, scope))) this.reload()
      }
    }
  }
  private async removeReview(review: CourseReview): Promise<void> {
    if (this.mutating || this.sending || !review.isMe || review.deleted) return
    const version = this.generation; const scope = this.source.scope(this.feature)
    const write = ++this.writeRevision
    this.mutating = review.id
    try {
      const choice = await promptAction.showDialog({ title: this.text($r('app.string.utility_delete_review')),
      message: this.text($r('app.string.utility_delete_review_hint')), buttons: [
        { text: this.text($r('app.string.forum_cancel')), color: '#808080' },
        { text: this.text($r('app.string.utility_delete_review')), color: '#D43838' }] })
      if (choice.index !== 1 || !this.current(version, scope)) return
      await this.source.remove(review); if (write === this.writeRevision) this.needsRead = true
    }
    catch (e) { if (this.current(version, scope)) DiagnosticNavigation.feedback(this.getUIContext(), ErrorDiagnostics.message(e as Object)) }
    finally {
      if (write === this.writeRevision) {
        this.mutating = 0
        if (this.active && (this.needsRead || !this.current(version, scope))) this.reload()
      }
    }
  }
  private reviewVoteState(review: CourseReview): ReviewVoteState {
    let state = this.reviewVotes.get(review.id)
    if (state === undefined) { state = new ReviewVoteState(review); this.reviewVotes.set(review.id, state) }
    return state
  }
  private async vote(review: CourseReview, up: boolean): Promise<void> {
    const state = this.reviewVoteState(review)
    if (state.pending || this.sending || state.deleted) return
    const version = this.generation; const scope = this.source.scope(this.feature)
    const previousVotes = state.votes; const previousVote = state.myVote
    // Match ReviewVoteWidget: clicking the opposite arrow first cancels the
    // existing vote; the PATCH direction follows the existing vote then.
    const direction = previousVote === 0 ? up : previousVote > 0
    state.pending = true; state.myVote = previousVote === 0 ? (up ? 1 : -1) : 0
    state.votes = previousVotes + state.myVote - previousVote
    try {
      const changed = await this.source.vote(review.id, direction)
      if (!this.current(version, scope)) { this.needsRead = true; return }
      state.update(changed)
      // Keep body identity stable; metadata is needed by subsequent editing.
      review.votes = changed.votes; review.myVote = changed.myVote
    } catch (e) {
      if (this.current(version, scope)) {
        state.votes = previousVotes; state.myVote = previousVote
        DiagnosticNavigation.feedback(this.getUIContext(), ErrorDiagnostics.message(e as Object))
      }
    } finally {
      state.pending = false
      if (this.active && this.refreshAfterVote && !this.hasPendingVote()) { this.refreshAfterVote = false; this.reload(true) }
    }
  }
  private hasPendingVote(): boolean {
    for (const state of this.reviewVotes.values()) if (state.pending) return true
    return false
  }
  @Builder
  ReviewVotes(review: CourseReview) {
    ForEach([this.reviewVoteState(review)], (state: ReviewVoteState) => {
      ReviewVoteControls({ state: state, onVote: (up: boolean) => { this.vote(review, up) } })
    }, (_state: ReviewVoteState): string => String(review.id))
  }
  private copyGroup(source: CourseReviewGroup): CourseReviewGroup {
    const group = new CourseReviewGroup(); group.id = source.id; group.name = source.name; group.code = source.code
    group.department = source.department; group.credits = source.credits; group.weekHour = source.weekHour
    group.courseCount = source.courseCount; group.reviewCount = source.reviewCount; group.courses = source.courses.slice(); return group
  }
  private termTitle(value: string): string {
    const match = /^(\d+–\d+)\/(\d+)$/.exec(value)
    if (match === null) return value
    const titles: Resource[] = [$r('app.string.utility_term_unknown'), $r('app.string.utility_term_autumn'),
      $r('app.string.utility_term_winter'), $r('app.string.utility_term_spring'), $r('app.string.utility_term_summer')]
    return match[1] + ' ' + this.text(titles[Number(match[2])] ?? titles[0])
  }
  private ratingWord(index: number, value: number): string {
    const resources: Resource[] = [$r('app.string.utility_rating_overall_words'), $r('app.string.utility_rating_content_words'),
      $r('app.string.utility_rating_workload_words'), $r('app.string.utility_rating_assessment_words')]
    return Number.isInteger(value) && value >= 1 && value <= 5
      ? this.text(resources[index]).split(';')[value - 1] ?? this.text($r('app.string.utility_not_provided'))
      : this.text($r('app.string.utility_rating_unset'))
  }
  private courseDescription(course: ReviewCourse): string { return [course.teacher, this.termTitle(course.term)].filter(value => value.length > 0).join(' · ') }
  private choices(values: string[], terms: boolean = false): SelectOption[] {
    const options: SelectOption[] = [{ value: this.text($r('app.string.utility_all')) }]
    for (const value of values) options.push({ value: terms ? this.termTitle(value) : value })
    return options
  }
  private editorChoices(): SelectOption[] {
    const options: SelectOption[] = []
    for (const course of this.group?.courses ?? []) options.push({ value: this.courseDescription(course) || String(course.id) })
    return options
  }
  private async official(): Promise<void> {
    const url = this.feature === 'sports' ? CampusUtilityRepository.SPORTS_RULES_URL : this.feature === 'life_code' ? CampusUtilityRepository.LIFE_CODE_URL : 'https://my.fudan.edu.cn/'
    if (this.feature === 'life_code') { this.restoreBrightness(); this.snapshot = new CampusUtilitySnapshot() }
    try { await BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, url) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, this.text($r('app.string.utility_browser_failed'))) }
  }
  private async sportsGuide(): Promise<void> {
    try { await BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, CampusUtilityRepository.SPORTS_GUIDE_URL) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, this.text($r('app.string.utility_browser_failed'))) }
  }
  @Builder
  LabeledValue(title: Resource, value: () => string, highlighted: boolean = false, tone: string = '') {
    Column({ space: 5 }) {
      Text(this.text(title)).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
      Text(value() || this.text($r('app.string.utility_not_provided'))).fontSize(highlighted ? 24 : 15)
        .fontWeight(highlighted ? FontWeight.Bold : FontWeight.Medium).lineHeight(highlighted ? 32 : 23)
        .fontColor(CampusContentStyle.signalColor(tone, highlighted ? CampusContentStyle.accent : ThemeColors.textPrimary)).width('100%')
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
  @Builder
  EmptyNote(message: () => string) {
    Text(message()).fontSize(14).lineHeight(22).fontColor(ThemeColors.textSecondary)
      .width('100%').padding(ThemeDimens.cardInset).borderRadius(24).backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
  }
  @Builder
  AccessCard(card: CampusAccessCard) {
    Column({ space: 14 }) {
      this.LabeledValue($r('app.string.utility_access_permission'), () => card.permission, true, CampusSignal.permission(card.permission))
      Row({ space: 12 }) {
        Column() { this.LabeledValue($r('app.string.utility_card_status'), () => card.status) }.layoutWeight(1)
        Column() { this.LabeledValue($r('app.string.utility_access_expiry'), () => card.expireDate) }.layoutWeight(1)
      }.width('100%')
      Text([card.name, card.id].filter(value => value.length > 0).join(' · ')).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
    }.width('100%').padding(ThemeDimens.cardInset).alignItems(HorizontalAlign.Start).borderRadius(24)
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
  }
  @Builder
  SportsCategory(index: number, title: Resource) {
    Column({ space: 5 }) {
      Text(this.snapshot.sports.category(index) === undefined ? '—' : String(this.snapshot.sports.category(index)))
        .fontSize(32).fontWeight(FontWeight.Bold).fontColor(index === 0 ? CampusContentStyle.accent : index === 1 ? CampusContentStyle.attention : CampusContentStyle.available)
      Text(this.text(title)).fontSize(13).fontColor(ThemeColors.textSecondary)
    }.layoutWeight(1).padding({ top: 18, bottom: 18 }).borderRadius(20).backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
  }
  @Builder
  SportsItem(item: ExerciseItem) {
    Row({ space: 12 }) {
      Text(item.title).fontSize(15).fontColor(ThemeColors.textPrimary).layoutWeight(1)
      Text(item.times === undefined ? '—' : String(item.times)).fontSize(22).fontWeight(FontWeight.Bold).fontColor(CampusContentStyle.accent)
    }.width('100%').padding({ top: 11, bottom: 11 })
  }
  @Builder
  SportsRecord(record: ExerciseRecord) {
    Column({ space: 8 }) {
      Text(record.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      Row({ space: 14 }) {
        Column() { this.LabeledValue($r('app.string.utility_result'), () => record.result, true) }.layoutWeight(1)
        Column() { this.LabeledValue($r('app.string.utility_score'), () => record.score, true) }.layoutWeight(1)
      }.width('100%')
      if (record.comment) Text(record.comment).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary)
    }.width('100%').padding(20).borderRadius(24).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
  }
  @Builder
  UtilityContent() {
    if (this.feature === 'campus_access') {
      ForEach(this.snapshot.access, (card: CampusAccessCard) => { this.AccessCard(card) }, (card: CampusAccessCard): string => card.id)
      if (!this.loading && !this.error && this.snapshot.access.length === 0) this.EmptyNote(() => this.text($r('app.string.utility_no_access')))
      this.EmptyNote(() => this.text($r('app.string.utility_access_hint')))
    } else if (this.feature === 'sports') {
      if (this.snapshot.sports.updatedAt > 0) {
        Row({ space: 10 }) {
          this.SportsCategory(0, $r('app.string.utility_sports_morning'))
          this.SportsCategory(1, $r('app.string.utility_sports_required'))
          this.SportsCategory(2, $r('app.string.utility_sports_optional'))
        }.width('100%')
        Column() { ForEach(this.snapshot.sports.items, (item: ExerciseItem) => { this.SportsItem(item) }, (item: ExerciseItem): string => item.title) }
          .width('100%').padding({ left: 20, right: 20, top: 6, bottom: 6 }).borderRadius(24)
          .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
        ForEach(this.snapshot.sports.records, (record: ExerciseRecord) => { this.SportsRecord(record) }, (record: ExerciseRecord, index: number): string => String(index) + record.title)
      }
      this.EmptyNote(() => this.text($r('app.string.utility_sports_migrated_hint')))
      if (this.snapshot.sports.updatedAt > 0) this.EmptyNote(() => this.text($r('app.string.utility_sports_hint')))
      FloatingActionButton({ label: $r('app.string.utility_sports_guide'), controlHeight: 44, onAction: () => { this.sportsGuide() } }).width(190).align(Alignment.Center)
    } else {
      if (this.snapshot.code.value) {
        Column({ space: 18 }) {
          Text(this.text($r('app.string.utility_life_code'))).fontSize(22).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          QRCode(this.snapshot.code.value).width(232).height(232).color(Color.Black).backgroundColor(Color.White).padding(12)
          Text(this.text($r('app.string.utility_code_fetched'), new Date(this.snapshot.code.updatedAt).toLocaleTimeString()))
            .fontSize(12).fontColor(ThemeColors.textSecondary)
        }.width('100%').padding({ top: 26, bottom: 26, left: 16, right: 16 }).borderRadius(28)
          .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      }
      this.EmptyNote(() => this.text($r('app.string.utility_code_hint')))
    }
    if (!this.sheetMode) FloatingActionButton({ label: $r('app.string.utility_open_official'), controlHeight: 44, onAction: () => { this.official() } }).width(170).align(Alignment.Center)
  }
  @Builder
  ReviewTag(value: string, color: ResourceColor) {
    Text(value).fontSize(12).lineHeight(18).fontColor(color).padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor($r('app.color.input_surface')).borderRadius(8)
      .margin({ right: 6, bottom: 6 })
  }
  @Builder
  CourseMetadata(department: string, code: string, credits: number[]) {
    if (department || code || credits.length > 0) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center, alignContent: FlexAlign.Start }) {
        if (department) Text(department).fontSize(12).fontColor(ThemeColors.textSecondary)
          .constraintSize({ maxWidth: '100%' }).flexShrink(0).margin({ right: 8 })
        if (code) Text((department ? '·  ' : '') + code).fontSize(12).fontColor(ThemeColors.textSecondary)
          .constraintSize({ maxWidth: '100%' }).flexShrink(0).margin({ right: 8 })
        if (credits.length > 0) {
          Row() {
            Text(this.text($r('app.string.utility_credits'), credits.map((credit: number): string => credit.toFixed(1)).join(' / ')))
              .fontSize(12).fontColor($r('app.color.review_level_2'))
              .constraintSize({ maxWidth: '100%' })
          }.padding({ left: 8, right: 8, top: 4, bottom: 4 }).constraintSize({ minHeight: 24, maxWidth: '100%' })
            .alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center).flexShrink(0)
            .backgroundColor($r('app.color.input_surface')).borderRadius(8).id('course-credit-tag')
        }
      }.width('100%').constraintSize({ minHeight: 24 })
    }
  }
  @Builder
  ReviewAchievement(value: string) {
    Text(value).fontSize(12).lineHeight(18).fontColor($r('app.color.review_badge_text'))
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .linearGradient({ angle: 135, colors: [[$r('app.color.review_badge_blue'), 0], [$r('app.color.review_badge_purple'), 1]] })
      .borderRadius(6).constraintSize({ maxWidth: '100%' })
      .margin({ right: 6, bottom: 6 })
  }
  @Builder
  RatingValue(title: Resource, index: number, value: number) {
    Row({ space: 6 }) {
      Text(this.text(title)).fontColor(ThemeColors.textSecondary).fontSize(12).lineHeight(19)
      Text(this.ratingWord(index, value)).fontColor(ReviewPresentation.ratingColor(value)).fontSize(13).fontWeight(FontWeight.Medium).lineHeight(19)
    }.margin({ right: 16, bottom: 6 })
  }
  @Builder
  ReviewRatingDisplay(rank: () => ReviewRating) {
    Flex({ wrap: FlexWrap.Wrap }) {
      this.RatingValue($r('app.string.utility_rating_overall'), 0, rank().overall)
      this.RatingValue($r('app.string.utility_rating_content'), 1, rank().content)
      this.RatingValue($r('app.string.utility_rating_workload'), 2, rank().workload)
      this.RatingValue($r('app.string.utility_rating_assessment'), 3, rank().assessment)
    }.width('100%')
  }
  @Builder
  ReviewCard(review: CourseReview) {
    Column({ space: 10 }) {
      if (this.group === null) {
        this.CourseMetadata(review.department, review.courseCode, review.credit !== undefined ? [review.credit] : [])
        Text(review.courseName)
          .fontSize(19).lineHeight(27).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
      } else {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Row({ space: 7 }) {
            Rect().width(3).height(16).fill(ThemeColors.primary).borderRadius(2)
            Text(this.text($r('app.string.utility_reviewer'), review.reviewerId)).fontSize(19).lineHeight(27).fontWeight(FontWeight.Bold).fontColor(ThemeColors.primary)
          }.margin({ right: 8, bottom: 6 })
          ForEach(review.achievements, (name: string) => { this.ReviewAchievement(name) }, (name: string): string => name)
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          if (review.teacher) this.ReviewTag(review.teacher, $r('app.color.campus_text_violet'))
          if (review.term) this.ReviewTag(this.termTitle(review.term), $r('app.color.review_level_5'))
          if (review.campus) this.ReviewTag(review.campus, ThemeColors.info)
          if (review.credit !== undefined) this.ReviewTag(this.text($r('app.string.utility_credits'), review.credit.toFixed(1)), $r('app.color.review_level_2'))
        }.width('100%')
        if (review.title) Text(review.title).fontSize(17).lineHeight(25).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
      }
      Divider().strokeWidth(0.6).color($r('app.color.surface_outline'))
      if (review.deleted) {
        this.EmptyNote(() => this.text($r('app.string.utility_review_deleted')))
      } else {
        ForumContentView({ content: review.content, textSize: 15, preview: this.group === null }).width('100%')
        if (this.group !== null) {
          Divider().strokeWidth(0.6).color($r('app.color.surface_outline'))
          this.ReviewRatingDisplay(() => review.rank)
          Text(review.updated || review.created).fontSize(11).lineHeight(17).fontColor(ThemeColors.textSecondary)
        }
      }
      Row({ space: 12 }) {
        this.ReviewVotes(review)
        Blank()
        if (this.group === null && review.groupId > 0) {
          FloatingActionButton({ label: $r('app.string.utility_view_course'), controlHeight: 36, onAction: () => { this.openGroup(review.groupId) } }).width(100)
        } else if (review.isMe && !review.deleted) {
          Button(this.text($r('app.string.utility_edit_review'))).fontSize(13).fontColor(CampusContentStyle.accent).backgroundColor(Color.Transparent).stateEffect(false).onClick(() => { this.openEditor(review) })
          Button(this.text($r('app.string.utility_delete_review'))).fontSize(13).fontColor(CampusContentStyle.attention).backgroundColor(Color.Transparent).stateEffect(false).onClick(() => { this.removeReview(review) })
        }
      }.width('100%').alignItems(VerticalAlign.Center)
    }.width('100%').padding(20).borderRadius(24).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
  }
  @Builder
  GroupCard(group: CourseReviewGroup) {
    Column({ space: 10 }) {
      Text(group.name).fontSize(20).lineHeight(28).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      this.CourseMetadata(group.department, group.code, this.group === null ? group.creditValues() : [])
      if (this.group !== null && (group.campuses().length > 0 || group.creditValues().length > 0)) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          ForEach(group.campuses(), (campus: string) => { this.ReviewTag(campus, ThemeColors.info) }, (campus: string): string => campus)
          if (group.creditValues().length > 0) {
            this.ReviewTag(this.text($r('app.string.utility_credits'), group.creditValues().map((credit: number): string => credit.toFixed(1)).join(' / ')), $r('app.color.review_level_2'))
          }
        }.width('100%')
      }
      Divider().strokeWidth(0.6).color($r('app.color.surface_outline'))
      CourseReviewSummaryView({ state: this.summaryState(group), courseId: group.id })
    }.width('100%').padding(18).borderRadius(24).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      .onClick(() => { if (this.group === null) this.openGroup(group.id) })
  }
  @Builder
  EvaluationContent() {
      Row({ space: 10 }) {
        TextInput({ text: this.query, placeholder: this.text($r('app.string.utility_search_hint')) }).layoutWeight(1).height(46)
          .defaultFocus(false).enableKeyboardOnFocus(false)
          .focusable(!this.mainTab || (this.activeTab === 3 && this.mainVisible && this.foreground)).focusOnTouch(true)
          .fontSize(14).fontColor(ThemeColors.textPrimary).backgroundColor(Color.Transparent).cancelButton({ style: CancelButtonStyle.INVISIBLE })
          .id('course-search-input').onChange((value: string) => { if (value === this.query) return; this.query = value; this.liveSearch.update(value) }).onSubmit(() => { this.liveSearch.flush() })
        if (this.query.length > 0) SearchClearButton({ controlId: 'course-search-clear', onClear: () => { this.query = ''; this.liveSearch.update('') } })
      }.width('100%').padding({ left: 6, right: 8 }).borderRadius(24).backgroundColor($r('app.color.campus_search_surface'))
  }
  @Builder
  EvaluationFeedList() {
    List({ space: 14, scroller: this.scroller }) {
      ListItem() {
        Column({ space: 14 }) {
          this.EvaluationContent()
          this.ErrorContent()
          if (this.loaded && !this.loading && !this.error && this.groups.length === 0) this.EmptyNote(() => this.text($r('app.string.utility_no_courses')))
        }.width('100%').padding({ top: this.contentInset() })
      }
      LazyForEach(this.courseGroups, (group: CourseReviewGroup) => {
        ListItem() { this.GroupCard(group) }.id('course-feed-' + group.id)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      }, (group: CourseReviewGroup): string => [String(group.id), group.name, group.department, group.code,
        group.credits.join(',')].join('\u0000'))
      ListItem() {
        Column({ space: 12 }) {
          if (this.loadingMore) LoadingProgress().width(24).height(24).color(ThemeColors.primary)
          if (this.moreError) {
            ErrorNotice({ message: this.moreError, controlId: 'campusutilitypage-diagnostics', textSize: 13, textColor: ThemeColors.textSecondary }).width('100%')
            FloatingActionButton({ label: $r('app.string.ui_reload'), controlHeight: 42, onAction: () => { this.nextPage() } }).width(130)
          }
        }.width('100%')
      }
    }.width('100%').height('100%').id('course-feed-list').focusable(true).defaultFocus(!this.mainTab || this.activeTab === 3)
      .cachedCount(2).scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) })
      .contentEndOffset(this.listBottomInset())
      .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .opacity(this.contentOpacity * ((this.readPending || this.navigationLoading) && !this.refreshing ? 0.45 : 1))
      .animation({ duration: 220, curve: Curve.EaseOut })
      .onScrollIndex((first: number, last: number) => {
        const start: number = Math.max(0, first - 1); const end: number = Math.max(start, last - 1)
        if (start !== this.summaryFirst || end !== this.summaryLast) {
          this.summaryFirst = start; this.summaryLast = end; this.loadSummaries()
        }
        if (!this.moreError && last >= this.courseGroups.totalCount() - 6) this.nextPage()
      })
      .onReachEnd(() => { if (!this.moreError) this.nextPage() })
      .onScrollStart(() => { this.catalogScrolling = true; this.summaryLoader.setScrolling(true) })
      .onScrollStop(() => {
        this.catalogScrolling = false; this.summaryLoader.setScrolling(false)
        this.loadSummaries(); this.applyCatalogUpdate()
      })
  }
  @Builder
  EvaluationHelp() {
    FloatingActionButton({ label: $r('app.string.utility_evaluation_hint'), icon: 'about',
      iconResource: $r('sys.symbol.info_circle'), controlHeight: 48, controlId: 'course-feed-help',
      onAction: () => {
        promptAction.showDialog({ message: this.text($r('app.string.utility_evaluation_hint')) })
      } }).width(48)
  }
  @Builder
  EvaluationDetailHeader() {
    if (this.group !== null && this.group.name) {
      this.GroupCard(this.group)
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(this.text($r('app.string.utility_teacher'))).fontSize(12).fontColor(ThemeColors.textSecondary)
          Select(this.choices(this.group.teachers())).value(this.teacher || this.text($r('app.string.utility_all')))
            .fontColor(ThemeColors.textPrimary).font({ size: 13 }).optionFont({ size: 14 })
            .onSelect((index: number) => { this.filterReviews(index > 0 ? this.group?.teachers()[index - 1] ?? '' : '', this.term) })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 4 }) {
          Text(this.text($r('app.string.utility_term'))).fontSize(12).fontColor(ThemeColors.textSecondary)
          Select(this.choices(this.group.terms(), true)).value(this.term ? this.termTitle(this.term) : this.text($r('app.string.utility_all')))
            .fontColor(ThemeColors.textPrimary).font({ size: 13 }).optionFont({ size: 14 })
            .onSelect((index: number) => { this.filterReviews(this.teacher, index > 0 ? this.group?.terms()[index - 1] ?? '' : '') })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(16).borderRadius(24).backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))

    }
  }
  @Builder
  RatingEditor(title: Resource, index: number, value: () => number) {
    Column({ space: 3 }) {
      Row({ space: 12 }) {
        Text(this.text(title)).fontSize(14).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        Rating({ rating: value(), indicator: false }).stars(5).stepSize(1).width(148).height(30)
          .starStyle({ backgroundUri: this.dark ? $r('app.media.review_rating_empty_dark') : $r('app.media.review_rating_empty_light'),
            foregroundUri: this.dark ? $r('app.media.review_rating_full_dark') : $r('app.media.review_rating_full_light'),
            secondaryUri: this.dark ? $r('app.media.review_rating_full_dark') : $r('app.media.review_rating_full_light') })
          .onChange((rating: number) => { this.setRating(index, rating) })
      }.width('100%')
      Text(this.ratingWord(index, value())).fontSize(12).lineHeight(18).fontColor(ReviewPresentation.ratingColor(value())).width('100%').textAlign(TextAlign.End)
    }.width('100%')
  }
  @Builder
  EditorContent() {
    Scroll() {
      Column({ space: 14 }) {
        Text(this.text($r('app.string.utility_evaluation_editor_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary)
        Column({ space: 5 }) {
          Text(this.text($r('app.string.utility_course_offering'))).fontSize(12).fontColor(ThemeColors.textSecondary)
          Select(this.editorChoices()).value(this.draft.courseId > 0 ? this.courseDescription(this.group?.courses.find(course => course.id === this.draft.courseId) ?? new ReviewCourse()) : this.text($r('app.string.utility_select_course')))
            .font({ size: 14 }).fontColor(ThemeColors.textPrimary).enabled(this.editing === null)
            .onSelect((index: number) => { this.draftCourse(this.group?.courses[index]?.id ?? 0) })
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) {
          Text(this.text($r('app.string.utility_review_title'))).fontSize(12).fontColor(ThemeColors.textSecondary)
          TextInput({ text: this.draft.title, placeholder: this.text($r('app.string.utility_review_title_hint')) }).maxLength(200).fontSize(15).fontColor(ThemeColors.textPrimary)
            .backgroundColor($r('app.color.input_surface')).onChange((value: string) => { this.draftTitle(value) })
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) {
          Text(this.text($r('app.string.utility_review_body'))).fontSize(12).fontColor(ThemeColors.textSecondary)
          TextArea({ text: this.draft.content, placeholder: this.text($r('app.string.utility_review_body_hint')) }).height(130).fontSize(15).fontColor(ThemeColors.textPrimary)
            .backgroundColor($r('app.color.input_surface')).onChange((value: string) => { this.draftContent(value) })
        }.width('100%').alignItems(HorizontalAlign.Start)
        this.RatingEditor($r('app.string.utility_rating_overall'), 0, () => this.draft.rank.overall)
        this.RatingEditor($r('app.string.utility_rating_content'), 1, () => this.draft.rank.content)
        this.RatingEditor($r('app.string.utility_rating_workload'), 2, () => this.draft.rank.workload)
        this.RatingEditor($r('app.string.utility_rating_assessment'), 3, () => this.draft.rank.assessment)
        FloatingActionButton({ label: this.sending ? $r('app.string.utility_sending') : $r('app.string.utility_submit'), controlHeight: 44,
          actionEnabled: !this.sending && this.draft.valid(), onAction: () => { this.sendReview() } }).width('100%')
      }.width('100%').padding({ left: 22, right: 22, top: 10, bottom: Math.max(18, px2vp(this.bottomPx)) }).alignItems(HorizontalAlign.Start)
    }.width('100%').constraintSize({ maxHeight: 590 }).scrollBar(BarState.Off)
  }
  @Builder
  ReloadIcon() {
    FloatingActionButton({ label: $r('app.string.campus_card_refresh'), icon: 'refresh', zeroContentPadding: true,
      controlHeight: 48, actionEnabled: !this.loading && !this.refreshing,
      onAction: () => { this.manualReload() } }).width(48)
  }
  @Builder
  ErrorContent() {
            if (this.error) {
              Column({ space: 12 }) {
                ErrorNotice({ message: this.error, controlId: 'campusutilitypage-diagnostics', textSize: 14, textColor: ThemeColors.textSecondary }).width('100%')
                if (!this.verificationRequired) {
                  FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', onCard: true, zeroContentPadding: true, controlHeight: 48,
                    actionEnabled: !this.loading && !this.refreshing, onAction: () => { this.manualReload() } }).width(48)
                }
                if (this.verificationRequired && this.feature !== 'sports') {
                  FloatingActionButton({ label: $r('app.string.campus_verify_continue'), controlHeight: 42, actionEnabled: !this.verifying,
                    onAction: () => { this.verify() } }).width(160)
                }
                if (this.termsRequired) FloatingActionButton({ label: $r('app.string.utility_open_terms'), controlHeight: 42, onAction: () => { this.official() } }).width(180)
                if (this.feature === 'evaluation' && !ForumRepository.getInstance().isLoggedIn()) {
                  FloatingActionButton({ label: $r('app.string.utility_login_forum'), controlHeight: 42,
                    onAction: () => { router.pushUrl({ url: 'pages/ForumLoginPage' }).catch(() => {}) } }).width(140)
                }
              }.width('100%').padding(20).borderRadius(24).backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
            }
  }
  @Builder
  EvaluationDetailList() {
    // Only visible reviews own text/Web/image surfaces. A course may contain
    // hundreds of rich reviews; never render them all in a single Scroll layer.
    List({ space: 14, scroller: this.scroller }) {
      ListItem() {
        Column({ space: 14 }) {
          this.ErrorContent()
          this.EvaluationDetailHeader()
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: this.contentInset() })
      }
      LazyForEach(this.detailReviews, (review: CourseReview) => {
        ListItem() { this.ReviewCard(review) }
      }, (review: CourseReview): string => ReviewPresentation.rowKey(review))
      ListItem() {
        Column() {
          if (this.group !== null && this.group.name && this.detailReviews.totalCount() === 0) {
            this.EmptyNote(() => this.text($r('app.string.utility_no_reviews')))
          }
        }.width('100%')
      }
    }.width('100%').height('100%').cachedCount(1).scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) })
      .contentEndOffset(this.listBottomInset())
      .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .opacity(this.contentOpacity * ((this.readPending || this.navigationLoading) && !this.refreshing ? 0.45 : 1))
      .animation({ duration: 220, curve: Curve.EaseOut })
  }
  @Builder
  PageBody() {
        if (this.feature === 'evaluation' && this.group !== null) {
          this.EvaluationDetailList()
        } else if (this.feature === 'evaluation') {
          this.EvaluationFeedList()
        } else {
        Scroll(this.scroller) {
          Column({ space: 14 }) {
            this.ErrorContent()
            if (this.feature === 'evaluation') this.EvaluationContent()
            else this.UtilityContent()
          }.width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: this.contentInset(),
            bottom: Math.max(22, px2vp(this.bottomPx) + (this.mainTab ? 108 : 22)) })
            .onSizeChange((oldSize: SizeOptions, nextSize: SizeOptions) => { this.contentHeight = Number(nextSize.height) })
        }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) }).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .renderGroup(true).opacity(this.contentOpacity * ((this.readPending || this.navigationLoading) && !this.refreshing ? 0.45 : 1))
          .animation({ duration: 220, curve: Curve.EaseOut })
          .onReachEnd(() => { this.nextPage() })
          .onDidScroll(() => { this.prefetch() })
          .onSizeChange((oldSize: SizeOptions, nextSize: SizeOptions) => { this.viewportHeight = Number(nextSize.height) })
        }
  }
  @Builder
  PageContent() {
    Stack({ alignContent: Alignment.Top }) {
      this.PageBody()
      CenterLoadingProgress({ busy: (this.readPending || this.navigationLoading || (this.feature === 'evaluation' && !this.loaded && !this.error)) })
      TopFade({ extent: this.headerExtent(), trailingEdge: 16 })
      Row({ space: 12 }) {
        if (!this.mainTab || this.group !== null) {
          Row() { FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48,
            onAction: () => { this.back() } }).width(48) }.width(this.feature === 'evaluation' ? 100 : 48)
        }
        Text(this.group !== null ? this.text($r('app.string.utility_course_details')) : this.text(CampusUtilities.title(this.feature)))
          .fontSize(this.mainTab && this.group === null ? 28 : 20).lineHeight(36).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          .textAlign(this.mainTab && this.group === null ? TextAlign.Start : TextAlign.Center)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.feature === 'evaluation') {
          Row({ space: 4 }) {
            if (this.group === null) this.EvaluationHelp()
            else {
              FloatingActionButton({ label: $r('app.string.utility_write_review'), icon: 'edit', controlHeight: 48,
                controlId: 'course-write-review', actionEnabled: this.group.courses.length > 0,
                onAction: () => { this.openEditor() } }).width(48)
            }
            this.ReloadIcon()
          }.width(100).height(48).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.End)
        } else {
          FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 48,
            controlId: 'campus-detail-refresh', actionEnabled: !this.loading && !this.refreshing,
            onAction: () => { this.manualReload() } }).width(48)
        }
      }.width('100%').height(this.feature === 'evaluation' ? 48 : 56).padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
        .translate({ y: px2vp(this.topPx) + (this.feature === 'evaluation' ? 4 : 0) })
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgStart)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.editor, this.EditorContent, this.editorTransition.options(this.editor, { height: SheetSize.FIT_CONTENT, dragBar: true, showClose: true,
        title: { title: $r('app.string.utility_write_review') }, backgroundColor: ThemeColors.cardBg,
        onDisappear: () => { if (!this.sending) { this.draft = new CourseReviewDraft(); this.editing = null } } }))
  }
  @Builder
  AccessSheet() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text(this.text(CampusUtilities.title('campus_access'))).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).layoutWeight(1).id('campus-access-title')
        FloatingActionButton({ label: $r('app.string.utility_open_official'), icon: 'web', iconResource: $r('sys.symbol.link'), controlHeight: 40,
          controlId: 'campus-access-official', onAction: () => { this.official() } }).width(40)
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', controlHeight: 40,
          controlId: 'campus-access-refresh', actionEnabled: !this.loading && !this.readPending && !this.verifying,
          onAction: () => { this.manualReload() } }).width(40)
        FloatingActionButton({ label: $r('app.string.ui_close'), icon: 'close', iconResource: $r('sys.symbol.xmark'), controlHeight: 40,
          controlId: 'campus-access-close', onAction: () => { this.onSheetClose() } }).width(40)
      }.width('100%').alignItems(VerticalAlign.Center).padding({ left: ThemeDimens.cardInset, right: ThemeDimens.cardInset })
      Stack() {
        Scroll(this.scroller) {
          Column({ space: 14 }) { this.ErrorContent(); this.UtilityContent() }
            .width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, bottom: Math.max(20, px2vp(this.bottomPx)) })
            .alignItems(HorizontalAlign.Start)
        }.width('100%').constraintSize({ maxHeight: Math.max(180, Math.min(480, px2vp(display.getDefaultDisplaySync().height) * 0.65)) })
          .scrollBar(BarState.Auto).onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) })
          .opacity(this.contentOpacity).animation({ duration: 220, curve: Curve.EaseOut })
        CenterLoadingProgress({ busy: this.readPending }).width(36).height(36)
      }.width('100%')
    }.width('100%').padding({ top: 8 }).id('campus-access-sheet-content')
  }
  build() {
    if (this.sheetMode) { this.AccessSheet() }
    else { this.PageContent() }
  }
}
