import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice, DiagnosticLink } from '../components/ErrorNotice'
import { ForumSpecialTag } from '../components/ForumSpecialTag'
import { MoreGlyph } from '../components/MoreGlyph'
import { ForumLatestReply } from '../common/ForumLatestReply'
import { formatRelativeTime } from '../model/Forum'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { LiveSearch } from '../common/LiveSearch'
import { SearchClearButton } from '../components/SearchClearButton'
import { AppLanguage } from '../common/AppLanguage'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { FloatingSurface } from '../components/FloatingSurface'
import { TopFade } from '../components/TopFade'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
/**
 * Tree Hole feed (树洞首页).
 *
 * Backed by the real fduhole.com API: GET /holes/_homepage for the default feed,
 * GET /holes?division_id=… when a division chip is active, GET /floors/search for
 * keyword searches. Ported from lib/page/subpage_forum.dart
 */

import { router, promptAction, SymbolGlyphModifier } from '@kit.ArkUI'
import { ForumRepository } from '../repository/ForumRepository'
import { FduRepository } from '../repository/FduRepository'
import { HttpError } from '../util/HttpUtil'
import { ForumRoute } from '../common/ForumRoute'
import { ForumHole, ForumFloor, ForumDivision, ForumTag } from '../model/Forum'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { getSymbolIcon } from '../common/DanXiIcons'
import { HoleRouteParams, EditorRouteParams } from '../common/RouteParams'
import { Constant } from '../common/Constant'
import { ForumPresentation } from '../common/ForumPresentation'
import { ForumFeed } from '../model/ForumFeed'
import { ForumContentView } from '../components/ForumContentView'
import { ForumPreviewCard } from '../components/ForumPreviewCard'
import { ForumFloorFeed, shouldPrefetch } from '../model/ForumPaging'
import { ForumListSource } from '../common/ForumListSource'
import { ForumPageRepository } from '../common/ForumPageRepository'
import { ForumPreferences } from '../common/ForumPreferences'
import { ForumPreviewWork } from '../common/ForumPreviewWork'
import { ForumPreviewSequence } from '../common/ForumPreviewSequence'
import { ForumListRouteParams } from '../common/ForumListRoute'
import { ForumTagChip } from '../components/ForumTagChip'
import { common } from '@kit.AbilityKit'
import { BrowserLink } from '../common/BrowserLink'
import { AnnouncementConfig } from '../common/AnnouncementConfig'
import { ForumActivitySource, DefaultForumActivitySource } from '../common/ForumActivitySource'
import { AnnouncementBanner } from '../model/AnnouncementConfigData'
import { nativeFloatingBackground } from '../common/AdaptiveMaterial'

@Component
export struct ForumPage {
  private forumMenuTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private activitiesSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  touchScroller: Scroller = new Scroller()
  private previewWork: ForumPreviewWork = new ForumPreviewWork()
  private previewSequence: ForumPreviewSequence = new ForumPreviewSequence()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(ForumPreferences.SORT) @Watch('onFeedRefresh') sortOrder: string = 'time_updated'
  @StorageLink(ForumPreferences.BACKGROUND) backgroundSource: string = ''
  @StorageLink(ForumPreferences.ACTIVITIES) @Watch('onActivitiesPreferenceChanged') activitiesEnabled: boolean = true
  @StorageLink(AnnouncementConfig.KEY_REVISION) @Watch('onActivitiesChanged') activitiesRevision: number = 0
  @StorageLink(ForumRepository.KEY_SESSION_REVISION) @Watch('onLoginChanged') sessionRevision: number = 0
  @State activities: AnnouncementBanner[] = []
  @State activitiesSheet: boolean = false
  @State private forumMenuVisible: boolean = false
  @State private sortMenuVisible: boolean = false
  @State activitiesLoading: boolean = false
  @State activitiesError: string = ''
  @State activitiesCheckedAt: number = 0
  @State orderSaving: boolean = false
  @StorageLink(Constant.KEY_FORUM_FOLD_BEHAVIOR) @Watch('onFoldModeChanged') foldMode: string = 'fold'
  @State revealedHoles: number[] = []
  // ForumLoginPage flips this AppStorage flag; a bare router.back() would not
  // re-run aboutToAppear on a component that stays mounted inside Tabs.
  @StorageLink('forum_logged_in') @Watch('onLoginChanged') forumLoggedIn: boolean = false
  // Bumped by ForumEditorPage after a successful publish; ForumPage stays mounted
  // inside Tabs so returning from the editor never re-runs aboutToAppear.
  @StorageLink('forum_feed_refresh') @Watch('onFeedRefresh') feedRefresh: number = 0
  @State sessionActive: boolean = false
  @State holes: ForumHole[] = []
  @State searchResults: ForumFloor[] = []
  @State divisions: ForumDivision[] = []
  @State divisionsLoading: boolean = false
  @State divisionsError: string = ''
  @State divisionsNeedLogin: boolean = false
  @State isLoading: boolean = true
  @State private preparingFeed: boolean = false
  @State errorMessage: string = ''
  @State campusLoginRequired: boolean = false
  @State verificationRequired: boolean = false
  @State divisionsVerificationRequired: boolean = false
  @State verifying: boolean = false
  @State keyword: string = ''
  @State activeKeyword: string = ''
  @State private displayedKeyword: string = ''
  @State private contentOpacity: number = 1
  @State private contentShift: number = 0
  private contentMotionRevision: number = 0

  private contentMotionCurrent(revision: number, generation: number, scope: number): boolean {
    return revision === this.contentMotionRevision && generation === this.requestGeneration && this.isCurrentSession(scope)
  }

  private animateContent(revision: number, generation: number, scope: number): void {
    this.contentOpacity = 0; this.contentShift = 0
    // LazyForEach mounts its visible cards asynchronously. Let the data update
    // reach layout before revealing it; a 16 ms timer can run before that frame.
    this.getUIContext().postFrameCallback({ onFrame: () => {
      if (!this.contentMotionCurrent(revision, generation, scope)) return
      this.getUIContext().postFrameCallback({ onFrame: () => {
        if (!this.contentMotionCurrent(revision, generation, scope)) return
        this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
          this.contentOpacity = 1; this.contentShift = 0
        })
      }, onIdle: () => {} })
    }, onIdle: () => {} })
  }
  private presentContent(commit: () => void, generation: number, scope: number): void {
    const revision: number = ++this.contentMotionRevision
    const hasContent: boolean = this.holes.length > 0 || this.searchResults.length > 0
    this.getUIContext().animateTo({ duration: hasContent ? 100 : 0, curve: Curve.EaseOut, onFinish: () => {
      // A superseded response must never reveal a newer request's hidden cards.
      if (!this.contentMotionCurrent(revision, generation, scope)) return
      commit()
      this.animateContent(revision, generation, scope)
    } }, () => { this.contentOpacity = 0 })
  }

  @State selectedDivision: number = 0
  @State beforeDate: number = 0
  @State loadingMore: boolean = false
  @State hasMore: boolean = false
  @State refreshing: boolean = false
  @State private pullOffset: number = 0
  @State moreError: boolean = false
  @State moreDiagnosticError: string = ''

  private refreshFeed(forceDivisions: boolean = false): void {
    if (!this.active || !this.sessionActive) return
    if (!this.loadContent()) return
    this.loadDivisions(forceDivisions)
    this.repo.getMe().catch(() => {})
    this.loadActivities(true)
  }

  repo: ForumPageRepository = ForumRepository.getInstance()
  private async retryVerification(divisionsOnly: boolean = false): Promise<void> {
    if (this.verifying) return
    const required: boolean = divisionsOnly ? this.divisionsVerificationRequired :
      this.verificationRequired || this.divisionsVerificationRequired
    if (!required) { if (divisionsOnly) this.loadDivisions(true); else this.loadContent(); return }
    if (!FduRepository.getInstance().canLoginOnDemand()) { router.pushUrl({ url: 'pages/LoginPage' }); return }
    const scope: number = this.sessionScope
    this.verifying = true
    try {
      await FduRepository.getInstance().verifyService(ForumRoute.LOGIN_URL)
      if (!this.isCurrentSession(scope)) return
      this.verificationRequired = false; this.divisionsVerificationRequired = false
      this.refreshFeed(true)
    } catch (e) {
      if (this.isCurrentSession(scope)) {
        if (divisionsOnly) this.divisionsError = ForumRepository.describeError(e)
        else this.errorMessage = ForumRepository.describeError(e)
      }
    } finally { this.verifying = false }
  }
  activitySource: ForumActivitySource = new DefaultForumActivitySource()
  private feed: ForumFeed = new ForumFeed()
  private searchFeed: ForumFloorFeed = new ForumFloorFeed()
  private visibleEnd: number = -1
  private active: boolean = false
  private holeSource: ForumListSource<ForumHole> = new ForumListSource<ForumHole>()
  private searchSource: ForumListSource<ForumFloor> = new ForumListSource<ForumFloor>()
  private requestGeneration: number = 0
  private contentPendingKey: string = ''
  private contentPendingGeneration: number = -1
  private liveSearch: LiveSearch = new LiveSearch(() => { if (this.active) this.applySearch() })
  private bootstrapGeneration: number = 0
  private divisionsGeneration: number = 0
  private sessionScope: number = -1
  private bootstrapScope: number = -1
  private activitiesGeneration: number = 0
  private feedDirty: boolean = false

  onFoldModeChanged(): void {
    this.revealedHoles = []
    this.syncPreviewOrder(this.displayedKeyword.length > 0)
    this.holeSource.update(this.visibleFeedHoles())
    this.prefetch()
  }

  aboutToAppear(): void {
    this.active = true
    this.previewWork.setActive(true)
    this.onActivitiesChanged()
    this.loadActivities()
    this.bootstrap()
  }

  onActivitiesChanged(): void {
    const snapshot = this.activitySource.peek()
    this.activities = snapshot.banners.slice()
    this.activitiesLoading = snapshot.loading === true
    this.activitiesError = snapshot.error || ''
    this.activitiesCheckedAt = snapshot.checkedAt || 0
  }

  onActivitiesPreferenceChanged(): void {
    if (!this.activitiesEnabled) {
      this.activitiesGeneration++
      this.activitiesLoading = false
      this.activitiesSheet = false
      return
    }
    this.onActivitiesChanged()
    this.loadActivities()
  }

  private loadActivities(force: boolean = false): void {
    if (!this.active || !this.activitiesEnabled) return
    const generation: number = ++this.activitiesGeneration
    this.activitiesLoading = true
    this.activitiesError = ''
    this.activitySource.load(force).then(() => {
      if (!this.active || generation !== this.activitiesGeneration) return
      this.onActivitiesChanged()
      this.activitiesLoading = false
    }).catch((e: Object) => {
      if (!this.active || generation !== this.activitiesGeneration) return
      this.activitiesError = ErrorDiagnostics.message(e as Object)
      this.activitiesCheckedAt = Date.now()
      this.activitiesLoading = false
    })
  }

  private collection(section: string, tag: string = ''): void {
    if (!this.sessionActive) { router.pushUrl({ url: 'pages/ForumLoginPage' }); return }
    router.pushUrl({ url: 'pages/ForumAccountPage', params: new ForumListRouteParams(section, tag) })
      .catch((diagnosticFailure: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.ui_retry'))) })
  }

  private async changeOrder(value: string): Promise<void> {
    if (this.orderSaving || value === this.sortOrder) return
    this.orderSaving = true
    try { await ForumPreferences.write(ForumPreferences.SORT, value) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.profile_save_failed'))) }
    finally { this.orderSaving = false }
  }

  private async openActivity(item: AnnouncementBanner): Promise<void> {
    try {
      const action = ForumRepository.getInstance().resolveActivityAction(item.action)
      if (/^##[1-9]\d*$/.test(action)) {
        const floor = await ForumRepository.getInstance().getFloor(Number(action.substring(2)))
        if (this.active) router.pushUrl({ url: 'pages/ForumDetailPage', params: new HoleRouteParams(floor.holeId, floor.floorId) })
      } else if (/^#[1-9]\d*$/.test(action)) this.openHole(Number(action.substring(1)))
      else await BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, action)
      this.activitiesSheet = false
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e)) }
  }

  aboutToDisappear(): void {
    this.previewWork.setActive(false)
    this.forumMenuVisible = false
    this.sortMenuVisible = false
    this.liveSearch.cancel()
    this.contentMotionRevision++
    this.contentOpacity = 1; this.contentShift = 0
    this.active = false
    this.requestGeneration++
    this.bootstrapGeneration++
    this.divisionsGeneration++
    this.activitiesGeneration++
    // A hidden-page request is discarded by its generation guard. Release only
    // that pending footer, so returning can resume the same cursor and rows.
    this.loadingMore = false
  }

  onLoginChanged(propName: string): void {
    if (!this.active) return
    const scope: number = this.repo.sessionRevision()
    // Status and revision are published together; /users/me also republishes
    // status. Neither publication is a reason to reload the same feed.
    if (scope === this.sessionScope || scope === this.bootstrapScope) return
    this.bootstrap()
  }

  onFeedRefresh(propName: string): void {
    if (!this.active) { this.feedDirty = true; return }
    if (this.active && this.sessionActive) {
      this.loadContent()
    }
  }

  bootstrap(): void {
    if (!this.active) return
    this.bootstrapScope = this.repo.sessionRevision()
    if (this.sessionActive && this.sessionScope === this.bootstrapScope) {
      // Returning from another page must not remove the chips or reset the
      // selection. Repository freshness also avoids another metadata request.
      this.loadDivisions()
      // Preserve the native list and its inertia/position on tab re-entry.
      // Publishing/settings changes and interrupted reads still reload; an
      // ordinary return must not replace every row during the next gesture.
      if (this.feedDirty || this.isLoading) this.loadContent()
      else if (this.keyword.trim() !== this.activeKeyword) this.applySearch()
      else this.prefetch()
      return
    }
    const generation: number = ++this.bootstrapGeneration
    this.requestGeneration++
    this.divisionsGeneration++
    this.sessionActive = false
    this.divisions = this.repo.peekCachedDivisions()
    this.divisionsLoading = false
    this.divisionsError = ''
    this.divisionsNeedLogin = false
    this.divisionsVerificationRequired = false
    this.previewSequence.clear()
    this.holes = []
    this.searchResults = []
    this.holeSource.update([])
    this.searchSource.update([])
    this.selectedDivision = 0
    this.keyword = ''
    this.activeKeyword = ''; this.displayedKeyword = ''
    this.contentMotionRevision++
    this.contentOpacity = 1
    this.loadingMore = false
    this.hasMore = false
    this.refreshing = false
    this.revealedHoles = []
    this.isLoading = true
    this.errorMessage = ''
    this.repo.restoreSession().then((loggedIn: boolean) => {
      if (!this.active || generation !== this.bootstrapGeneration) return
      this.sessionActive = loggedIn
      this.sessionScope = this.repo.sessionRevision()
      if (!loggedIn) {
        this.holes = []
        this.searchResults = []
        this.isLoading = false
        return
      }
      // Restore only this account's metadata. Cold start checks for updated
      // divisions/pins once; subsequent reads share the repository cache.
      const cached: ForumDivision[] = this.repo.peekCachedDivisions()
      if (!this.divisionsMatch(cached)) this.divisions = cached
      if (this.divisions.length > 0) this.selectedDivision = this.divisions[0].divisionId
      this.syncPreviewOrder(false, true)
      this.loadDivisions()
      this.repo.getMe().catch(() => {})
      this.loadContent()
    }).catch((e: Object) => {
      if (!this.active || generation !== this.bootstrapGeneration) return
      this.errorMessage = ForumRepository.describeError(e)
      this.isLoading = false
    })
  }

  private divisionsMatch(data: ForumDivision[]): boolean {
    if (data.length !== this.divisions.length) return false
    for (let index: number = 0; index < data.length; index++) {
      const previous: ForumDivision = this.divisions[index]
      const current: ForumDivision = data[index]
      if (previous.divisionId !== current.divisionId || previous.name !== current.name ||
        previous.description !== current.description || previous.pinned.length !== current.pinned.length) return false
      for (let pin: number = 0; pin < current.pinned.length; pin++) {
        if (previous.pinned[pin] !== current.pinned[pin]) return false
      }
    }
    return true
  }

  private loadDivisions(force: boolean = false): void {
    if (!this.active || !this.sessionActive) return
    const generation: number = ++this.divisionsGeneration
    const scope: number = this.sessionScope
    this.divisionsLoading = this.divisions.length === 0
    this.divisionsError = ''
    this.divisionsNeedLogin = false
    this.divisionsVerificationRequired = false
    this.repo.getDivisions(force).then((data: ForumDivision[]) => {
      if (!this.isCurrentSession(scope) || generation !== this.divisionsGeneration) return
      if (!this.divisionsMatch(data)) {
        this.divisions = data
        this.syncPreviewOrder(this.displayedKeyword.length > 0)
        this.holeSource.update(this.visibleFeedHoles())
      }
      this.divisionsLoading = false
      if (data.length > 0 && !data.some((row: ForumDivision): boolean => row.divisionId === this.selectedDivision)) {
        this.selectedDivision = data[0].divisionId
        if (this.activeKeyword.length === 0) this.loadContent()
      }
    }).catch((e: Object) => {
      if (!this.isCurrentSession(scope) || generation !== this.divisionsGeneration) return
      // Keep cached tabs usable and offer an independent retry even when the
      // main feed succeeded. Previously this failure was only printed to logs.
      this.divisionsLoading = false
      this.divisionsError = ForumRepository.describeError(e)
      this.divisionsVerificationRequired = e instanceof HttpError && e.statusCode === -2
      this.divisionsNeedLogin = this.divisionsVerificationRequired && !FduRepository.getInstance().canLoginOnDemand()
    })
  }

  private isCurrentSession(scope: number): boolean {
    return this.active && this.sessionActive && scope === this.sessionScope && scope === this.repo.sessionRevision()
  }

  private loadContent(): boolean {
    if (!this.isCurrentSession(this.sessionScope)) return false
    const key: string = this.sessionScope + '/' + this.selectedDivision + '/' + encodeURIComponent(this.activeKeyword) +
      '/' + this.sortOrder + '/' + this.beforeDate
    if (this.contentPendingKey === key && this.contentPendingGeneration === this.requestGeneration) return false
    const generation: number = ++this.requestGeneration
    this.contentPendingKey = key; this.contentPendingGeneration = generation
    this.feedDirty = false
    const scope: number = this.sessionScope
    this.feed = new ForumFeed()
    if (this.beforeDate > 0) this.feed.cursor = this.beforeDate
    this.searchFeed = new ForumFloorFeed()
    this.visibleEnd = -1
    this.moreError = false
    this.hasMore = false
    this.loadingMore = false
    if (!this.refreshing) this.isLoading = true
    this.errorMessage = ''
    this.campusLoginRequired = false
    this.verificationRequired = false
    if (this.activeKeyword.length > 0) {
      this.repo.searchFloors(this.activeKeyword).then((floors: ForumFloor[]) => {
        if (!this.isCurrentSession(scope) || generation !== this.requestGeneration) return
        this.presentContent(() => {
        this.preparingFeed = this.holes.length + this.searchResults.length === 0 && floors.length > 0
        this.searchFeed.append(floors, Constant.POST_COUNT_PER_PAGE)
        this.searchResults = this.searchFeed.floors.slice()
        this.displayedKeyword = this.activeKeyword
        this.syncPreviewOrder(true, true)
        this.searchSource.update(this.searchResults)
        this.hasMore = this.searchFeed.hasMore
        this.isLoading = false
        this.refreshing = false
        this.contentPendingGeneration = -1
        }, generation, scope)
      }).catch((e: Object) => {
        if (!this.isCurrentSession(scope) || generation !== this.requestGeneration) return
        this.handleLoadError(e)
      })
      return true
    }
    this.requestFeedPage().then((data: ForumHole[]) => {
      if (!this.isCurrentSession(scope) || generation !== this.requestGeneration) return
      this.presentContent(() => {
      this.preparingFeed = this.holes.length + this.searchResults.length === 0 && data.length > 0
      this.feed.append(data, Constant.POST_COUNT_PER_PAGE, this.sortOrder)
      this.holes = this.feed.holes.slice()
      this.displayedKeyword = this.activeKeyword
      this.syncPreviewOrder(false, true)
      this.holeSource.update(this.visibleFeedHoles())
      this.hasMore = this.feed.hasMore
      this.isLoading = false
      this.refreshing = false
      this.contentPendingGeneration = -1
      if (ForumPresentation.visibleHoles(this.holes, this.foldMode).length === 0) this.prefetch()
      }, generation, scope)
    }).catch((e: Object) => {
      if (!this.isCurrentSession(scope) || generation !== this.requestGeneration) return
      this.handleLoadError(e)
    })
    return true
  }

  private requestFeedPage(): Promise<ForumHole[]> {
    return this.selectedDivision > 0
      ? this.repo.getDivisionHoles(this.feed.cursor, this.selectedDivision, '', Constant.POST_COUNT_PER_PAGE, this.sortOrder)
      : this.repo.getHomepageHoles(this.feed.cursor, Constant.POST_COUNT_PER_PAGE, this.sortOrder)
  }

  private handleLoadError(error: Object): void {
    this.contentMotionRevision++
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => { this.contentOpacity = 1 })
    this.contentPendingGeneration = -1
    this.preparingFeed = false
    this.errorMessage = ForumRepository.describeError(error)
    this.verificationRequired = error instanceof HttpError && error.statusCode === -2
    this.campusLoginRequired = this.verificationRequired && !FduRepository.getInstance().canLoginOnDemand()
    if (this.verificationRequired) this.errorMessage = ErrorDiagnostics.message(error,
      AppLanguage.text($r('app.string.forum_webvpn_verification_hint'), this.languageRevision))
    this.displayedKeyword = this.activeKeyword
    this.isLoading = false
    this.refreshing = false
  }

  private prefetch(): void {
    const count: number = this.activeKeyword.length > 0 ? this.searchResults.length :
      ForumPresentation.visibleHoles(this.holes, this.foldMode).length
    // One single-flight page ahead, with room for fast native flings. Cached
    // page rows are reused; this does not fetch the whole feed or preload tabs.
    if (!this.moreError && (count === 0 || shouldPrefetch(this.visibleEnd, count, 8))) this.loadMore()
  }

  private loadMore(): void {
    if (!this.active || !this.sessionActive || this.loadingMore || this.isLoading || this.refreshing || !this.hasMore) return
    const generation: number = this.requestGeneration
    const scope: number = this.sessionScope
    this.loadingMore = true
    this.moreError = false
    if (this.activeKeyword.length > 0) {
      this.repo.searchFloors(this.activeKeyword, this.searchFeed.offset).then((data: ForumFloor[]) => {
        if (!this.isCurrentSession(scope) || generation !== this.requestGeneration) return
        this.searchFeed.append(data, Constant.POST_COUNT_PER_PAGE)
        this.searchResults = this.searchFeed.floors.slice()
        this.syncPreviewOrder(true)
        this.searchSource.update(this.searchResults)
        this.hasMore = this.searchFeed.hasMore
        this.loadingMore = false
        this.prefetch()
      }).catch((e: Object) => {
        if (!this.isCurrentSession(scope) || generation !== this.requestGeneration) return
        this.loadingMore = false
        this.moreError = true
        this.moreDiagnosticError = ForumRepository.describeError(e)
      })
      return
    }
    this.requestFeedPage().then((data: ForumHole[]) => {
      if (!this.isCurrentSession(scope) || generation !== this.requestGeneration) return
      this.feed.append(data, Constant.POST_COUNT_PER_PAGE, this.sortOrder)
      this.holes = this.feed.holes.slice()
      this.syncPreviewOrder(false)
      this.holeSource.update(this.visibleFeedHoles())
      this.hasMore = this.feed.hasMore
      this.loadingMore = false
      this.prefetch()
    }).catch((e: Object) => {
      if (!this.isCurrentSession(scope) || generation !== this.requestGeneration) return
      this.loadingMore = false
      this.moreError = true
      this.moreDiagnosticError = ForumRepository.describeError(e)
    })
  }

  private applySearch(): void {
    const trimmed: string = this.keyword.trim()
    if (trimmed === this.activeKeyword && !this.errorMessage) return
    this.activeKeyword = trimmed
    this.loadContent()
  }

  private clearSearch(): void {
    this.liveSearch.cancel()
    this.keyword = ''
    this.activeKeyword = ''
    this.loadContent()
  }

  private pinnedHoles(): ForumHole[] {
    if (this.beforeDate > 0 || this.displayedKeyword.length > 0) return []
    const seen: Set<number> = new Set<number>()
    const rows: ForumHole[] = []
    for (const division of this.divisions) {
      if (this.selectedDivision > 0 && division.divisionId !== this.selectedDivision) continue
      for (const hole of division.pinned) {
        if (hole.holeId > 0 && !seen.has(hole.holeId)) { seen.add(hole.holeId); rows.push(hole) }
      }
    }
    return ForumPresentation.visibleHoles(rows, this.foldMode)
  }
  private visibleFeedHoles(): ForumHole[] {
    const pins: Set<number> = new Set<number>(this.pinnedHoles().map((hole: ForumHole) => hole.holeId))
    return ForumPresentation.visibleHoles(this.holes, this.foldMode).filter((hole: ForumHole) => !pins.has(hole.holeId))
  }
  private syncPreviewOrder(search: boolean, startAtTop: boolean = false): void {
    const keys: string[] = search
      ? this.searchResults.map((floor: ForumFloor) => 'forum-search-card-' + floor.floorId)
      : this.pinnedHoles().concat(this.visibleFeedHoles()).map((hole: ForumHole) => 'forum-card-' + hole.holeId)
    this.previewSequence.setOrder(keys, startAtTop)
  }
  private chooseDate(): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.beforeDate > 0 ? this.beforeDate - 1 : Date.now()),
      end: new Date(), onDateAccept: (date: Date) => {
        if (!this.active) return
        this.beforeDate = Math.min(Date.now(), new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime())
        this.liveSearch.cancel()
        this.keyword = ''
        this.activeKeyword = ''
        this.loadContent()
      } })
  }
  private clearDate(): void { this.beforeDate = 0; this.loadContent() }
  private post(): void {
    router.pushUrl({ url: 'pages/ForumEditorPage', params: new EditorRouteParams(this.selectedDivision, this.currentDivisionName()) })
      .catch((diagnosticFailure: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.ui_could_not_open_editor_please_retry'))) })
  }
  private menuSymbol(icon: string): SymbolGlyphModifier {
    const symbol: SymbolGlyphModifier = new SymbolGlyphModifier(getSymbolIcon(icon))
    symbol.fontSize(19).fontColor([ThemeColors.primary])
    return symbol
  }
  private runForumMenuAction(action: () => void): void {
    // STACK_EXPAND blurs the parent without making its uncovered rows modal.
    // Exclude blurred rows from hit testing without changing their enabled tint.
    // The native stack owns the blur/restore animation; stale callbacks stay guarded.
    if (!this.active || this.sortMenuVisible) return
    action()
  }
  @Builder
  ForumMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.forum_messages'), symbolStartIcon: this.menuSymbol('announcement') })
          .id('forum-menu-messages').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
          .onClick(() => this.runForumMenuAction(() => this.collection('messages')))
        MenuItem({ content: $r('app.string.forum_favorites'), symbolStartIcon: this.menuSymbol('star') })
          .id('forum-menu-favorites').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
          .onClick(() => this.runForumMenuAction(() => this.collection('favorites')))
        MenuItem({ content: $r('app.string.forum_subscriptions'), symbolStartIcon: this.menuSymbol('eye') })
          .id('forum-menu-subscriptions').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
          .onClick(() => this.runForumMenuAction(() => this.collection('subscriptions')))
        MenuItem({ content: $r('app.string.forum_my_posts'), symbolStartIcon: this.menuSymbol('person') })
          .id('forum-menu-posts').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
          .onClick(() => this.runForumMenuAction(() => this.collection('posts')))
        MenuItem({ content: $r('app.string.forum_my_replies'), symbolStartIcon: this.menuSymbol('reply') })
          .id('forum-menu-replies').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
          .onClick(() => this.runForumMenuAction(() => this.collection('replies')))
        MenuItem({ content: $r('app.string.forum_view_history'), symbolStartIcon: this.menuSymbol('history') })
          .id('forum-menu-history').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
          .onClick(() => this.runForumMenuAction(() => this.collection('history')))
        MenuItem({ content: $r('app.string.forum_all_tags'), symbolStartIcon: this.menuSymbol('tag') })
          .id('forum-menu-tags').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
          .onClick(() => this.runForumMenuAction(() => this.collection('tags')))
      }
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.forum_sort_title'), symbolStartIcon: this.menuSymbol('sort'), builder: () => { this.SortMenu() } })
          .id('forum-menu-sort').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
        MenuItem({ content: $r('app.string.forum_before_date'), symbolStartIcon: this.menuSymbol('history') })
          .id('forum-menu-date').hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
          .onClick(() => this.runForumMenuAction(() => this.chooseDate()))
        if (this.beforeDate > 0) {
          MenuItem({ content: $r('app.string.forum_clear_date'), symbolStartIcon: this.menuSymbol('refresh') })
            .hitTestBehavior(this.sortMenuVisible ? HitTestMode.None : HitTestMode.Default)
            .onClick(() => this.runForumMenuAction(() => this.clearDate()))
        }
      }
    }.width(264).subMenuExpandingMode(SubMenuExpandingMode.STACK_EXPAND)
  }
  @Builder
  MoreControl() {
    FloatingActionButton({ icon: 'more', label: $r('app.string.detail_more'), controlHeight: 48, controlId: 'forum-more',
      onAction: () => { this.forumMenuTransition.open(() => {
        if (this.active) { this.sortMenuVisible = false; this.forumMenuVisible = true }
      }, () => this.getUIContext()) } }).width(48)
      .bindMenu(this.forumMenuVisible, this.ForumMenu(), this.forumMenuTransition.menuOptions(this.forumMenuVisible, { placement: Placement.BottomRight,
        onDisappear: () => { this.forumMenuVisible = false; this.sortMenuVisible = false } }))
  }

  private currentDivisionName(): string {
    for (const division of this.divisions) {
      if (division.divisionId === this.selectedDivision) {
        return division.name
      }
    }
    return ''
  }

  private openHole(holeId: number, floorId: number = 0): void {
    router.pushUrl({ url: 'pages/ForumDetailPage', params: new HoleRouteParams(holeId, floorId) }).catch((diagnosticFailure: Object) => {
      DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.ui_could_not_open_post_please_retry'), this.languageRevision))
    })
  }

  @Builder
  DivisionChip(divisionId: number, name: string) {
    FloatingActionButton({ label: name, controlHeight: 36, emphasized: this.selectedDivision === divisionId,
      onAction: () => {
        if (this.selectedDivision === divisionId) return
        this.getUIContext().animateTo({ duration: 360, curve: Curve.Friction }, () => {
          this.selectedDivision = divisionId
        })
        this.clearSearch()
      } }).width('100%')
  }

  @Builder
  LatestReply(hole: ForumHole, floor: ForumFloor) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Column().width(2).height(36).backgroundColor(ThemeColors.divider).borderRadius(1)
        Column({ space: 4 }) {
          Text(AppLanguage.text($r('app.string.settings_latest_reply'), this.languageRevision,
            floor.anonyname || AppLanguage.text($r('app.string.ui_anonymous'), this.languageRevision),
            AppLanguage.relativeTime(formatRelativeTime(floor.timeCreated), this.languageRevision)))
            .fontSize(12).lineHeight(18).fontColor(ThemeColors.textHint).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(ForumLatestReply.summary(floor, AppLanguage.text($r('app.string.settings_deleted_reply'), this.languageRevision),
            AppLanguage.text($r('app.string.settings_image_summary'), this.languageRevision),
            AppLanguage.text($r('app.string.settings_sticker_summary'), this.languageRevision),
            AppLanguage.text($r('app.string.settings_quote_summary'), this.languageRevision)))
            .fontSize(13).lineHeight(20).fontColor(ThemeColors.textSecondary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(VerticalAlign.Center)
    }.width('100%').padding({ top: 10, bottom: 6 }).backgroundColor(Color.Transparent).stateEffect(false)
      .onClick(() => { this.openHole(hole.holeId, floor.floorId) })
  }

  private metadataWidth(hole: ForumHole, pinned: boolean): number {
    const special: string = hole.firstFloor?.specialTag ?? ''
    const deleted: string = hole.timeDeleted ? AppLanguage.text($r('app.string.ui_this_floor_was_deleted'), this.languageRevision) : ''
    const widths: number[] = []
    const scale: number = Math.max(1, AppStorage.get<number>('app_font_scale') ?? 1)
    if (special) widths.push((Math.min(12, ForumPresentation.tagLabel(special).length) * 11 + 14) * scale)
    if (deleted) widths.push((Math.min(12, deleted.length) * 11 + 14) * scale)
    if (pinned) widths.push(12 * scale)
    return Math.min(190, widths.reduce((sum: number, width: number) => sum + width, 0) + Math.max(0, widths.length - 1) * 6)
  }

  @Builder
  HoleCard(hole: ForumHole, pinned: boolean = false) {
    ForumPreviewCard({ controlId: 'forum-card-' + hole.holeId, sequence: this.previewSequence,
      content: (prepared: () => void) => { this.HoleCardContent(hole, pinned, prepared) },
      onRevealed: () => { this.preparingFeed = false } })
  }

  @Builder
  HoleCardContent(hole: ForumHole, pinned: boolean, prepared: () => void) {
    Column() {
      if (hole.tags.length > 0 || (hole.firstFloor?.specialTag.length ?? 0) > 0 || hole.timeDeleted.length > 0 || pinned) {
        Row({ space: 8 }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(hole.tags, (tag: ForumTag) => {
              ForumTagChip({ name: tag.name, onSelect: (name: string) => { this.collection('tag', name) } })
                .margin({ right: 6, bottom: 4 })
            }, (tag: ForumTag) => String(tag.tagId) + tag.name)
          }.layoutWeight(1)
          Row({ space: 6 }) {
            if (hole.firstFloor?.specialTag) ForumSpecialTag({ name: hole.firstFloor?.specialTag ?? '' })
            if (hole.timeDeleted) ForumSpecialTag({ name: AppLanguage.text($r('app.string.ui_this_floor_was_deleted'), this.languageRevision) })
            if (pinned) SymbolGlyph(getSymbolIcon('pin')).fontSize(12).fontColor([ThemeColors.textSecondary]).accessibilityText($r('app.string.forum_pinned'))
          }.width(this.metadataWidth(hole, pinned)).justifyContent(FlexAlign.End).alignItems(VerticalAlign.Center)
        }.width('100%').justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Top).margin({ bottom: 8 })
      }

      if (ForumPresentation.isCaution(hole) && this.foldMode !== 'show' && !this.revealedHoles.includes(hole.holeId)) {
        Text(AppLanguage.text($r('app.string.ui_read_with_care_content_collapsed_tap_to_expand'), this.languageRevision))
          .fontSize(14).fontColor(ThemeColors.textSecondary).padding({ top: 12, bottom: 12 })
          .onAppear(prepared)
      } else {
        ForumContentView({ content: hole.firstFloor?.content ?? '', mentions: hole.firstFloor?.mention ?? [], preview: true,
          previewWork: this.previewWork,
          coordinatedPreview: true, onPrepared: prepared,
          onPreviewOpen: () => { this.openHole(hole.holeId) } })
        if (ForumLatestReply.floor(hole) !== null) this.LatestReply(hole, ForumLatestReply.floor(hole)!)
      }

      Row() {
        Text(hole.getAuthor())
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textSecondary)
        Text(' · ' + AppLanguage.relativeTime(hole.getDisplayTime(), this.languageRevision))
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textHint)
        Blank()
        Row({ space: 10 }) {
          Row({ space: 3 }) {
            SymbolGlyph(getSymbolIcon('eye')).fontSize(12).fontColor([ThemeColors.textHint])
            Text(String(hole.view)).fontSize(ThemeDimens.textSizeSmall).fontColor(ThemeColors.textHint)
          }.accessibilityText(hole.view + AppLanguage.text($r('app.string.ui_views'), this.languageRevision))
          Row({ space: 3 }) {
            SymbolGlyph(getSymbolIcon('replies')).fontSize(12).fontColor([ThemeColors.textHint])
            Text(String(hole.reply)).fontSize(ThemeDimens.textSizeSmall).fontColor(ThemeColors.textHint)
          }.accessibilityText(hole.reply + AppLanguage.text($r('app.string.ui_replies'), this.languageRevision))
        }.alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
    .borderRadius(ThemeDimens.radiusMedium)
    .margin({ bottom: 12 })
    .onClick(() => {
      if (ForumPresentation.isCaution(hole) && this.foldMode !== 'show' && !this.revealedHoles.includes(hole.holeId)) {
        this.revealedHoles = this.revealedHoles.concat([hole.holeId])
      } else {
        this.openHole(hole.holeId)
      }
    })
  }

  @Builder
  SearchResultCard(floor: ForumFloor) {
    ForumPreviewCard({ controlId: 'forum-search-card-' + floor.floorId, sequence: this.previewSequence,
      content: (prepared: () => void) => { this.SearchResultContent(floor, prepared) },
      onRevealed: () => { this.preparingFeed = false } })
  }

  @Builder
  SearchResultContent(floor: ForumFloor, prepared: () => void) {
    Column() {
      ForumContentView({ content: floor.content, mentions: floor.mention, preview: true,
        previewWork: this.previewWork,
        coordinatedPreview: true, onPrepared: prepared,
        onPreviewOpen: () => { this.openHole(floor.holeId) } })
      Row() {
        Text(floor.anonyname.length > 0 ? floor.anonyname : AppLanguage.text($r('app.string.ui_anonymous'), this.languageRevision))
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textSecondary)
        Text(' · ' + AppLanguage.relativeTime(floor.getDisplayTime(), this.languageRevision))
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textHint)
        Blank()
        Text('#' + floor.holeId)
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textHint)
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
    .borderRadius(ThemeDimens.radiusMedium)
    .margin({ bottom: 12 })
    .onClick(() => this.openHole(floor.holeId))
  }

  @Builder
  StatusBlock(iconName: string, title: string, detail: string) {
    Column() {
      SymbolGlyph(getSymbolIcon(iconName))
        .fontSize(40)
        .fontColor([ThemeColors.textHint])
      Text(title)
        .fontSize(ThemeDimens.textSizeTitle)
        .fontColor(ThemeColors.textSecondary)
        .margin({ top: 12 })
      if (detail.length > 0) {
        if (iconName === 'about') {
          ErrorNotice({ message: detail, controlId: 'forum-page-diagnostics' }).margin({ top: 6 })
        } else { Text(detail)
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textHint)
          .margin({ top: 6 })
          .textAlign(TextAlign.Center)
        }
      }
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  LoginGate() {
    Column() {
      SymbolGlyph(getSymbolIcon('forum'))
        .fontSize(48)
        .fontColor([ThemeColors.primaryLight])
      Text(AppLanguage.text($r('app.string.ui_log_in_to_browse_the_forum'), this.languageRevision))
        .fontSize(ThemeDimens.textSizeTitle)
        .fontColor(ThemeColors.textPrimary)
        .margin({ top: 16 })
      Text(AppLanguage.text($r('app.string.ui_a_fduhole_com_account_is_required_please_log_in'), this.languageRevision))
        .fontSize(ThemeDimens.textSizeSmall)
        .fontColor(ThemeColors.textHint)
        .margin({ top: 8 })
        .textAlign(TextAlign.Center)
      Button(AppLanguage.text($r('app.string.ui_log_in_to_forum'), this.languageRevision))
        .type(ButtonType.Normal)
        .width(180)
        .height(44)
        .borderRadius(22)
        .backgroundColor(ThemeColors.primary)
        .fontColor('#FFFFFF')
        .fontSize(ThemeDimens.textSizeBody)
        .margin({ top: 24 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/ForumLoginPage' })
        })
    }
    .width('100%')
    .padding({ top: 72, bottom: 72 })
    .alignItems(HorizontalAlign.Center)
  }

  private headerInset(): number {
    const extraRows: number = Math.max(0, Math.ceil(this.divisions.length / 5) - 1)
    return px2vp(this.topPx) + (this.sessionActive && this.displayedKeyword.length === 0 ? 172 + extraRows * 42 : 120) +
      (this.beforeDate > 0 ? 32 : 0)
  }

  @Builder
  HeaderIcon(icon: string, title: Resource, action: () => void) {
    FloatingActionButton({ icon: icon, label: title, controlHeight: 48, onAction: action }).width(48)
  }

  @Builder
  SortMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.forum_sort_replied') }).selected(this.sortOrder === 'time_updated').selectIcon(true)
        .id('forum-sort-replied').enabled(!this.orderSaving)
        .onClick(() => { this.changeOrder('time_updated') })
      MenuItem({ content: $r('app.string.forum_sort_created') }).selected(this.sortOrder === 'time_created').selectIcon(true)
        .id('forum-sort-created').enabled(!this.orderSaving)
        .onClick(() => { this.changeOrder('time_created') })
    }.width(240).id('forum-sort-menu')
      .onAppear(() => { this.sortMenuVisible = true })
      .onDisAppear(() => { this.sortMenuVisible = false })
  }

  @Builder
  ActivityRow(item: AnnouncementBanner, expanded: boolean = false) {
    Row({ space: 10 }) {
      SymbolGlyph(getSymbolIcon('announcement')).fontSize(18).fontColor([ThemeColors.primary])
      Text(item.title).fontSize(13).lineHeight(20).fontColor(ThemeColors.textPrimary).layoutWeight(1).maxLines(expanded ? 1000 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.action.length > 0) {
        Text(item.button || AppLanguage.text($r('app.string.forum_activity_open'), this.languageRevision))
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.primary).constraintSize({ maxWidth: 76 })
      }
    }.width('100%').padding({ left: 12, right: 8, top: expanded ? 12 : 8, bottom: expanded ? 12 : 8 })
      .alignItems(VerticalAlign.Center).onClick(() => { if (item.action) this.openActivity(item) })
  }

  @Builder
  ActivityBanner(items: () => AnnouncementBanner[]) {
    Row({ space: 4 }) {
      Swiper() {
        ForEach(items(), (item: AnnouncementBanner) => { this.ActivityRow(item) },
          (item: AnnouncementBanner) => item.title + item.action)
      }.autoPlay(items().length > 1).interval(6000).indicator(false).loop(true).layoutWeight(1).height(56)
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(getSymbolIcon('expand')).fontSize(16).fontColor([ThemeColors.textSecondary])
      }.width(40).height(40).flexShrink(0).padding(0).backgroundColor(Color.Transparent).stateEffect(false).hoverEffect(HoverEffect.None)
        .id('forum-activities-expand')
        .onClick(() => { this.activitiesSheetTransition.open(() => {
          if (this.active) this.activitiesSheet = true
        }, () => this.getUIContext()) }).accessibilityText(AppLanguage.text($r('app.string.forum_activities_all'), this.languageRevision))
    }.width('100%').alignItems(VerticalAlign.Center).padding({ right: 4 }).borderRadius(18).backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
  }

  @Builder
  ActivityStatus(loading: () => boolean, error: () => string, checkedAt: () => number, cached: boolean = false) {
    Row({ space: 12 }) {
      if (loading() || checkedAt() === 0) {
        LoadingProgress().width(20).height(20).color(ThemeColors.primary)
      } else {
        SymbolGlyph(getSymbolIcon('announcement')).fontSize(18).fontColor([ThemeColors.primary])
      }
      Column({ space: 4 }) {
        Text(cached ? $r('app.string.forum_activities_cached') : loading() || checkedAt() === 0 ?
          $r('app.string.forum_activities_loading') : error() ? $r('app.string.forum_activities_unavailable') : $r('app.string.forum_activities_empty'))
          .fontSize(13).lineHeight(20).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%')
        Text(loading() || checkedAt() === 0 ? $r('app.string.forum_activities_source') : error() ?
          $r('app.string.forum_activities_retry_hint') : $r('app.string.forum_activities_empty_hint'))
          .fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
        if (!loading() && error()) {
          DiagnosticLink({ message: error(), summary: AppLanguage.text($r('app.string.forum_activities_unavailable'), this.languageRevision),
            controlId: 'forum-activities-diagnostics' })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (!loading() && checkedAt() > 0) {
        this.HeaderIcon('refresh', $r('app.string.ui_retry'), () => { this.loadActivities(true) })
      }
    }.width('100%').padding(12).alignItems(VerticalAlign.Center).borderRadius(20)
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      
  }

  @Builder
  ActivitySection(enabled: () => boolean, items: () => AnnouncementBanner[], loading: () => boolean, error: () => string, checkedAt: () => number) {
    if (enabled() && (items().length > 0 || loading() || checkedAt() === 0 || error().length > 0)) {
      Column({ space: 8 }) {
        if (items().length > 0) {
          this.ActivityBanner(items)
          if (error().length > 0) { this.ActivityStatus(loading, error, checkedAt, true) }
        } else {
          this.ActivityStatus(loading, error, checkedAt)
        }
      }.width('100%').margin({ bottom: 12 })
    }
  }

  @Builder
  ActivitiesSheet(items: () => AnnouncementBanner[]) {
    Column({ space: 8 }) {
      Scroll() {
        Column({ space: 8 }) { ForEach(items(), (item: AnnouncementBanner) => { this.ActivityRow(item, true) }, (item: AnnouncementBanner) => item.title + item.action) }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 360 }).scrollBar(BarState.Off)
    }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 20 })
  }

  @Builder
  SearchControls() {
    Row() {
      SymbolGlyph(getSymbolIcon('search')).fontSize(18).fontColor([ThemeColors.textHint]).margin({ right: 8 })
      TextInput({ text: this.keyword, placeholder: AppLanguage.text($r('app.string.ui_search_forum'), this.languageRevision) })
        .layoutWeight(1).height('100%').backgroundColor(Color.Transparent).padding(0)
        .fontSize(ThemeDimens.textSizeBody).fontColor(ThemeColors.textPrimary).placeholderColor(ThemeColors.textHint)
        .cancelButton({ style: CancelButtonStyle.INVISIBLE }).id('forum-search-input')
        .onChange((value: string) => { this.keyword = value; this.liveSearch.update(value) }).onSubmit(() => this.liveSearch.flush())
      if (this.keyword.length > 0) {
        SearchClearButton({ controlId: 'forum-search-clear', onClear: () => this.clearSearch() })
          // The native tab-bar builder adds 12vp; match the search row's 8vp end inset.
          .margin({ right: -4 })
      }
    }.width('100%').height('100%').padding({ left: 16, right: 0 }).alignItems(VerticalAlign.Center)
  }

  @Builder
  PageFailure() {
    Column({ space: 12 }) {
      this.StatusBlock('about', AppLanguage.text($r('app.string.ui_loading_failed'), this.languageRevision),
        this.errorMessage.length > 0 ? this.errorMessage : this.divisionsError)
      FloatingActionButton({ label: this.campusLoginRequired || this.divisionsNeedLogin ? $r('app.string.ui_log_in_to_campus_account') :
        this.verificationRequired || this.divisionsVerificationRequired ? $r('app.string.campus_verify_continue') : $r('app.string.ui_retry'),
        controlHeight: 42, controlId: 'forum-page-retry', emphasized: true, actionEnabled: !this.verifying,
        onAction: () => { this.retryVerification() } }).width(160)
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.backgroundSource.length > 0) {
        Image(this.backgroundSource).width('100%').height('100%').objectFit(ImageFit.Cover)
          .opacity(this.darkMode ? 0.18 : 0.12).hitTestBehavior(HitTestMode.None)
      }
        Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
      Column() {
      if (!this.sessionActive) {
        List({ scroller: this.touchScroller }) {
          if (this.activitiesEnabled) {
            ListItem() { this.ActivitySection(() => this.activitiesEnabled, () => this.activities, () => this.activitiesLoading, () => this.activitiesError, () => this.activitiesCheckedAt) }
          }
          ListItem() { this.LoginGate() }
          ListItem() { Column().height(Math.max(16, px2vp(this.bottomPx)) + 96) }
        }.width('100%').height('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter }).contentStartOffset(this.headerInset())
          .syncLoad(true).cachedCount(2)
          .onTouch((event: TouchEvent) => { this.previewWork.touch(event) })
          .onScrollStart(() => { this.previewWork.scrollStarted() }).onScrollStop(() => { this.previewWork.scrollStopped() })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Off)
      } else if (this.errorMessage.length > 0 && this.displayedKeyword.length > 0) {
        Column() {
          this.PageFailure()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center).padding({ top: this.headerInset() })
      } else if (this.displayedKeyword.length > 0) {
        if (this.searchResults.length === 0) {
          Column() { this.StatusBlock('search', AppLanguage.text($r('app.string.ui_no_matching_content'), this.languageRevision), AppLanguage.text($r('app.string.ui_try_a_different_keyword'), this.languageRevision)) }.padding({ top: this.headerInset() })
        } else {
          List({ scroller: this.touchScroller }) {
            LazyForEach(this.searchSource, (floor: ForumFloor) => {
              ListItem() {
                this.SearchResultCard(floor)
              }
            }, (floor: ForumFloor) => String(floor.floorId))
            if (this.hasMore) { ListItem() { this.MoreFooter() } }
            ListItem() { Column().height(Math.max(16, px2vp(this.bottomPx)) + 96) }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
          .contentStartOffset(this.headerInset())
          .syncLoad(true).cachedCount({ minCount: 4, maxCount: 8 }, false)
          .onTouch((event: TouchEvent) => { this.previewWork.touch(event) })
          .onScrollStart(() => { this.previewSequence.beginBrowsing(); this.previewWork.scrollStarted() })
          .onScrollStop(() => { this.previewWork.scrollStopped() })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .scrollBar(BarState.Off)
          .onScrollIndex((start: number, end: number) => {
            this.previewSequence.setStart(start); this.visibleEnd = end; this.prefetch()
          })
        }
      } else {
        List({ scroller: this.touchScroller }) {
          if (this.activitiesEnabled) {
            ListItem() { this.ActivitySection(() => this.activitiesEnabled, () => this.activities, () => this.activitiesLoading, () => this.activitiesError, () => this.activitiesCheckedAt) }
          }
          if (this.errorMessage.length > 0 || this.divisionsVerificationRequired) {
            ListItem() {
              this.PageFailure()
            }
          }
          if (this.errorMessage.length === 0) {
          if (!this.isLoading && this.visibleFeedHoles().length + this.pinnedHoles().length === 0) {
            ListItem() {
              this.StatusBlock('empty', AppLanguage.text($r('app.string.ui_no_posts_to_display'), this.languageRevision), this.hasMore ? AppLanguage.text($r('app.string.ui_posts_on_this_page_are_hidden_you_can_load_more'), this.languageRevision) : '')
            }
          }
          ForEach(this.pinnedHoles(), (hole: ForumHole) => {
            ListItem() { this.HoleCard(hole, true) }
          }, (hole: ForumHole) => 'pinned-' + hole.holeId)
          LazyForEach(this.holeSource, (hole: ForumHole) => {
            ListItem() {
              this.HoleCard(hole)
            }
          }, (hole: ForumHole) => String(hole.holeId))
          if (this.hasMore) {
            ListItem() {
              this.MoreFooter()
            }
          }
          }
          ListItem() { Column().height(Math.max(16, px2vp(this.bottomPx)) + 96) }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
          .contentStartOffset(this.headerInset())
          // Native List owns re-touch, fling cancellation and the next pan.
          // scrollTo() from Down adds a programmatic jump to that transaction.
          .syncLoad(true).cachedCount({ minCount: 4, maxCount: 8 }, false)
          .onTouch((event: TouchEvent) => { this.previewWork.touch(event) })
          .onScrollStart(() => { this.previewSequence.beginBrowsing(); this.previewWork.scrollStarted() })
          .onScrollStop(() => { this.previewWork.scrollStopped() })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
        .onScrollIndex((start: number, end: number) => {
          const leading: number = (this.activitiesEnabled ? 1 : 0) +
            (this.errorMessage.length > 0 || this.divisionsVerificationRequired ? 1 : 0)
          this.previewSequence.setStart(start - leading)
          this.visibleEnd = end - leading - this.pinnedHoles().length; this.prefetch()
        })
      }
      }.width('100%').height('100%')
      }.width('100%').height('100%').opacity(this.contentOpacity).translate({ y: this.contentShift })
        .onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => {
        if (this.sessionActive) this.refreshFeed()
        else { this.refreshing = false; this.loadActivities(true); this.bootstrap() }
      })
      CenterLoadingProgress({ busy: (this.isLoading || this.preparingFeed) && this.sessionActive && !this.refreshing })
      TopFade({ extent: this.headerInset() - 20 })
      FeedRefreshProgress({ topInset: this.headerInset() + 12, pullOffset: this.pullOffset, refreshing: this.refreshing })
      Column() {
      // ── header ──
      Row({ space: 6 }) {
        Text(AppLanguage.text($r('app.string.ui_forum'), this.languageRevision))
          .fontSize(ThemeDimens.textSizeXLarge)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
        Blank()
        if (this.sessionActive) {
          FloatingActionButton({ label: $r('app.string.forum_post'), icon: 'edit', controlHeight: 48,
            emphasized: true, controlId: 'forum-post', onAction: () => this.post() }).width(48)
          this.MoreControl()
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })

      // Floating search capsule.
      FloatingSurface({ radius: 22, acceptsInput: true, content: () => { this.SearchControls() } })
        .height(44).margin({ left: 20, right: 20 })

      if (this.beforeDate > 0) {
        Row({ space: 8 }) {
          Text(AppLanguage.text($r('app.string.forum_before_date_value'), this.languageRevision,
            new Date(this.beforeDate - 1).toLocaleDateString())).fontSize(12).fontColor(ThemeColors.primary)
          SearchClearButton({ controlId: 'forum-date-clear', onClear: () => this.clearDate() })
        }.height(32).alignItems(VerticalAlign.Center)
      }
      // ── division chips ──
      if (this.sessionActive && this.displayedKeyword.length === 0) {
        Column({ space: 6 }) {
          // Equal-width cells fit the current divisions without horizontal
          // scrolling. Additional server divisions form another visible row.
          GridRow({ columns: Math.max(1, Math.min(5, this.divisions.length)), gutter: { x: 6, y: 6 } }) {
            ForEach(this.divisions, (division: ForumDivision) => {
              GridCol() { this.DivisionChip(division.divisionId, division.name) }
            }, (division: ForumDivision) => String(division.divisionId))
          }.width('100%')
          if (this.divisionsLoading) {
            Row({ space: 6 }) {
              LoadingProgress().width(16).height(16).color(ThemeColors.primary)
              Text(AppLanguage.text($r('app.string.forum_divisions_loading'), this.languageRevision))
                .fontSize(12).fontColor(ThemeColors.textSecondary)
            }.alignItems(VerticalAlign.Center)
          } else if (this.divisionsError.length > 0 && !this.divisionsVerificationRequired) {
            FloatingActionButton({ label: $r('app.string.forum_divisions_retry'), controlHeight: 32, actionEnabled: !this.verifying,
                onAction: () => { this.retryVerification(true) } }).width(168)
          }
        }.width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter }).margin({ top: 8 })
          .clip(false)
      }

      // ── body ──
      }.width('100%').padding({ top: px2vp(this.topPx) })
        .hitTestBehavior(HitTestMode.Transparent)

    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.activitiesSheet, this.ActivitiesSheet(() => this.activities), this.activitiesSheetTransition.options(this.activitiesSheet, { height: SheetSize.FIT_CONTENT, showClose: true, dragBar: true,
      title: { title: $r('app.string.forum_activities_all') },
      backgroundColor: nativeFloatingBackground(this.materialRevision), systemMaterial: adaptiveMaterial(this.materialRevision) }))
  }

  @Builder
  MoreFooter() {
    Row() {
      if (this.loadingMore) { LoadingProgress().width(22).height(22) }
      if (this.moreError) { ErrorNotice({ message: this.moreDiagnosticError, controlId: 'forum-more-diagnostics' }) }
      else Text(this.loadingMore ? AppLanguage.text($r('app.string.ui_loading'), this.languageRevision) : AppLanguage.text($r('app.string.ui_scroll_up_to_load_more'), this.languageRevision))
        .fontSize(13).fontColor(ThemeColors.textSecondary).margin({ left: 8 })
    }.width('100%').constraintSize({ minHeight: 48 }).justifyContent(FlexAlign.Center).onClick(() => this.loadMore())
  }
}
