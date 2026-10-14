import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ForumImageTransition } from '../common/ForumImageTransition'
import { ErrorNotice, DiagnosticLink } from './ErrorNotice'
import { settleScrollTouch } from '../common/ScrollTouch'
import { ForumSpecialTag } from './ForumSpecialTag'
import { MoreGlyph } from './MoreGlyph'
import { forumActionIcon } from '../common/ForumActionIcons'
import { getSymbolIcon } from '../common/DanXiIcons'
import { CenterLoadingProgress } from './CenterLoadingProgress'
import { AppLanguage } from '../common/AppLanguage'
import { ForumPreferences } from '../common/ForumPreferences'
import { ForumReadingProgress, ForumReadingPosition } from '../common/ForumReadingProgress'
import { EmptyRefreshIndicator, FeedRefreshProgress } from './FeedRefreshProgress'
import { FloatingSurface } from '../components/FloatingSurface'
import { BottomFade } from '../components/BottomFade'
import { TopFade } from '../components/TopFade'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
/**
 * Tree Hole thread detail (帖子详情).
 *
 * GET /holes/{id} + GET /holes/{id}/floors, with reply and like/dislike writes.
 * Ported from lib/page/forum/hole_detail.dart
 */

import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { picker, fileIo as fs } from '@kit.CoreFileKit'
import { ForumRepository } from '../repository/ForumRepository'
import { FduRepository } from '../repository/FduRepository'
import { HttpError } from '../util/HttpUtil'
import { ForumRoute } from '../common/ForumRoute'
import { ForumHole, ForumFloor, ForumTag, ForumDivision, ForumUser, formatRelativeTime } from '../model/Forum'
import { ForumDetailSource, ForumDetailRules, ForumHistory, ForumSummary, SummaryBranch, SummaryInteraction } from '../model/ForumDetail'
import { ForumContentParser } from '../model/ForumContent'
import { ForumImage } from '../model/ForumImage'
import { ForumStickers } from '../common/ForumStickers'
import { pasteboard } from '@kit.BasicServicesKit'
import { ForumLocalState } from '../common/ForumLocalState'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { HoleRouteParams } from '../common/RouteParams'
import { Constant } from '../common/Constant'
import { ForumPresentation } from '../common/ForumPresentation'
import { ForumContentView } from '../components/ForumContentView'
import { ForumFloorFeed, shouldPrefetch } from '../model/ForumPaging'
import { ForumFloorLocator, ForumFloorWindow } from '../model/ForumFloorLocator'
import { ForumListSource } from '../common/ForumListSource'
import { ForumListRouteParams } from '../common/ForumListRoute'
import { ForumTagChip } from './ForumTagChip'
import { ForumVoteState } from '../model/ForumVoteState'
import { ForumVoteControls } from './ForumVoteControls'
import { ForumThreadRoute } from '../model/ForumThreadHistory'
import { ForumSummaryRules } from '../model/ForumSummaryRules'
import { ForumSummaryView } from './ForumSummaryView'

const PAGE_SIZE: number = 10

@Component
export struct ForumDetailView {
  private showSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private voteStates: Map<number, ForumVoteState> = new Map()
  private voteModels: Map<number, ForumFloor> = new Map()
  private floorRenderVersions: Map<number, number> = new Map<number, number>()
  @StorageLink(ForumPreferences.SUMMARY) summaryEnabled: boolean = true
  @Prop @Watch('routeChanged') initialRoute: ForumThreadRoute = new ForumThreadRoute(-1)
  @Prop initialHoleId: number = -1
  @Prop initialFloorId: number = 0
  repo: ForumDetailSource = ForumRepository.getInstance()
  onBack: () => void = () => { router.back() }
  onNavigate: ((holeId: number, floorId: number, position: ForumReadingPosition | null) => void) | undefined = undefined
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  private sourceIndex: number = router.getState().index
  private topInset(): number { return px2vp(ForumImageTransition.sourceInset(this.sourceIndex, this.topPx)) }
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink(Constant.KEY_FORUM_FOLD_BEHAVIOR) foldMode: string = 'fold'
  @State revealed: boolean = false
  @State openingFloor: ForumFloor | null = null
  @State hole: ForumHole | null = null
  @State floors: ForumFloor[] = []
  @State isLoading: boolean = true
  @State isLoadingMore: boolean = false
  @State isSending: boolean = false
  @State errorMessage: string = ''
  @State verificationRequired: boolean = false
  @State verifying: boolean = false
  @State replyText: string = ''
  @State hasMore: boolean = true
  @State refreshing: boolean = false
  @State private pullOffset: number = 0
  @State moreError: boolean = false
  @State moreDiagnosticError: string = ''
  @State highlightId: number = 0
  @State locating: boolean = false
  @State locateError: boolean = false
  @State locateDiagnosticError: string = ''
  @State favorite: boolean = false
  @State subscribed: boolean = false
  @State preferenceBusy: boolean = false
  @State private favoritePending: boolean = false
  @State private subscriptionPending: boolean = false
  private preferenceReadPending: boolean = false
  @State preferenceReady: boolean = false
  @State private favoriteScale: number = 1
  @State private subscriptionScale: number = 1
  @State preferenceError: string = ''
  @State admin: boolean = false
  @State filterAuthor: string = ''
  @State replyTarget: ForumFloor | null = null
  @State revealedFloors: number[] = []
  @State showSheet: boolean = false
  @State sheetKind: string = 'hole'
  @State selectedFloor: ForumFloor | null = null
  @State sheetBusy: boolean = false
  @State sheetError: string = ''
  @State draft: string = ''
  @State composeMode: string = 'reply'
  @State previewDraft: boolean = false
  @State composeContentHeight: number = 0
  @State imageUploadGeneration: number = -1
  @State history: ForumHistory[] = []
  @State summary: ForumSummary | null = null
  @State summaryFeedbackSent: boolean = false
  @State summaryFeedbackPending: boolean = false
  @State summaryFeedbackType: string = ''
  @State summaryPhase: string = 'loading'
  private summaryTimer: number = -1
  private summaryDeadline: number = 0
  private summaryAttempts: number = 0
  @State selectedIds: number[] = []
  @State loadToEnd: boolean = false
  @State managementAction: string = ''
  @State divisions: ForumDivision[] = []
  @State allTags: ForumTag[] = []
  @State tagIds: number[] = []
  @State chosenDivision: number = 0

  private holeId: number = 0
  private votingIds: number[] = []
  private reloadAfterVotes: boolean = false
  private loadPendingGeneration: number = -1
  private loadPendingHole: number = -1
  @State private listOpacity: number = 1
  @State private contentSettling: boolean = false
  @State private listShift: number = 0
  private listMotionTimer: number = -1

  private animateLocation(): void {
    if (this.listMotionTimer >= 0) clearTimeout(this.listMotionTimer)
    const generation: number = this.loadGeneration
    this.contentSettling = true
    this.listOpacity = 0; this.listShift = 0
    this.listMotionTimer = setTimeout(() => {
      if (this.active && generation === this.loadGeneration) this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut, onFinish: () => {
        if (this.active && generation === this.loadGeneration) this.contentSettling = false
      } }, () => {
        this.listOpacity = 1; this.listShift = 0
      })
    }, 160)
  }
  private loadGeneration: number = 0
  private feed: ForumFloorFeed = new ForumFloorFeed()
  private visibleEnd: number = -1
  private active: boolean = false
  private pendingLocate: number = 0
  private pendingRanking: number = 0
  private locateGeneration: number = 0
  private windowGeneration: number = 0
  private locateToBottom: boolean = false
  private latestLocation: boolean = false
  private locateAnchorId: number = 0
  private locateSettleTimer: number = -1
  private scrollTimer: number = -1
  private highlightTimer: number = -1
  private sheetGeneration: number = 0
  private preferenceGeneration: number = 0
  private draftSelectionStart: number = 0
  private draftSelectionEnd: number = 0
  private draftController: TextAreaController = new TextAreaController()
  private scroller: Scroller = new Scroller()
  private floorSource: ForumListSource<ForumFloor> = new ForumListSource<ForumFloor>()
  private galleryKey: string = ''
  private galleryFloors: ForumFloor[] | null = null
  private galleryOpening: ForumFloor | null = null
  private galleryImages: string[] = []
  @StorageLink('app_foreground') @Watch('foregroundChanged') foreground: boolean = true
  private readingOwner: number = 0
  private readingInitialized: boolean = false
  private readingPosition: ForumReadingPosition | null = null
  private navigationResume: ForumReadingPosition | null = null
  private resumePosition: ForumReadingPosition | null = null
  private resumeTimer: number = -1
  private resumeDeadline: number = 0
  private saveTimer: number = -1
  @State private windowStart: number = 0
  @State private loadingEarlier: boolean = false
  @State private earlierError: string = ''
  private visibleStart: number = 0
  private topScrollPosted: boolean = false
  private topLocation: boolean = false
  private topScrollTimer: number = -1

  private systemTopScroll(offset: number, source: ScrollSource): ScrollResult | void {
    // The installed native engine reports status-bar back-to-top as
    // OTHER_USER_INPUT; scroller-driven return-to-top uses SCROLLER_ANIMATION.
    // Ordinary finger drag/fling and non-animated floor location are separate.
    if ((source !== ScrollSource.OTHER_USER_INPUT && source !== ScrollSource.SCROLLER_ANIMATION) || offset >= 0 || this.windowStart <= 0 ||
      !this.active || this.isLoading || this.showSheet || this.needsReveal()) return
    // The native status-bar action animates to the loaded List's first row.
    // Resolve the actual thread prefix once, instead of walking every page
    // between the latest reply and 0F or stopping at the partial-window edge.
    if (!this.topScrollPosted && !this.topLocation) {
      this.topScrollPosted = true
      const generation: number = this.loadGeneration
      const location: number = this.locateGeneration
      // Returning zero can stop the native animation without another frame.
      // A queued UI task must still start the read on this first action.
      this.topScrollTimer = setTimeout(() => {
        this.topScrollTimer = -1
        this.topScrollPosted = false
        if (this.active && generation === this.loadGeneration && location === this.locateGeneration) this.returnToTop()
      }, 0)
    }
    return { offsetRemain: 0 }
  }

  private returnToTop(): void {
    if (!this.active || this.isLoading || this.needsReveal() || (this.topLocation && this.locating)) return
    this.cancelLocation()
    this.filterAuthor = ''; this.latestLocation = false; this.topLocation = true
    this.locateError = false; this.locateDiagnosticError = ''
    if (this.windowStart <= 0) {
      this.topLocation = false; this.floorSource.update(this.replies())
      this.scroller.scrollEdge(Edge.Top)
      return
    }
    this.locating = true
    const generation: number = this.loadGeneration
    const location: number = ++this.locateGeneration
    const window: number = ++this.windowGeneration
    this.isLoadingMore = false; this.loadingEarlier = false; this.earlierError = ''
    const current = (): boolean => this.active && generation === this.loadGeneration &&
      location === this.locateGeneration && window === this.windowGeneration
    this.repo.getFloors(this.holeId, 0, PAGE_SIZE).then((rows: ForumFloor[]) => {
      if (!current()) return
      if (rows.some((floor: ForumFloor) => floor.holeId !== this.holeId)) throw new Error('Invalid first floor range')
      this.listOpacity = 0; this.windowStart = 0
      this.feed = new ForumFloorFeed(); this.feed.append(rows, PAGE_SIZE)
      this.floors = this.feed.floors.slice()
      if (this.openingFloor === null && rows[0]?.ranking === 1) this.openingFloor = rows[0]
      this.floorSource.update(this.replies()); this.hasMore = this.feed.hasMore
      this.visibleStart = 0; this.visibleEnd = -1; this.moreError = false
      this.readingInitialized = true
      this.getUIContext().postFrameCallback({ onFrame: () => {
        if (!current()) return
        this.scroller.scrollEdge(Edge.Top)
        this.locating = false; this.topLocation = false
        this.animateLocation()
      }, onIdle: () => {} })
    }).catch((e: Object) => {
      if (!current()) return
      this.locating = false; this.locateError = true; this.listOpacity = 1
      this.locateDiagnosticError = ForumRepository.describeError(e)
    })
  }

  private foregroundChanged(): void {
    if (!this.foreground) {
      this.saveReading()
      this.cancelSummaryPolling()
    } else if (this.active && this.showSheet && this.sheetKind === 'summary' && ForumSummaryRules.waiting(this.summaryPhase) && !this.sheetBusy) {
      this.summaryDeadline = Date.now() + 120000
      this.readSummary(this.sheetGeneration, false)
    }
  }

  private saveReading(): void {
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer)
    this.saveTimer = -1
    if (this.readingPosition !== null) ForumReadingProgress.save(this.readingPosition).catch(() => {})
  }

  private captureReading(): void {
    if (!this.active || this.isLoading || this.refreshing || this.locating || this.loadToEnd || this.filterAuthor ||
      this.resumePosition !== null || this.needsReveal()) return
    try {
      const top: number = this.topInset() + 72
      const hit: number = this.scroller.getItemIndex(40, top + 1)
      const index: number = hit >= 0 ? hit : this.visibleStart
      const floor: ForumFloor | null | undefined = index === 0 ? this.openingFloor : this.replies()[index - 1]
      if (floor === null || floor === undefined) return
      const rect: RectResult = this.scroller.getItemRect(index)
      if (rect.height <= 0) return
      const position = new ForumReadingPosition()
      position.owner = this.readingOwner; position.holeId = this.holeId; position.floorId = floor.floorId
      position.index = index === 0 ? 0 : this.windowStart + this.floors.findIndex((item: ForumFloor) => item.floorId === floor.floorId)
      position.offset = Math.max(0, Math.min(top - rect.y, rect.height - 1)); position.updated = Date.now()
      this.readingPosition = position
      if (this.saveTimer < 0) this.saveTimer = setTimeout(() => { this.saveReading() }, 2000)
    } catch (e) { /* A detached/offscreen lazy row must not overwrite the previous anchor. */ }
  }

  private cancelResume(): void {
    this.resumePosition = null
    this.locateAnchorId = 0
    if (this.locateSettleTimer >= 0) clearTimeout(this.locateSettleTimer)
    this.locateSettleTimer = -1
    if (this.resumeTimer >= 0) clearTimeout(this.resumeTimer)
    this.resumeTimer = -1
  }

  private restoreReading(): void {
    if (!this.active || this.isLoading || this.resumePosition === null || this.needsReveal()) return
    const position: ForumReadingPosition = this.resumePosition
    const replies = this.replies()
    const found: number = replies.findIndex((floor: ForumFloor) => floor.floorId === position.floorId)
    const index: number = this.openingFloor?.floorId === position.floorId ? 0 : found >= 0 ? found + 1 :
      Math.min(replies.length, Math.max(1, position.index - this.windowStart + 1))
    const generation: number = this.loadGeneration
    if (this.resumeTimer >= 0) clearTimeout(this.resumeTimer)
    this.resumeTimer = setTimeout(() => {
      if (!this.active || generation !== this.loadGeneration || this.resumePosition !== position) return
      try {
        this.scroller.scrollToIndex(index, false, ScrollAlign.START)
        const rect: RectResult = this.scroller.getItemRect(index)
        // Reapply when ArkWeb/images report their final size; a touch immediately cancels restoration.
        const offset: number = found >= 0 || this.openingFloor?.floorId === position.floorId ? Math.min(position.offset, Math.max(0, rect.height - 1)) : 0
        this.scroller.scrollBy(0, offset)
      } catch (e) {}
    }, 80)
  }

  private readingLayoutChanged(floorId: number): void {
    if (this.resumePosition?.floorId === floorId && Date.now() <= this.resumeDeadline) this.restoreReading()
    if (this.locateAnchorId <= 0 || this.locateAnchorId !== this.highlightId) return
    const target: number = this.locateAnchorId
    const generation: number = this.loadGeneration
    const window: number = this.windowGeneration
    if (this.locateSettleTimer >= 0) clearTimeout(this.locateSettleTimer)
    this.locateSettleTimer = setTimeout(() => {
      if (!this.active || generation !== this.loadGeneration || window !== this.windowGeneration ||
        this.locateAnchorId !== target || this.highlightId !== target) return
      const index: number = this.openingFloor?.floorId === target ? 0 :
        this.replies().findIndex((floor: ForumFloor) => floor.floorId === target) + 1
      if (index <= 0 && this.openingFloor?.floorId !== target) return
      try { this.scroller.scrollToIndex(index, false, ScrollAlign.START); if (this.listOpacity === 0) this.animateLocation() } catch (e) {}
    }, 120)
  }

  private loadEarlier(): void {
    if (!this.active || this.isLoading || this.locating || this.topScrollPosted || this.windowStart <= 0 || this.loadingEarlier || this.resumePosition !== null || this.filterAuthor) return
    const generation: number = this.loadGeneration
    const window: number = this.windowGeneration
    const oldStart: number = this.windowStart
    const start: number = Math.max(0, oldStart - 50)
    this.loadingEarlier = true
    this.earlierError = ''
    this.repo.getFloors(this.holeId, start, oldStart - start).then((rows: ForumFloor[]) => {
      if (!this.active || generation !== this.loadGeneration || window !== this.windowGeneration) return
      if (rows.length === 0 || rows.some((floor: ForumFloor) => floor.holeId !== this.holeId)) throw new Error('Invalid earlier floor range')
      const known = new Set<number>(this.floors.map((floor: ForumFloor) => floor.floorId))
      const added: ForumFloor[] = rows.filter((floor: ForumFloor) => {
        if (known.has(floor.floorId)) return false
        known.add(floor.floorId)
        return true
      })
      const replies: ForumFloor[] = added.filter((floor: ForumFloor) => floor.floorId !== this.openingFloor?.floorId)
      this.floors = added.concat(this.floors)
      this.feed.floors = this.floors.slice(); this.windowStart = start
      this.visibleStart += replies.length; this.visibleEnd += replies.length
      this.floorSource.prepend(replies)
      // Native List retains the anchor and fling velocity. A scrollToIndex
      // restore here would interrupt the gesture as each range arrives.
    }).catch((e: Object) => {
      if (this.active && generation === this.loadGeneration && window === this.windowGeneration) this.earlierError = ForumRepository.describeError(e)
    }).finally(() => {
      if (generation === this.loadGeneration && window === this.windowGeneration) this.loadingEarlier = false
    })
  }

  private animatePreference(isFavorite: boolean, value: boolean): void {
    const generation: number = this.preferenceGeneration
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut, onFinish: () => {
      if (!this.active || generation !== this.preferenceGeneration) return
      this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
        if (isFavorite) this.favoriteScale = 1
        else this.subscriptionScale = 1
      })
    } }, () => {
      if (isFavorite) { this.favorite = value; this.favoriteScale = value ? 1.12 : 1 }
      else { this.subscribed = value; this.subscriptionScale = value ? 1.12 : 1 }
    })
  }

  private routeChanged(): void {
    if (!this.active || this.initialRoute.holeId < 0 || this.initialRoute.holeId === this.holeId) return
    this.saveReading()
    this.cancelResume()
    this.readingPosition = null; this.readingInitialized = false
    this.loadGeneration++
    this.preferenceGeneration++
    this.sheetGeneration++
    this.cancelSummaryPolling()
    this.summary = null; this.summaryFeedbackSent = false; this.summaryFeedbackPending = false; this.summaryFeedbackType = ''
    if (this.scrollTimer >= 0) clearTimeout(this.scrollTimer)
    if (this.highlightTimer >= 0) clearTimeout(this.highlightTimer)
    if (this.listMotionTimer >= 0) clearTimeout(this.listMotionTimer)
    this.showSheet = false
    this.listOpacity = 1; this.contentSettling = false
    this.hole = null
    this.openingFloor = null
    this.floors = []
    this.floorSource.update([])
    this.galleryFloors = null
    this.galleryOpening = null
    this.galleryImages = []
    this.replyTarget = null
    this.replyText = ''
    this.revealed = false
    this.revealedFloors = []
    this.filterAuthor = ''
    this.highlightId = 0
    this.locating = false
    this.locateError = false
    this.loadToEnd = false
    this.votingIds = []
    this.reloadAfterVotes = false
    this.preferenceReadPending = false
    this.preferenceBusy = false
    this.favoritePending = false; this.subscriptionPending = false
    this.favorite = false
    this.subscribed = false
    this.holeId = this.initialRoute.holeId
    this.navigationResume = this.initialRoute.position
    this.pendingLocate = this.navigationResume === null ? this.initialRoute.floorId : 0
    this.pendingRanking = 0
    this.scroller.scrollEdge(Edge.Top)
    this.load()
    this.loadPreferences()
  }

  aboutToDisappear(): void {
    this.cancelSummaryPolling()
    if (this.topScrollTimer >= 0) clearTimeout(this.topScrollTimer)
    this.topScrollTimer = -1; this.topScrollPosted = false
    if (this.listMotionTimer >= 0) clearTimeout(this.listMotionTimer)
    this.saveReading()
    this.cancelResume()
    this.active = false
    this.preferenceReadPending = false
    this.reloadAfterVotes = false
    this.loadGeneration++
    this.sheetGeneration++
    this.preferenceGeneration++
    if (this.scrollTimer >= 0) clearTimeout(this.scrollTimer)
    if (this.highlightTimer >= 0) clearTimeout(this.highlightTimer)
  }

  private needsReveal(): boolean {
    return this.hole !== null && ForumPresentation.isCaution(this.hole) && this.foldMode !== 'show' && !this.revealed
  }

  private replies(): ForumFloor[] {
    return ForumDetailRules.filter(this.floors, this.openingFloor?.floorId ?? 0, this.filterAuthor)
  }

  private gallery(): string[] {
    const key: string = this.foldMode + ':' + this.revealedFloors.join(',')
    if (this.galleryFloors === this.floors && this.galleryOpening === this.openingFloor && this.galleryKey === key) return this.galleryImages
    const images: string[] = []
    const floors: ForumFloor[] = this.openingFloor === null ? this.floors : [this.openingFloor].concat(this.floors)
    for (const floor of floors) {
      if (floor.deleted || (floor.fold.length > 0 && this.foldMode !== 'show' && !this.revealedFloors.includes(floor.floorId))) continue
      for (const part of ForumContentParser.parse(floor.content)) {
        if (part.kind === 'image' && !images.includes(part.source)) images.push(part.source)
      }
    }
    this.galleryFloors = this.floors
    this.galleryOpening = this.openingFloor
    this.galleryKey = key
    this.galleryImages = images
    return images
  }

  aboutToAppear(): void {
    this.active = true
    this.readingOwner = AppStorage.get<number>(ForumPreferences.USER_ID) ?? 0
    // The old port gated this on `if (params && params.postId)` while isLoading
    // started true, so a missing param spun forever, and a legitimate id of 0
    // was rejected. Check the type instead.
    if (this.initialRoute.holeId >= 0 || this.initialHoleId >= 0) {
      this.holeId = this.initialRoute.holeId >= 0 ? this.initialRoute.holeId : this.initialHoleId
      this.navigationResume = this.initialRoute.position
      this.pendingLocate = this.navigationResume !== null ? 0 :
        this.initialRoute.holeId >= 0 ? this.initialRoute.floorId : this.initialFloorId
      this.load()
      this.loadPreferences()
    } else {
      this.isLoading = false
      this.errorMessage = AppLanguage.text($r('app.string.ui_missing_post_information'), this.languageRevision)
    }
  }

  private load(): void {
    if (!this.active) return
    // Finish an optimistic row write before replacing its models and request
    // locks. Multiple refresh signals request just one subsequent read.
    if (this.votingIds.length > 0) { this.reloadAfterVotes = true; return }
    if (this.loadPendingHole === this.holeId && this.loadPendingGeneration === this.loadGeneration) return
    this.voteStates.clear()
    this.voteModels.clear()
    this.captureReading()
    const generation: number = ++this.loadGeneration
    this.loadPendingGeneration = generation; this.loadPendingHole = this.holeId
    this.locateGeneration++
    this.windowGeneration++
    this.locating = false
    this.topLocation = false; this.topScrollPosted = false
    if (this.topScrollTimer >= 0) clearTimeout(this.topScrollTimer)
    this.topScrollTimer = -1
    this.locateToBottom = false
    const captured: ForumReadingPosition | null = this.navigationResume
    this.navigationResume = null
    const resume = captured !== null && captured.holeId === this.holeId && captured.owner === this.readingOwner ?
      Promise.resolve(captured) : !this.readingInitialized && this.pendingLocate <= 0 ?
        ForumReadingProgress.read(this.readingOwner, this.holeId).catch(() => null) : Promise.resolve(null)
    this.cancelResume()
    this.windowStart = 0; this.loadingEarlier = false; this.earlierError = ''
    this.feed = new ForumFloorFeed()
    this.votingIds = []
    this.visibleEnd = -1
    this.moreError = false
    this.isLoadingMore = false
    if (!this.refreshing) this.isLoading = true
    this.errorMessage = ''
    this.verificationRequired = false
    this.repo.getHole(this.holeId).then((hole: ForumHole) => {
      if (generation !== this.loadGeneration) return [] as ForumFloor[]
      this.hole = hole
      ForumPreferences.recordVisit(hole.holeId).catch(() => {})
      this.openingFloor = hole.firstFloor
      return resume.then((position: ForumReadingPosition | null) => {
        if (generation !== this.loadGeneration) return [] as ForumFloor[]
        this.readingInitialized = true
        this.resumePosition = position; this.resumeDeadline = Date.now() + 6000
        this.windowStart = position === null ? 0 : Math.max(0, position.index - 3)
        this.feed.offset = this.windowStart
        return this.repo.getFloors(this.holeId, this.windowStart, PAGE_SIZE)
      })
    }).then((floors: ForumFloor[]) => {
      if (generation !== this.loadGeneration) return
      this.feed.append(floors, PAGE_SIZE)
      this.floors = this.feed.floors.slice()
      // Some older summaries omit 0F while paged floors still contain its
      // tombstone. Use that verified row instead of rendering an empty card
      // followed by a second 0F card.
      if (this.openingFloor === null && this.windowStart === 0 && this.floors[0]?.ranking === 1) {
        this.openingFloor = this.floors[0]
      }
      this.floorSource.update(this.replies())
      this.hasMore = this.feed.hasMore
      this.isLoading = false
      this.refreshing = false
      this.loadPendingGeneration = -1
      if (this.pendingLocate <= 0) this.animateLocation()
      this.restoreReading()
      this.continueLocate()
      if (this.loadToEnd) this.continueEnd()
      // View-count bump; failure is irrelevant to the reader.
      this.repo.markHoleRead(this.holeId).catch((e: Object) => {
        console.error('DanXi: markHoleRead failed: ' + ForumRepository.describeError(e))
      })
    }).catch((e: Object) => {
      if (generation !== this.loadGeneration) return
      this.verificationRequired = e instanceof HttpError && e.statusCode === -2
      this.listOpacity = 1; this.contentSettling = false
      this.errorMessage = this.verificationRequired ? AppLanguage.text($r('app.string.forum_webvpn_verification_hint'), this.languageRevision) :
        ForumRepository.describeError(e)
      this.isLoading = false
      this.refreshing = false
      this.loadPendingGeneration = -1
    })
  }

  private async manualReload(): Promise<void> {
    if (this.verifying || this.isLoading) return
    if (!this.verificationRequired) { this.load(); return }
    if (!FduRepository.getInstance().canLoginOnDemand()) { router.pushUrl({ url: 'pages/LoginPage' }); return }
    const generation: number = this.loadGeneration
    this.verifying = true
    try {
      await FduRepository.getInstance().verifyService(ForumRoute.LOGIN_URL)
      if (this.active && generation === this.loadGeneration) this.load()
    } catch (e) { if (this.active && generation === this.loadGeneration) this.errorMessage = ForumRepository.describeError(e) }
    finally { this.verifying = false }
  }

  private loadMore(): void {
    if (!this.active || this.locating || this.isLoading || this.refreshing || this.isLoadingMore || !this.hasMore || this.needsReveal()) {
      return
    }
    this.isLoadingMore = true
    this.moreError = false
    const generation: number = this.loadGeneration
    const window: number = this.windowGeneration
    this.repo.getFloors(this.holeId, this.feed.offset, PAGE_SIZE).then((more: ForumFloor[]) => {
      if (generation !== this.loadGeneration || window !== this.windowGeneration) return
      this.feed.append(more, PAGE_SIZE)
      this.floors = this.feed.floors.slice()
      this.floorSource.update(this.replies())
      this.hasMore = this.feed.hasMore
      this.isLoadingMore = false
      if (this.loadToEnd) this.continueEnd()
      else if (this.pendingLocate > 0) this.continueLocate()
      else this.prefetch()
    }).catch((e: Object) => {
      if (generation !== this.loadGeneration || window !== this.windowGeneration) return
      this.isLoadingMore = false
      this.moreError = true
      this.moreDiagnosticError = ForumRepository.describeError(e)
      if (this.pendingLocate > 0) { this.locating = false; this.locateError = true; this.locateDiagnosticError = this.moreDiagnosticError }
      this.loadToEnd = false
    })
  }

  private prefetch(): void {
    if (this.locating) return
    if (this.visibleStart <= 20 && !this.earlierError) this.loadEarlier()
    if (!this.moreError && shouldPrefetch(this.visibleEnd, this.replies().length + 1)) this.loadMore()
  }

  private locateFloor(floor: ForumFloor): void {
    if (floor.holeId !== this.holeId) {
      this.captureReading(); this.saveReading()
      if (this.onNavigate !== undefined) { this.onNavigate(floor.holeId, floor.floorId, this.readingPosition); return }
      router.pushUrl({ url: 'pages/ForumDetailPage', params: new HoleRouteParams(floor.holeId, floor.floorId) })
        .catch((diagnosticFailure: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.ui_could_not_open_the_quoted_post'), this.languageRevision)) })
      return
    }
    this.pendingLocate = floor.floorId
    this.pendingRanking = floor.ranking
    this.locateToBottom = false
    this.latestLocation = false
    this.cancelResume()
    this.filterAuthor = ''
    this.locateGeneration++
    this.locating = false; this.loadToEnd = false
    if (floor.floorId <= 0) { this.load(); this.scroller.scrollEdge(Edge.Top); return }
    this.floorSource.update(this.replies())
    this.continueLocate()
  }

  private continueLocate(): void {
    if (!this.active || this.pendingLocate <= 0 || this.isLoading || this.needsReveal()) return
    this.locateError = false
    const target: number = this.pendingLocate
    const replyIndex: number = this.replies().findIndex((floor: ForumFloor) => floor.floorId === target)
    const index: number = this.openingFloor?.floorId === target ? 0 : replyIndex < 0 ? -1 : replyIndex + 1
    if (index >= 0) {
      this.highlightId = target
      this.pendingLocate = 0
      this.locating = true
      this.listOpacity = 0
      const generation: number = this.loadGeneration
      const window: number = this.windowGeneration
      const location: number = this.locateGeneration
      if (this.scrollTimer >= 0) clearTimeout(this.scrollTimer)
      this.scrollTimer = setTimeout(() => {
        if (this.active && generation === this.loadGeneration && window === this.windowGeneration && location === this.locateGeneration && !this.needsReveal()) {
          try {
            // Smooth long-index scrolling lays out every intervening rich
            // floor in ArkUI. Jump directly; the destination outline supplies
            // feedback without creating those Web hosts.
            this.scroller.scrollToIndex(index, false, ScrollAlign.START)
            this.locating = false
            this.animateLocation()
            if (this.locateToBottom) { this.locateToBottom = false; this.scroller.scrollEdge(Edge.Bottom) }
            else this.locateAnchorId = target
            if (this.highlightTimer >= 0) clearTimeout(this.highlightTimer)
            this.highlightTimer = setTimeout(() => { if (this.active) this.highlightId = 0 }, 1600)
          }
          catch (e) { this.locating = false; this.listOpacity = 1; this.pendingLocate = target; this.locateError = true; this.locateDiagnosticError = ForumRepository.describeError(e as Object) }
        }
      }, 100)
    } else if (!this.locating) this.seekWindow(target === this.hole?.lastFloor?.floorId)
  }

  private cancelLocation(): void {
    this.locateGeneration++; this.pendingLocate = 0; this.pendingRanking = 0
    this.locateToBottom = false; this.locating = false; this.loadToEnd = false
    this.contentSettling = false; this.listOpacity = 1; this.highlightId = 0
    this.topLocation = false; this.topScrollPosted = false
    if (this.topScrollTimer >= 0) clearTimeout(this.topScrollTimer)
    this.topScrollTimer = -1
    this.cancelResume()
    if (this.scrollTimer >= 0) clearTimeout(this.scrollTimer)
    if (this.listMotionTimer >= 0) clearTimeout(this.listMotionTimer)
  }

  private seekWindow(latest: boolean): void {
    const hole: ForumHole | null = this.hole
    if (!this.active || hole === null || this.isLoading || this.needsReveal()) return
    this.captureReading(); this.saveReading(); this.cancelResume()
    this.locating = true; this.locateError = false
    this.latestLocation = latest
    if (this.scrollTimer >= 0) clearTimeout(this.scrollTimer)
    if (this.highlightTimer >= 0) clearTimeout(this.highlightTimer)
    this.highlightId = 0
    const generation: number = ++this.locateGeneration
    // Cancel paged reads against the previous window immediately. A canceled
    // seek leaves that window usable; no partial prefix is installed.
    const load: number = this.loadGeneration
    const window: number = ++this.windowGeneration
    this.isLoadingMore = false; this.loadingEarlier = false; this.earlierError = ''
    const current = (): boolean => this.active && generation === this.locateGeneration && load === this.loadGeneration && window === this.windowGeneration
    const target: number = this.pendingLocate
    const ranking: number = this.pendingRanking
    const resolve = async (): Promise<ForumFloorWindow> => {
      if (latest) return ForumFloorLocator.latest(this.repo, hole, current)
      let ordinal: number = ranking
      if (!(ordinal > 0)) {
        try {
          const floor: ForumFloor = await this.repo.getFloor(target)
          if (!current()) throw new Error('Obsolete floor location')
          if (floor.holeId !== hole.holeId) throw new Error('Floor belongs to another thread')
          ordinal = floor.ranking
        } catch (e) {
          // Hard-purged floors can disappear after the quote was cached. Find
          // the nearest surviving reply without losing the containing thread.
          if (!(e instanceof HttpError && e.statusCode === 404)) throw e as Error
        }
      }
      return ForumFloorLocator.locate(this.repo, hole, target, ordinal, current)
    }
    resolve().then((window: ForumFloorWindow) => {
      if (!current()) return
      this.listOpacity = 0
      this.windowStart = window.start
      this.feed = new ForumFloorFeed(); this.feed.offset = window.start
      this.feed.append(window.floors, PAGE_SIZE)
      if (latest) this.feed.hasMore = false
      this.floors = this.feed.floors.slice(); this.filterAuthor = ''
      this.floorSource.update(this.replies()); this.hasMore = this.feed.hasMore
      this.visibleEnd = -1; this.visibleStart = 0; this.moreError = false
      this.locating = false; this.loadToEnd = false
      this.locateToBottom = latest
      if (latest) this.pendingLocate = window.floors[window.floors.length - 1]?.floorId ?? 0
      else if (!window.exact) {
        this.pendingLocate = window.floors.find((floor: ForumFloor) => floor.floorId >= target)?.floorId ??
          window.floors[window.floors.length - 1]?.floorId ?? 0
        promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_this_floor_was_deleted_or_is_unavailable'), this.languageRevision) })
      }
      if (this.pendingLocate > 0) this.continueLocate()
      else this.scroller.scrollEdge(Edge.Top)
    }).catch((e: Object) => {
      if (!current()) return
      this.locating = false; this.loadToEnd = false; this.locateError = true
      this.locateDiagnosticError = ForumRepository.describeError(e)
      this.listOpacity = 1; this.contentSettling = false
      DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e))
    })
  }

  private replaceFloor(updated: ForumFloor): void {
    this.voteStates?.get(updated.floorId)?.update(updated)
    const previous: ForumFloor | null | undefined = this.openingFloor?.floorId === updated.floorId ?
      this.openingFloor : this.floors.find((floor: ForumFloor) => floor.floorId === updated.floorId)
    const structural: boolean = previous !== null && previous !== undefined &&
      (previous.content !== updated.content || previous.deleted !== updated.deleted ||
        previous.fold.join('|') !== updated.fold.join('|'))
    this.voteModels.set(updated.floorId, updated)
    // Vote counts live in the observed footer. Do not dirty the parent list or
    // its rich-text Web hosts for server timestamps changed by a vote.
    if (!structural) return
    if (structural) this.floorRenderVersions.set(updated.floorId, (this.floorRenderVersions.get(updated.floorId) ?? 0) + 1)
    if (this.openingFloor?.floorId === updated.floorId) this.openingFloor = updated
    for (let i = 0; i < this.floors.length; i++) {
      if (this.floors[i].floorId === updated.floorId) {
        const next: ForumFloor[] = this.floors.slice()
        next[i] = updated
        this.floors = next
        this.feed.floors = this.floors.slice()
        // A vote only replaces the small footer, preserving the rich Web host
        // and the list position. Structural/content changes still reload rows.
        if (structural) this.floorSource.update(this.replies())
        return
      }
    }
  }

  private toggleLike(floor: ForumFloor, up: boolean, state?: ForumVoteState): void {
    if (!this.active || floor.deleted || this.votingIds.includes(floor.floorId)) return
    this.cancelResume()
    this.votingIds = this.votingIds.concat([floor.floorId])
    const generation: number = this.loadGeneration
    const votingState: ForumVoteState | undefined = state ?? this.voteStates.get(floor.floorId)
    if (votingState !== undefined) votingState.pending = true
    // 1 = like, -1 = dislike, 0 = cancel (forum_repository.dart /floors/{id}/like/{like}).
    const target: number = up ? (floor.liked ? 0 : 1) : (floor.disliked ? 0 : -1)
    const optimistic = floor.withVote(target)
    state?.update(optimistic)
    this.replaceFloor(optimistic)
    this.repo.likeFloor(floor.floorId, target).then((updated: ForumFloor) => {
      if (this.active && generation === this.loadGeneration) { state?.update(updated); this.replaceFloor(updated) }
    }).catch((e: Object) => {
      if (!this.active || generation !== this.loadGeneration) return
      state?.update(floor)
      this.replaceFloor(floor)
      DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e))
    }).finally(() => {
      if (votingState !== undefined) votingState.pending = false
      if (this.active && generation === this.loadGeneration) {
        this.votingIds = this.votingIds.filter((id: number) => id !== floor.floorId)
        if (this.votingIds.length === 0 && this.reloadAfterVotes) { this.reloadAfterVotes = false; this.load() }
      }
    })
  }

  private sendReply(): void {
    if (this.isSending || this.isLoading || !ForumDetailRules.canReply(this.hole) || this.needsReveal()) return
    const content: string = this.replyText.trim()
    if (content.length === 0) {
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_enter_a_reply'), this.languageRevision) })
      return
    }
    const submittedText: string = this.replyText
    const targetId: number = this.replyTarget?.floorId ?? 0
    this.isSending = true
    this.repo.createFloor(this.holeId, ForumDetailRules.replyBody(content, targetId)).then(() => {
      if (!this.active) return
      this.isSending = false
      if (this.replyText === submittedText && (this.replyTarget?.floorId ?? 0) === targetId) {
        this.replyText = ''
        this.replyTarget = null
      }
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_reply_sent'), this.languageRevision) })
      // Re-read so the server-assigned pseudonym and floor id appear.
      this.loadToEnd = true
      this.load()
    }).catch((e: Object) => {
      if (!this.active) return
      this.isSending = false
      DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e))
    })
  }

  private text(label: Resource): string { return AppLanguage.text(label, this.languageRevision) }

  private loadPreferences(): void {
    if (!this.active || this.preferenceReadPending || this.preferenceBusy) return
    this.preferenceReadPending = true
    const generation: number = ++this.preferenceGeneration
    this.preferenceReady = false
    this.preferenceError = ''
    this.repo.getMe().then((user: ForumUser) => {
      if (this.active && generation === this.preferenceGeneration) this.admin = user.isAdmin
    }).catch(() => {})
    Promise.all([this.repo.getFavoriteHoleIds(), this.repo.getSubscribedHoleIds()]).then((ids: number[][]) => {
      if (!this.active || generation !== this.preferenceGeneration) return
      this.favorite = ids[0].includes(this.holeId)
      this.subscribed = ids[1].includes(this.holeId)
      this.preferenceReady = true
    }).catch((e: Object) => {
      if (this.active && generation === this.preferenceGeneration) this.preferenceError = ForumRepository.describeError(e)
    }).finally(() => {
      if (generation === this.preferenceGeneration) this.preferenceReadPending = false
    })
  }

  private async togglePreference(isFavorite: boolean): Promise<void> {
    if (!this.active) return
    if (isFavorite ? this.favoritePending : this.subscriptionPending) return
    if (!this.preferenceReady) { this.loadPreferences(); return }
    this.preferenceBusy = true
    if (isFavorite) this.favoritePending = true
    else this.subscriptionPending = true
    this.sheetError = ''
    const generation: number = this.preferenceGeneration
    const previous: boolean = isFavorite ? this.favorite : this.subscribed
    this.animatePreference(isFavorite, !previous)
    try {
      if (isFavorite) await this.repo.setFavorite(this.holeId, !previous)
      else await this.repo.setSubscription(this.holeId, !previous)
    } catch (e) {
      if (this.active && generation === this.preferenceGeneration) {
        this.animatePreference(isFavorite, previous)
        this.sheetError = ForumRepository.describeError(e)
      }
    }
    finally {
      if (this.active && generation === this.preferenceGeneration) {
        if (isFavorite) this.favoritePending = false
        else this.subscriptionPending = false
        this.preferenceBusy = this.favoritePending || this.subscriptionPending
      }
    }
  }

  private selectAuthor(author: string): void {
    this.cancelResume()
    this.filterAuthor = this.filterAuthor === author ? '' : author
    this.floorSource.update(this.replies())
    this.showSheet = false
    this.visibleEnd = 0
    this.scroller.scrollEdge(Edge.Top)
    this.prefetch()
  }

  private continueEnd(): void {
    if (!this.active || !this.loadToEnd || this.isLoading || this.locating) return
    if (this.hasMore) this.seekWindow(true)
    else {
      this.loadToEnd = false
      this.scroller.scrollEdge(Edge.Bottom)
    }
  }

  private retryLocate(): void {
    if (this.topLocation) this.returnToTop()
    else if (this.latestLocation) { this.loadToEnd = true; this.continueEnd() }
    else this.continueLocate()
  }

  private openSheet(kind: string, floor: ForumFloor | null = null): void {
    if (this.showSheet && ['hole', 'floor', 'admin'].includes(kind) && this.sheetKind === kind &&
      this.selectedFloor?.floorId === floor?.floorId) return
    this.cancelSummaryPolling()
    this.sheetGeneration++
    this.sheetKind = kind
    this.selectedFloor = floor
    this.sheetError = ''
    this.sheetBusy = false
    this.showSheet = true
  }

  private openMenu(kind: string, floor: ForumFloor | null = null): void {
    this.showSheetTransition.open(() => {
      if (this.active) this.openSheet(kind, floor)
    }, () => this.getUIContext())
  }

  private openCompose(mode: string, floor: ForumFloor | null): void {
    this.showSheetTransition.open(() => {
      if (!this.active) return
      this.composeMode = mode
      this.draft = mode === 'edit' ? floor?.content ?? '' : mode === 'reply' ? this.replyText : ''
      this.previewDraft = false
      this.composeContentHeight = 0
      this.draftSelectionStart = this.draft.length
      this.draftSelectionEnd = this.draft.length
      if (mode === 'reply' && floor !== null) this.replyTarget = floor
      this.openSheet('compose', floor)
    }, () => this.getUIContext())
  }

  private dismissSheet(action: DismissSheetAction, generation: number): void {
    // Interactive dismissal runs before the native two-way show value is
    // necessarily updated. Save first instead of waiting for onDisappear.
    if (this.active && generation === this.sheetGeneration) {
      this.cancelSummaryPolling()
      if (this.sheetKind === 'compose' && this.composeMode === 'reply') this.replyText = this.draft
      this.showSheet = false
      this.sheetGeneration++
    }
    action.dismiss()
  }

  private sheetDisappeared(generation: number): void {
    // Programmatic closes still save their reply draft. Late callbacks from
    // a previous sheet cannot invalidate or overwrite a newly opened editor.
    if (!this.active || generation !== this.sheetGeneration || this.showSheet) return
    this.cancelSummaryPolling()
    this.sheetGeneration++
    if (this.sheetKind === 'compose' && this.composeMode === 'reply') this.replyText = this.draft
  }

  private sheetOptions(): SheetOptions {
    const generation: number = this.sheetGeneration
    return {
      height: this.sheetHeight(),
      detents: this.sheetKind === 'summary' ? [SheetSize.MEDIUM, SheetSize.LARGE] : undefined,
      showClose: true,
      keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
      backgroundColor: ThemeColors.cardBg,
      onWillDismiss: (action: DismissSheetAction) => { this.dismissSheet(action, generation) },
      onDisappear: () => { this.sheetDisappeared(generation) }
    }
  }

  private insertDraft(before: string, after: string = ''): void {
    if (this.sheetBusy) return
    const start: number = Math.max(0, Math.min(this.draft.length, this.draftSelectionStart))
    const end: number = Math.max(start, Math.min(this.draft.length, this.draftSelectionEnd))
    const content: string = this.draft.substring(0, start) + before + this.draft.substring(start, end) + after + this.draft.substring(end)
    if (content.length > 2000) { this.sheetError = this.text($r('app.string.detail_content_limit')); return }
    this.draft = content
    this.draftSelectionStart = start + before.length
    this.draftSelectionEnd = end + before.length
    this.previewDraft = false
    const generation: number = this.sheetGeneration
    setTimeout(() => {
      if (!this.active || !this.showSheet || generation !== this.sheetGeneration) return
      if (this.draftSelectionStart < this.draftSelectionEnd) this.draftController.setTextSelection(this.draftSelectionStart, this.draftSelectionEnd)
      else this.draftController.caretPosition(this.draftSelectionStart)
    }, 0)
  }

  private async submitDraft(): Promise<void> {
    if (this.sheetBusy) return
    if (this.composeMode === 'feedback' && (this.summaryFeedbackSent || this.summaryFeedbackPending)) return
    const submittedText: string = this.draft
    const draft: string = submittedText.trim()
    if (!draft && this.composeMode !== 'feedback') { this.sheetError = this.text($r('app.string.detail_content_required')); return }
    if (this.composeMode === 'reply' && !ForumDetailRules.canReply(this.hole)) return
    if (this.composeMode === 'edit' && (this.selectedFloor === null || !ForumDetailRules.canEdit(this.selectedFloor, this.admin))) return
    this.sheetBusy = true
    this.sheetError = ''
    const mode: string = this.composeMode
    const submittedHole: number = this.holeId
    if (mode === 'feedback') this.summaryFeedbackPending = true
    const floorId: number = this.selectedFloor?.floorId ?? 0
    const targetId: number = this.replyTarget?.floorId ?? 0
    const generation: number = this.sheetGeneration
    try {
      if (mode === 'edit') {
        await this.repo.modifyFloor(floorId, draft)
        const updated = await this.repo.getFloor(floorId)
        if (this.active) this.replaceFloor(updated)
      } else if (mode === 'report') await this.repo.reportFloor(floorId, draft)
      else if (mode === 'feedback') {
        await this.repo.summaryFeedback(submittedHole, 'downvote', draft)
        if (this.active && submittedHole === this.holeId) { this.summaryFeedbackSent = true; this.summaryFeedbackType = 'downvote' }
      } else await this.repo.createFloor(this.holeId, ForumDetailRules.replyBody(draft, targetId))
      if (mode !== 'feedback') AppStorage.setOrCreate<number>('forum_feed_refresh', Date.now())
      if (!this.active) return
      const current: boolean = generation === this.sheetGeneration && this.showSheet &&
        this.sheetKind === 'compose' && this.composeMode === mode
      const unchanged: boolean = current && this.draft === submittedText &&
        (mode !== 'reply' || (this.replyTarget?.floorId ?? 0) === targetId)
      if (unchanged) {
        this.draft = ''
        if (mode === 'feedback') { this.openSheet('summary'); this.summaryPhase = 'ready' }
        else this.showSheet = false
      }
      if (mode === 'reply') {
        if (unchanged) { this.replyText = ''; this.replyTarget = null }
        else if (current) this.replyText = this.draft
        this.loadToEnd = true; this.load()
      }
      promptAction.showToast({ message: this.text($r('app.string.detail_operation_success')) })
    } catch (e) { if (this.active && generation === this.sheetGeneration) this.sheetError = ForumRepository.describeError(e) }
    finally {
      if (this.active && mode === 'feedback' && submittedHole === this.holeId) this.summaryFeedbackPending = false
      if (this.active && generation === this.sheetGeneration) this.sheetBusy = false
    }
  }

  private async pickImageUpload(): Promise<void> {
    if (!this.active || !this.showSheet || this.sheetBusy || this.sheetKind !== 'compose' ||
      ['report', 'feedback'].includes(this.composeMode)) return
    const generation: number = this.sheetGeneration
    const current = (): boolean => this.active && this.showSheet && generation === this.sheetGeneration &&
      this.sheetKind === 'compose'
    this.sheetBusy = true
    this.sheetError = ''
    this.imageUploadGeneration = generation
    let cache: string = ''
    try {
      // PhotoSelectOptions.maxSelectNumber/isOriginalSupported are not exposed
      // by this project's ArkUI-X SDK. The native file picker supports a single
      // original image without granting library-wide read permissions.
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 1
      options.fileSuffixFilters = ['.jpg,.jpeg,.png,.gif,.webp,.heic,.heif,.avif,.bmp']
      const images: string[] = await new picker.DocumentViewPicker(context).select(options)
      if (!current() || images.length === 0) return
      const uri: string = images[0]
      const filename: string = ForumImage.filename(uri)
      cache = context.cacheDir + '/danxi-upload-' + Date.now() + '-' + generation + '-' + filename
      // Read only the URI authorized by the user's picker action, then stream the cache file.
      const selected: fs.File = await fs.open(uri, fs.OpenMode.READ_ONLY)
      try {
        if (!current()) return
        await fs.copyFile(selected.fd, cache)
      } finally { await fs.close(selected) }
      if (!current()) return
      const source: string = await this.repo.uploadImage(cache, filename)
      if (!current()) return
      const imageText: string = (this.draft ? '\n' : '') + '![](' + source + ')\n'
      if (this.draft.length + imageText.length > 2000) {
        this.sheetError = this.text($r('app.string.detail_image_too_long'))
        return
      }
      // Append to the latest draft so typing during the upload is preserved.
      this.draft += imageText
    } catch (e) {
      if (current()) this.sheetError = this.text($r('app.string.detail_image_upload_failed'))
    } finally {
      if (cache) { try { await fs.unlink(cache) } catch (e) {} }
      if (current()) { this.sheetBusy = false; this.imageUploadGeneration = -1 }
    }
  }

  private async copyText(value: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value))
      promptAction.showToast({ message: this.text($r('app.string.detail_copied')) })
    } catch (e) { if (this.active) this.sheetError = ForumRepository.describeError(e) }
  }

  private async deleteSelected(): Promise<void> {
    const floor = this.selectedFloor
    const generation: number = this.sheetGeneration
    if (floor === null || !ForumDetailRules.canEdit(floor, this.admin) || this.sheetBusy) return
    this.sheetBusy = true
    try {
      const confirmation = await promptAction.showDialog({ title: this.text($r('app.string.detail_delete_floor')),
        message: '##' + floor.floorId + '\n' + this.text($r('app.string.detail_delete_note')),
        buttons: [{ text: this.text($r('app.string.forum_cancel')), color: '#808080' },
          { text: this.text($r('app.string.detail_delete_floor')), color: '#D83232' }] })
      if (confirmation.index !== 1 || !this.active || generation !== this.sheetGeneration) return
      await this.repo.deleteFloor(floor.floorId)
      const updated = await this.repo.getFloor(floor.floorId)
      if (this.active) { this.replaceFloor(updated); if (generation === this.sheetGeneration) this.showSheet = false }
      AppStorage.setOrCreate<number>('forum_feed_refresh', Date.now())
    } catch (e) { if (this.active && generation === this.sheetGeneration) this.sheetError = ForumRepository.describeError(e) }
    finally { if (this.active && generation === this.sheetGeneration) this.sheetBusy = false }
  }

  private async openHistory(floor: ForumFloor): Promise<void> {
    this.history = []
    this.openSheet('history', floor)
    this.sheetBusy = true
    const generation: number = this.sheetGeneration
    try {
      const data = await this.repo.getHistory(floor.floorId)
      if (this.active && generation === this.sheetGeneration) this.history = data
    } catch (e) { if (this.active && generation === this.sheetGeneration) this.sheetError = ForumRepository.describeError(e) }
    finally { if (this.active && generation === this.sheetGeneration) this.sheetBusy = false }
  }

  private async openSummary(refresh: boolean = false): Promise<void> {
    if (this.showSheet && this.sheetKind === 'summary' && (this.sheetBusy || ForumSummaryRules.waiting(this.summaryPhase))) return
    this.openSheet('summary')
    if (!refresh && ForumSummaryRules.hasContent(this.summary)) { this.summaryPhase = 'ready'; return }
    this.summaryPhase = 'loading'
    this.summaryAttempts = 0
    this.summaryDeadline = Date.now() + 120000
    await this.readSummary(this.sheetGeneration, refresh)
  }

  private cancelSummaryPolling(): void {
    if (this.summaryTimer >= 0) clearTimeout(this.summaryTimer)
    this.summaryTimer = -1
  }

  private async readSummary(generation: number, refresh: boolean): Promise<void> {
    if (!this.active || !this.showSheet || this.sheetKind !== 'summary' || generation !== this.sheetGeneration || !this.foreground) return
    if (Date.now() >= this.summaryDeadline || this.summaryAttempts >= 61) {
      this.summaryPhase = 'timeout'; this.sheetBusy = false
      this.sheetError = this.text($r('app.string.summary_timeout')) + '\n\nDetails\nAiSummaryTimeout: polling exceeded 120s / 61 attempts'
      return
    }
    this.sheetBusy = true
    this.summaryAttempts++
    const requestStartedAt: number = Date.now()
    try {
      const summary = await this.repo.getSummary(this.holeId, refresh)
      if (this.active && this.showSheet && this.sheetKind === 'summary' && generation === this.sheetGeneration) {
        this.summaryPhase = ForumSummaryRules.phase(summary)
        if (this.summaryPhase === 'ready') {
          if (this.summary?.generatedAt !== summary.generatedAt || this.summary?.traceId !== summary.traceId) {
            this.summaryFeedbackSent = false; this.summaryFeedbackType = ''
          }
          this.summary = summary
          this.sheetError = ''
        } else if (ForumSummaryRules.waiting(this.summaryPhase)) {
          // Match upstream's 2s cadence without adding the round-trip time
          // to every interval. Slow responses remain strictly sequential;
          // a short yield prevents an immediate loop. Never regenerate here.
          if (this.foreground) this.summaryTimer = setTimeout(() => {
            this.summaryTimer = -1
            this.readSummary(generation, false)
          }, Math.max(250, 2000 - Math.max(0, Date.now() - requestStartedAt)))
        } else if ((summary.code >= 2000 && summary.message) || this.summaryPhase === 'error') {
          this.sheetError = (summary.message || this.text($r('app.string.summary_error'))) +
            '\n\nDetails\nAiSummaryApiError: code=' + summary.code + (summary.traceId ? ', trace=' + summary.traceId : '')
        }
      }
    } catch (e) {
      if (this.active && this.showSheet && generation === this.sheetGeneration) {
        this.summaryPhase = e instanceof HttpError && e.statusCode === 403 ? 'permission' : 'error'
        this.sheetError = ForumRepository.describeError(e)
      }
    }
    finally { if (this.active && generation === this.sheetGeneration) this.sheetBusy = false }
  }

  private async upvoteSummary(): Promise<void> {
    if (this.sheetBusy || this.summaryFeedbackSent || this.summaryFeedbackPending) return
    const generation: number = this.sheetGeneration
    const submittedHole: number = this.holeId
    this.summaryFeedbackPending = true
    this.sheetError = ''
    try {
      await this.repo.summaryFeedback(submittedHole, 'upvote')
      if (this.active && submittedHole === this.holeId) {
        this.summaryFeedbackSent = true
        this.summaryFeedbackType = 'upvote'
        promptAction.showToast({ message: this.text($r('app.string.detail_operation_success')) })
      }
    } catch (e) { if (this.active && generation === this.sheetGeneration) this.sheetError = ForumRepository.describeError(e) }
    finally {
      if (this.active && submittedHole === this.holeId) this.summaryFeedbackPending = false
      if (this.active && generation === this.sheetGeneration) this.sheetBusy = false
    }
  }

  private summaryLocate(id: number): void {
    if (!Number.isSafeInteger(id) || id <= 0 || !this.active || !this.showSheet || this.sheetKind !== 'summary') return
    const generation: number = this.sheetGeneration
    const current = (): boolean => this.active && this.showSheet && this.sheetKind === 'summary' && generation === this.sheetGeneration
    ForumSummaryRules.resolve(this.repo, this.holeId, id, (this.hole?.reply ?? 0) + 1, current).then((floor: ForumFloor) => {
      if (this.active && this.showSheet && this.sheetKind === 'summary' && generation === this.sheetGeneration) {
        this.showSheet = false; this.locateFloor(floor)
      }
    }).catch((e: Object) => {
      if (this.active && this.showSheet && this.sheetKind === 'summary' && generation === this.sheetGeneration) {
        this.sheetError = ForumRepository.describeError(e)
      }
    })
  }

  private async hideHole(): Promise<void> {
    await ForumLocalState.hide(this.holeId)
    if (this.active) { this.showSheet = false; this.onBack() }
  }

  private shareFloor(floor: ForumFloor): string {
    return floor.anonyname + ' · ' + ForumDetailRules.timestamp(floor.timeCreated) + '\n##' + floor.floorId + '\n' +
      (floor.deleted ? this.text($r('app.string.ui_this_floor_was_deleted')) : ForumContentParser.summary(floor.content))
  }

  private exportSelection(): void {
    const floors = this.openingFloor === null ? this.floors : [this.openingFloor].concat(this.replies())
    this.copyText('#' + this.holeId + '\n\n' + floors.filter((floor: ForumFloor) => this.selectedIds.includes(floor.floorId))
      .map((floor: ForumFloor) => this.shareFloor(floor)).join('\n\n'))
  }

  private manage(action: string): void {
    if (!this.admin) return
    this.managementAction = action
    this.draft = action === 'special_tag' ? this.selectedFloor?.specialTag ?? '' : action === 'fold' ? this.selectedFloor?.fold.join('\n') ?? '' : ''
    this.sheetError = ''
    this.sheetKind = 'management'
  }

  private async submitManagement(): Promise<void> {
    if (!this.admin || this.sheetBusy) return
    const action: string = this.managementAction
    const generation: number = this.sheetGeneration
    const floorId: number = this.selectedFloor?.floorId ?? 0
    const draft: string = this.draft
    const divisionId: number = this.chosenDivision
    const tags: ForumTag[] = this.allTags.filter((tag: ForumTag) => this.tagIds.includes(tag.tagId))
    const locked: boolean = this.hole?.locked ?? false
    const frozen: boolean = this.hole?.frozen ?? false
    this.sheetBusy = true
    try {
      const confirmation = await promptAction.showDialog({ title: this.text($r('app.string.detail_admin')),
        message: action + ' · #' + this.holeId + '\n' + this.text($r('app.string.detail_admin_note')),
        buttons: [{ text: this.text($r('app.string.forum_cancel')), color: '#808080' },
          { text: this.text($r('app.string.detail_confirm')), color: '#D83232' }] })
      if (confirmation.index !== 1 || !this.active || generation !== this.sheetGeneration) return
      if (['lock', 'frozen', 'delete', 'force', 'unhidden'].includes(action)) {
        await this.repo.moderateHole(this.holeId, action, action === 'lock' ? !locked : action === 'frozen' ? !frozen : true)
      } else if (action === 'delete_floor') await this.repo.deleteFloor(floorId, draft)
      else if (action === 'tags') await this.repo.updateHoleTags(this.holeId, divisionId, tags)
      else if (action === 'pin') {
        const divisions = await this.repo.getDivisions()
        const division = divisions.find((item: ForumDivision) => item.divisionId === this.hole?.divisionId)
        if (!division) throw new Error(this.text($r('app.string.detail_missing_division')))
        const ids = division.pinned.map((hole: ForumHole) => hole.holeId)
        await this.repo.setPinned(division.divisionId, ids.includes(this.holeId) ? ids.filter((id: number) => id !== this.holeId) : ids.concat([this.holeId]))
      } else await this.repo.moderateFloor(floorId, action, draft)
      if (!this.active) return
      if (generation === this.sheetGeneration) this.showSheet = false
      AppStorage.setOrCreate<number>('forum_feed_refresh', Date.now())
      if (action === 'force' || action === 'delete') this.onBack()
      else this.load()
    } catch (e) { if (this.active && generation === this.sheetGeneration) this.sheetError = ForumRepository.describeError(e) }
    finally { if (this.active && generation === this.sheetGeneration) this.sheetBusy = false }
  }

  private async manageTags(): Promise<void> {
    this.manage('tags')
    const generation: number = this.sheetGeneration
    this.tagIds = this.hole?.tags.map((tag: ForumTag) => tag.tagId) ?? []
    this.chosenDivision = this.hole?.divisionId ?? 0
    this.sheetBusy = true
    try {
      const divisions: ForumDivision[] = await this.repo.getDivisions()
      const tags: ForumTag[] = await this.repo.getTags()
      if (this.active && generation === this.sheetGeneration) { this.divisions = divisions; this.allTags = tags }
    } catch (e) { if (this.active && generation === this.sheetGeneration) this.sheetError = ForumRepository.describeError(e) }
    finally { if (this.active && generation === this.sheetGeneration) this.sheetBusy = false }
  }

  @Builder
  SheetAction(label: Resource, action: () => void, destructive: boolean = false, enabled: boolean = true, emphasized: boolean = false) {
    Button() {
      Row({ space: 12 }) {
        SymbolGlyph(forumActionIcon(label)).fontSize(19)
          .fontColor([destructive ? ThemeColors.error : emphasized ? Color.White : ThemeColors.primary])
        Text(this.text(label)).fontSize(14).fontColor(destructive ? ThemeColors.error : emphasized ? Color.White : ThemeColors.textPrimary)
          .layoutWeight(1).textAlign(TextAlign.Start)
      }.width('100%').padding({ left: 14, right: 14 }).alignItems(VerticalAlign.Center)
    }.width('100%').height(44).borderRadius(14)
      .backgroundColor(emphasized ? ThemeColors.primary : $r('app.color.input_surface'))
      .fontColor(destructive ? ThemeColors.error : emphasized ? Color.White : ThemeColors.textPrimary).fontSize(14)
      .stateEffect(false).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
      .enabled(enabled && !this.sheetBusy).onClick(action)
  }

  @Builder
  EditorTool(label: ResourceStr, action: () => void) {
    Button(label).height(36).fontSize(14).borderRadius(12)
      .padding({ left: 12, right: 12 }).margin({ right: 8, bottom: 8 })
      .backgroundColor($r('app.color.input_surface')).fontColor(ThemeColors.primary)
      .enabled(!this.sheetBusy).onClick(action)
  }

  private isMenuSheet(): boolean {
    return this.sheetKind === 'hole' || this.sheetKind === 'floor' || this.sheetKind === 'admin'
  }

  private isNaturalSheet(): boolean {
    return this.isMenuSheet() || this.sheetKind === 'select' || this.sheetKind === 'management'
  }

  private sheetHeight(): SheetSize | number {
    return this.sheetKind === 'compose' ? this.composeSheetHeight() :
      this.sheetKind === 'summary' ? SheetSize.MEDIUM :
      this.isNaturalSheet() ? SheetSize.FIT_CONTENT : SheetSize.LARGE
  }

  private measureCompose(size: SizeOptions): void {
    if (!this.active || !this.showSheet || this.sheetKind !== 'compose') return
    const height: number = Math.ceil(Number(size.height))
    if (Number.isFinite(height) && height > 0 && this.composeContentHeight !== height) this.composeContentHeight = height
  }

  private composeSheetHeight(): number {
    // Measure the unbounded scroll content, while keeping the submit surface
    // outside that scroll. The system caps this preferred height to its viewport
    // and keyboard avoidance lets the weighted scroll yield space to the keyboard.
    // Only our root top padding (12), column gap (12) and footer (12+44+12)
    // belong in this overhead. Native sheet chrome/safe area are already added
    // by the sheet host; counting them here left an empty scroll region.
    const content: number = this.composeContentHeight > 0 ? this.composeContentHeight :
      this.composeMode === 'report' || this.composeMode === 'feedback' ? 174 : 422
    return content + 92
  }

  @Builder
  SheetBody() {
    Column({ space: 10 }) {
      if (this.sheetKind === 'hole') {
        Text('#' + this.holeId).fontColor(ThemeColors.textSecondary).fontSize(14).fontWeight(FontWeight.Medium)
          .width('100%').constraintSize({ minHeight: 40 }).padding({ right: 48 })
        if (this.preferenceError) {
          ErrorNotice({ message: this.preferenceError, controlId: 'forumdetailview-diagnostics', textSize: 12, textColor: ThemeColors.error }).width('100%')
          this.SheetAction($r('app.string.ui_retry'), () => { this.loadPreferences() })
        }
        Button() {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.star')).fontSize(19).fontColor([ThemeColors.primary])
              .scale({ x: this.favoriteScale, y: this.favoriteScale })
            Text(this.favorite ? $r('app.string.detail_unfavorite') : $r('app.string.detail_favorite')).fontSize(14)
              .fontColor(this.favorite ? ThemeColors.primary : ThemeColors.textPrimary)
          }.width('100%').padding({ left: 14, right: 14 }).alignItems(VerticalAlign.Center)
        }
          .width('100%').height(44).borderRadius(14).fontSize(14)
          .backgroundColor($r('app.color.input_surface')).fontColor(this.favorite ? ThemeColors.primary : ThemeColors.textPrimary)
          .stateEffect(false).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .enabled(!this.sheetBusy && !this.favoritePending).onClick(() => { this.togglePreference(true) })
        Button() {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.bell')).fontSize(19).fontColor([ThemeColors.primary])
              .scale({ x: this.subscriptionScale, y: this.subscriptionScale })
            Text(this.subscribed ? $r('app.string.detail_unsubscribe') : $r('app.string.detail_subscribe')).fontSize(14)
              .fontColor(this.subscribed ? ThemeColors.primary : ThemeColors.textPrimary)
          }.width('100%').padding({ left: 14, right: 14 }).alignItems(VerticalAlign.Center)
        }
          .width('100%').height(44).borderRadius(14).fontSize(14)
          .backgroundColor($r('app.color.input_surface')).fontColor(this.subscribed ? ThemeColors.primary : ThemeColors.textPrimary)
          .stateEffect(false).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .enabled(!this.sheetBusy && !this.subscriptionPending).onClick(() => { this.togglePreference(false) })
        Text($r('app.string.detail_subscription_note')).fontColor(ThemeColors.textHint).fontSize(12)
        this.SheetAction(this.filterAuthor ? $r('app.string.detail_show_all') : $r('app.string.detail_only_op'),
          () => { this.selectAuthor(this.filterAuthor ? '' : this.openingFloor?.anonyname ?? '') })
        this.SheetAction($r('app.string.detail_to_top'), () => {
          this.showSheet = false; this.returnToTop()
        })
        this.SheetAction($r('app.string.detail_to_end'), () => { this.showSheet = false; this.cancelResume(); this.loadToEnd = true; this.continueEnd() })
        this.SheetAction($r('app.string.detail_copy_hole'), () => { this.copyText('#' + this.holeId) })
        this.SheetAction($r('app.string.detail_share_post'), () => {
          this.selectedIds = this.openingFloor === null ? [] : [this.openingFloor.floorId]; this.sheetKind = 'share'
        })
        this.SheetAction($r('app.string.detail_hide'), () => { this.hideHole().catch((e: Object) => { this.sheetError = ForumRepository.describeError(e) }) })
        Text($r('app.string.detail_hide_note')).fontColor(ThemeColors.textHint).fontSize(12)
      } else if (this.sheetKind === 'floor' && this.selectedFloor !== null) {
        Text() {
          Span(this.selectedFloor.anonyname + ' · ').fontWeight(FontWeight.Bold)
            .fontColor(ForumPresentation.authorColor(this.selectedFloor.anonyname, this.darkMode))
          Span('##' + this.selectedFloor.floorId).fontColor(ThemeColors.textHint)
        }
          .width('100%').constraintSize({ minHeight: 40 }).padding({ right: 48 })
        Text(ForumDetailRules.timestamp(this.selectedFloor.timeCreated)).fontSize(12).fontColor(ThemeColors.textHint)
          .width('100%').padding({ right: 48 })
        this.SheetAction($r('app.string.detail_reply_floor'), () => { this.openCompose('reply', this.selectedFloor) }, false,
          !this.selectedFloor.deleted && ForumDetailRules.canReply(this.hole))
        this.SheetAction($r('app.string.detail_copy_content'), () => { this.copyText(ForumContentParser.summary(this.selectedFloor?.content ?? '')) })
        this.SheetAction($r('app.string.detail_select_text'), () => { this.sheetKind = 'select' })
        this.SheetAction($r('app.string.detail_copy_floor'), () => { this.copyText('##' + this.selectedFloor?.floorId) })
        this.SheetAction($r('app.string.detail_copy_time'), () => { this.copyText(ForumDetailRules.timestamp(this.selectedFloor?.timeCreated ?? '')) })
        this.SheetAction($r('app.string.detail_share_floor'), () => { if (this.selectedFloor !== null) this.copyText(this.shareFloor(this.selectedFloor)) })
        this.SheetAction(this.filterAuthor ? $r('app.string.detail_show_all') : $r('app.string.detail_only_author'),
          () => { this.selectAuthor(this.filterAuthor ? '' : this.selectedFloor?.anonyname ?? '') })
        if (this.selectedFloor.modified > 0) this.SheetAction($r('app.string.detail_history'), () => { if (this.selectedFloor !== null) this.openHistory(this.selectedFloor) })
        if (ForumDetailRules.canEdit(this.selectedFloor, this.admin)) {
          this.SheetAction($r('app.string.detail_edit'), () => { this.openCompose('edit', this.selectedFloor) })
          this.SheetAction($r('app.string.detail_delete_floor'), () => { this.deleteSelected() }, true)
        }
        this.SheetAction($r('app.string.detail_report'), () => { this.openCompose('report', this.selectedFloor) }, true, !this.selectedFloor.deleted)
        if (this.admin) this.SheetAction($r('app.string.detail_admin'), () => { this.sheetKind = 'admin' }, true)
      } else if (this.sheetKind === 'select') {
        Text(ForumContentParser.summary(this.selectedFloor?.content ?? '')).fontSize(18).fontColor(ThemeColors.textPrimary)
          .copyOption(CopyOptions.LocalDevice).width('100%').textAlign(TextAlign.Start)
          .constraintSize({ minHeight: 40 }).padding({ right: 48 })
      } else if (this.sheetKind === 'compose') {
        Text(this.composeMode === 'feedback' ? $r('app.string.summary_feedback_note') :
          this.composeMode === 'report' ? $r('app.string.detail_report_note') : $r('app.string.detail_markdown_note'))
          .fontSize(12).fontColor(ThemeColors.textSecondary).width('100%')
          .constraintSize({ minHeight: 40 }).padding({ right: 48 })
        if (this.replyTarget !== null && this.composeMode === 'reply') {
          Text() {
            SymbolSpan(getSymbolIcon('reply')).fontSize(13)
              .fontColor([ForumPresentation.authorColor(this.replyTarget.anonyname, this.darkMode)])
            Span(' ' + this.replyTarget.anonyname + ' · ')
              .fontColor(ForumPresentation.authorColor(this.replyTarget.anonyname, this.darkMode))
            Span('##' + this.replyTarget.floorId).fontColor(ThemeColors.textHint)
          }.fontSize(13).width('100%')
        }
        if (this.previewDraft && !['report', 'feedback'].includes(this.composeMode)) {
          ForumContentView({ content: this.draft, mentions: this.replyTarget === null ? [] : [this.replyTarget] })
        } else {
          TextArea({ text: this.draft, placeholder: this.text($r('app.string.ui_say_something')), controller: this.draftController })
            .constraintSize({ minHeight: 112, maxHeight: 224 }).width('100%').padding(16).fontSize(16).maxLength(2000)
            .backgroundColor($r('app.color.input_surface')).fontColor(ThemeColors.textPrimary)
            .placeholderColor(ThemeColors.textHint).onChange((value: string) => { this.draft = value })
            .onTextSelectionChange((start: number, end: number) => { this.draftSelectionStart = start; this.draftSelectionEnd = end })
        }
        if (!['report', 'feedback'].includes(this.composeMode)) {
          Flex({ wrap: FlexWrap.Wrap }) {
            this.EditorTool('B', () => { this.insertDraft('**', '**') })
            this.EditorTool('I', () => { this.insertDraft('*', '*') })
            this.EditorTool('∑', () => { this.insertDraft('$', '$') })
            this.EditorTool($r('app.string.detail_preview'), () => { this.previewDraft = !this.previewDraft })
            this.EditorTool($r('app.string.detail_image_add'), () => { this.pickImageUpload() })
          }.width('100%')
          if (this.sheetBusy && this.imageUploadGeneration === this.sheetGeneration) {
            Text($r('app.string.detail_image_uploading')).fontSize(12).fontColor(ThemeColors.textSecondary)
          }
          Grid() {
            ForEach(ForumStickers.ids(), (id: string) => {
              GridItem() { Image(ForumStickers.resource(id)).width(40).height(40).objectFit(ImageFit.Contain) }
                .onClick(() => { this.insertDraft('![](' + id + ')') })
            }, (id: string) => id)
          }.columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr').rowsGap(8).height(184).width('100%')
        }
      } else if (this.sheetKind === 'history') {
        Text($r('app.string.detail_history')).fontWeight(FontWeight.Medium)
        ForEach(this.history, (item: ForumHistory) => {
          Column({ space: 8 }) {
            Text(ForumDetailRules.timestamp(item.timeUpdated)).fontSize(12).fontColor(ThemeColors.textHint)
            ForumContentView({ content: item.content })
          }.padding(12).width('100%').backgroundColor($r('app.color.input_surface')).borderRadius(14)
        }, (item: ForumHistory, index: number) => String(index) + item.timeUpdated)
        if (!this.sheetBusy && this.history.length === 0 && !this.sheetError) Text($r('app.string.detail_no_history'))
        this.SheetAction($r('app.string.ui_retry'), () => { if (this.selectedFloor !== null) this.openHistory(this.selectedFloor) })
      } else if (this.sheetKind === 'summary') {
        ForumSummaryView({ source: this.repo, holeId: this.holeId, value: this.summary, phase: this.summaryPhase, error: this.sheetError,
          count: (this.hole?.reply ?? 0) + 1, feedbackSent: this.summaryFeedbackSent, feedbackType: this.summaryFeedbackType, feedbackPending: this.summaryFeedbackPending,
          onRetry: () => { this.openSummary(true) }, onLocate: (id: number) => { this.summaryLocate(id) },
          onHelpful: () => { this.upvoteSummary() }, onUnhelpful: () => { this.openCompose('feedback', null) },
          onCopy: (value: string) => { this.copyText(value) } })
      } else if (this.sheetKind === 'share') {
        Text($r('app.string.detail_share_note')).fontSize(12).fontColor(ThemeColors.textSecondary)
        ForEach(this.openingFloor === null ? this.replies() : [this.openingFloor].concat(this.replies()), (floor: ForumFloor) => {
          Row({ space: 10 }) {
            Checkbox().select(this.selectedIds.includes(floor.floorId)).onChange((checked: boolean) => {
              this.selectedIds = checked ? this.selectedIds.concat([floor.floorId]) : this.selectedIds.filter((id: number) => id !== floor.floorId)
            })
            Text(floor.anonyname + ' · ##' + floor.floorId + '\n' + ForumContentParser.summary(floor.content))
              .fontSize(13).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          }.width('100%').padding(8)
        }, (floor: ForumFloor) => String(floor.floorId))
        this.SheetAction($r('app.string.detail_copy_selected'), () => { this.exportSelection() }, false, this.selectedIds.length > 0)
        if (this.hasMore) this.SheetAction($r('app.string.detail_load_more'), () => { this.loadMore() }, false, !this.isLoadingMore)
      } else if (this.sheetKind === 'admin') {
        Text($r('app.string.detail_admin_note')).fontColor(ThemeColors.textSecondary).fontSize(12)
          .width('100%').constraintSize({ minHeight: 40 }).padding({ right: 48 })
        this.SheetAction($r('app.string.detail_lock'), () => { this.manage('lock') })
        this.SheetAction($r('app.string.detail_freeze'), () => { this.manage('frozen') })
        this.SheetAction($r('app.string.detail_hide_server'), () => { this.manage(this.hole?.hidden ? 'unhidden' : 'delete') }, true)
        this.SheetAction($r('app.string.detail_delete_force'), () => { this.manage('force') }, true)
        this.SheetAction($r('app.string.detail_delete_floor'), () => { this.manage('delete_floor') }, true)
        this.SheetAction($r('app.string.detail_pin'), () => { this.manage('pin') })
        this.SheetAction($r('app.string.detail_tags_division'), () => { this.manageTags() })
        this.SheetAction($r('app.string.detail_special_tag'), () => { this.manage('special_tag') })
        this.SheetAction($r('app.string.detail_fold_floor'), () => { this.manage('fold') })
        this.SheetAction($r('app.string.detail_sensitive'), () => { this.manage('sensitive'); this.draft = 'true' })
        this.SheetAction($r('app.string.detail_unmark_sensitive'), () => { this.manage('sensitive'); this.draft = 'false' })
        this.SheetAction($r('app.string.detail_penalty'), () => { this.manage('penalty') }, true)
      } else if (this.sheetKind === 'management') {
        Text($r('app.string.detail_admin_note')).fontSize(12).fontColor(ThemeColors.error)
          .width('100%').constraintSize({ minHeight: 40 }).padding({ right: 48 })
        if (this.managementAction === 'tags') {
          ForEach(this.divisions, (division: ForumDivision) => {
            Button(division.name).backgroundColor(this.chosenDivision === division.divisionId ? ThemeColors.primary : $r('app.color.input_surface'))
              .fontColor(this.chosenDivision === division.divisionId ? Color.White : ThemeColors.textPrimary)
              .onClick(() => { this.chosenDivision = division.divisionId })
          }, (division: ForumDivision) => String(division.divisionId))
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.allTags, (tag: ForumTag) => {
              Button(ForumPresentation.tagLabel(tag.name)).fontSize(12).margin(4)
                .backgroundColor(this.tagIds.includes(tag.tagId) ? ForumPresentation.tagColor(tag.name, this.darkMode) : ForumPresentation.tagBackground(tag.name, this.darkMode))
                .fontColor(this.tagIds.includes(tag.tagId) || ForumPresentation.featured(tag.name) ? Color.White : ForumPresentation.tagColor(tag.name, this.darkMode))
                .linearGradient({ direction: GradientDirection.Right, colors: ForumPresentation.featured(tag.name) ? [['#007AFF', 0], ['#009AD8', 1]] : [[Color.Transparent, 0], [Color.Transparent, 1]] }).borderRadius(8).clip(true)
                .onClick(() => { this.tagIds = this.tagIds.includes(tag.tagId) ? this.tagIds.filter((id: number) => id !== tag.tagId) : this.tagIds.concat([tag.tagId]) })
            }, (tag: ForumTag) => String(tag.tagId))
          }
        } else if (['special_tag', 'fold', 'penalty', 'delete_floor'].includes(this.managementAction)) {
          TextArea({ text: this.draft, placeholder: this.text($r('app.string.detail_reason_note')) }).height(160)
            .onChange((value: string) => { this.draft = value }).fontColor(ThemeColors.textPrimary).backgroundColor($r('app.color.input_surface'))
        }
        this.SheetAction($r('app.string.detail_confirm'), () => { this.submitManagement() }, true)
      }
      if (this.sheetBusy && this.sheetKind !== 'summary') LoadingProgress().width(28).height(28).color(ThemeColors.primary)
      if (this.sheetError && this.sheetKind !== 'summary') ErrorNotice({ message: this.sheetError, controlId: 'forumdetailview-diagnostics', textSize: 13, textColor: ThemeColors.error }).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, bottom: this.sheetKind === 'compose' ? 12 : 24 })
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => { this.measureCompose(size) })
  }

  @Builder
  SheetContents() {
    if (this.isNaturalSheet()) {
      // Natural height fits menus, selection and short confirmations. Long
      // text or tag catalogs remain scrollable within the system's height cap.
      Scroll() {
        this.SheetBody()
      }.width('100%').scrollBar(BarState.Off).align(Alignment.Top).padding({ top: 12 })
    } else {
      Column({ space: 12 }) {
        Scroll() {
          this.SheetBody()
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top)
        if (this.sheetKind === 'compose') {
          Column() {
            this.SheetAction($r('app.string.detail_submit'), () => { this.submitDraft() }, false,
              this.composeMode !== 'feedback' || (!this.summaryFeedbackPending && !this.summaryFeedbackSent), true)
            if (this.composeMode === 'feedback') {
              Button($r('app.string.forum_cancel')).width('100%').height(36).fontSize(13).fontColor(ThemeColors.textSecondary)
                .backgroundColor(Color.Transparent).stateEffect(false).enabled(!this.summaryFeedbackPending)
                .onClick(() => { this.showSheetTransition.open(() => {
                  if (this.active) { this.openSheet('summary'); this.summaryPhase = 'ready' }
                }, () => this.getUIContext()) })
            }
          }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 12 })
        }
      }.width('100%').height('100%').padding({ top: 12 })
    }
  }

  private voteState(floor: ForumFloor): ForumVoteState {
    const found = this.voteStates.get(floor.floorId)
    if (found !== undefined) return found
    const state = new ForumVoteState(this.voteModels.get(floor.floorId) ?? floor)
    this.voteStates.set(floor.floorId, state)
    while (this.voteStates.size > 200) {
      const oldest: number | undefined = this.voteStates.keys().next().value
      if (oldest !== undefined) { this.voteStates.delete(oldest); this.voteModels.delete(oldest) }
    }
    return state
  }

  @Builder
  VoteActions(floor: ForumFloor) {
    ForEach([this.voteState(floor)], (state: ForumVoteState) => {
      ForumVoteControls({ state: state, onVote: (up: boolean) => {
        const current = this.voteModels.get(floor.floorId) ?? (this.openingFloor?.floorId === floor.floorId ? this.openingFloor :
          this.floors.find((item: ForumFloor) => item.floorId === floor.floorId) ?? floor)
        const snapshot = current.withVote(0)
        snapshot.liked = state.liked; snapshot.disliked = state.disliked
        snapshot.like = state.like; snapshot.dislike = state.dislike; snapshot.deleted = state.deleted
        this.toggleLike(snapshot, up, state)
      } })
    }, (_state: ForumVoteState) => String(floor.floorId) + ':' + this.loadGeneration)
  }

  private hiddenFloor(floor: ForumFloor): boolean {
    return floor.fold.length > 0 && this.foldMode !== 'show' && !this.revealedFloors.includes(floor.floorId)
  }

  private ordinal(floor: ForumFloor): number {
    if (floor.floorId === this.openingFloor?.floorId) return 0
    if (floor.ranking > 0) return floor.ranking - 1
    const index = this.floors.findIndex((item: ForumFloor) => item.floorId === floor.floorId)
    return this.windowStart + index + (this.windowStart > 0 || this.floors[0]?.floorId === this.openingFloor?.floorId ? 0 : 1)
  }

  @Builder
  FloorBody(floor: ForumFloor, size: number = 16) {
    if (floor.deleted) {
      Text($r('app.string.ui_this_floor_was_deleted')).fontSize(14).fontColor(ThemeColors.textHint).padding(12)
    } else if (this.hiddenFloor(floor)) {
      Column({ space: 8 }) {
        Text(floor.getFoldReason()).fontColor(ThemeColors.textSecondary).fontSize(13)
        Button($r('app.string.ui_expand_content')).stateEffect(false).onClick(() => {
          this.revealedFloors = this.revealedFloors.concat([floor.floorId])
        })
      }.width('100%').padding(12)
    } else {
      ForumContentView({ content: floor.content, mentions: floor.mention, textSize: size, gallery: this.gallery(), quoteRepository: this.repo,
        onLocate: (reference: ForumFloor) => { this.locateFloor(reference) } })
    }
  }

  @Builder
  FloorHeader(floor: ForumFloor) {
    Row({ space: 6 }) {
      Row() {}.width(4).height(22).borderRadius(2)
        .backgroundColor(ForumPresentation.authorColor(floor.anonyname, this.darkMode))
      if (floor.anonyname.length > 0 && floor.anonyname === this.openingFloor?.anonyname) {
        Stack() {
          Row() {}.width(25).height(18).borderRadius(3)
            .backgroundColor(ForumPresentation.authorColor(floor.anonyname, this.darkMode))
          // Cut the glyphs out of this badge's isolated layer, revealing the floor surface.
          Text('DZ').fontSize(12).lineHeight(18).height(18).width(25).textAlign(TextAlign.Center).fontWeight(900)
            .fontColor(Color.White).padding(0)
            .blendMode(BlendMode.DST_OUT, BlendApplyType.OFFSCREEN)
            .accessibilityLevel('no')
        }.width(25).height(18)
          .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
          .accessibilityText($r('app.string.detail_op'))
          .id('floor-op-' + floor.floorId)
      }
      Text(floor.anonyname || this.text($r('app.string.ui_anonymous'))).fontSize(16).lineHeight(24)
        .fontWeight(FontWeight.Bold).fontColor(ForumPresentation.authorColor(floor.anonyname, this.darkMode)).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 140 })
      if (floor.isMe) Text($r('app.string.detail_me')).fontSize(10).fontColor(ThemeColors.textSecondary)
      if (floor.specialTag) ForumSpecialTag({ name: floor.specialTag })
      Blank()
      this.VoteActions(floor)
      Button({ type: ButtonType.Circle }) {
        MoreGlyph({ color: ThemeColors.textSecondary })
      }.width(32).height(32).padding(0).backgroundColor($r('app.color.floating_fallback')).stateEffect(false)
        .systemMaterial(adaptiveMaterial(this.materialRevision))
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
        .id('floor-more-' + floor.floorId)
        .accessibilityText(this.text($r('app.string.detail_more')) + ' ##' + floor.floorId)
        .onClick(() => { this.openMenu('floor', floor) })
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  @Builder
  FloorFooter(floor: ForumFloor) {
    Row({ space: 5 }) {
      Text(String(this.ordinal(floor)) + 'F').fontSize(11).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textSecondary)
      Text('(##' + floor.floorId + ')').fontSize(12).fontColor(ThemeColors.textHint)
      Blank()
      if (floor.modified > 0) {
        Text($r('app.string.detail_modified')).fontSize(11).fontColor(ThemeColors.primary)
          .onClick(() => { this.openHistory(floor) })
      }
      Text(AppLanguage.relativeTime(formatRelativeTime(floor.timeCreated), this.languageRevision)).fontSize(11).fontColor(ThemeColors.textHint)
    }.width('100%').alignItems(VerticalAlign.Center).margin({ top: 6 })
  }

  @Builder
  FloorCard(floor: ForumFloor) {
    Column({ space: 8 }) {
      this.FloorHeader(floor)
      this.FloorBody(floor)
      this.FloorFooter(this.floors.find((item: ForumFloor) => item.floorId === floor.floorId) ?? floor)
    }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      .borderRadius(ThemeDimens.radiusLarge)
      .outline({ width: floor.floorId === this.highlightId ? 2 : 0, color: ThemeColors.primary, radius: ThemeDimens.radiusLarge })
      .onSizeChange(() => { this.readingLayoutChanged(floor.floorId) })
      .gesture(LongPressGesture().onAction(() => { this.openMenu('floor', floor) }))
  }

  @Builder
  ReplyControls() {
    Column() {
      if (this.replyTarget !== null) {
        Row() {
          Text() {
            SymbolSpan(getSymbolIcon('reply')).fontSize(11)
              .fontColor([ForumPresentation.authorColor(this.replyTarget.anonyname, this.darkMode)])
            Span(' ' + this.replyTarget.anonyname + ' · ')
              .fontColor(ForumPresentation.authorColor(this.replyTarget.anonyname, this.darkMode))
            Span('##' + this.replyTarget.floorId).fontColor(ThemeColors.textHint)
          }.fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([$r('sys.color.font_secondary')])
          }.width(24).height(22).padding(0).backgroundColor(Color.Transparent)
            .id('thread-cancel-reply').accessibilityText($r('app.string.detail_cancel_reply'))
            .stateEffect(false).onClick(() => { this.replyTarget = null })
        }.width('100%').height(22).padding({ left: 14, right: 14 })
      }
      Row({ space: 6 }) {
        TextInput({ text: this.replyText, placeholder: this.text(ForumDetailRules.canReply(this.hole) ? $r('app.string.ui_say_something') : $r('app.string.detail_reply_unavailable')) })
          .layoutWeight(1).height(42).borderRadius(21).backgroundColor(Color.Transparent)
          .padding({ left: 10, right: 10 }).fontSize(14)
          .fontColor($r('sys.color.font_primary')).placeholderColor($r('sys.color.font_secondary'))
          .maxLength(2000).enabled(ForumDetailRules.canReply(this.hole))
          .onChange((value: string) => { this.replyText = value }).onSubmit(() => { this.sendReply() })
        Button() { SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(20).fontColor([$r('sys.color.font_primary')]) }
          .width(32).height(42).padding(0).backgroundColor(Color.Transparent).stateEffect(false)
          .accessibilityText(this.text($r('app.string.detail_full_editor')))
          .enabled(ForumDetailRules.canReply(this.hole)).onClick(() => { this.openCompose('reply', this.replyTarget) })
        Button(this.isSending ? $r('app.string.ui_sending') : $r('app.string.ui_reply'))
          .type(ButtonType.Normal).width(64).height(42).borderRadius(21).backgroundColor(ThemeColors.primary)
          .fontColor('#FFFFFF').fontSize(14).padding({ left: 8, right: 8, top: 0, bottom: 0 }).stateEffect(false)
          .enabled(!this.isSending && !this.isLoading && !this.errorMessage && !this.needsReveal() && ForumDetailRules.canReply(this.hole))
          .onClick(() => { this.sendReply() })
      // The native custom tab host already provides 4vp above and below its
      // builder. Fill its remaining height instead of overflowing with 62vp.
      }.padding({ left: 8, right: 8 }).width('100%')
        .layoutWeight(1).alignItems(VerticalAlign.Center)
    }.width('100%').height('100%').padding({ top: 6, bottom: 6 }).justifyContent(FlexAlign.Center)
  }

  build() {
    // Bottom-anchor the floating child in its parent, not via Row.align.
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .linearGradient({
          angle: 135,
          colors: [[ThemeColors.bgStart, 0], [ThemeColors.bgEnd, 1]],
          repeating: false,
        })

      Stack({ alignContent: Alignment.Top }) {
        Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        Column() {
        if (this.isLoading) {
          Column().layoutWeight(1).width('100%')
        } else if (this.errorMessage.length > 0) {
          Column() {
            Text(AppLanguage.text($r('app.string.ui_loading_failed'), this.languageRevision))
              .fontSize(ThemeDimens.textSizeTitle)
              .fontColor(ThemeColors.textSecondary)
            ErrorNotice({ message: this.errorMessage, controlId: 'forumdetailview-diagnostics', textSize: ThemeDimens.textSizeSmall, textColor: ThemeColors.textHint })
              .margin({ top: 8 })
            Button(AppLanguage.text(this.verificationRequired ? $r('app.string.campus_verify_continue') : $r('app.string.ui_retry'), this.languageRevision))
              .type(ButtonType.Normal)
              .width(140)
              .height(42)
              .borderRadius(21)
              .backgroundColor(ThemeColors.primary)
              .fontColor('#FFFFFF')
              .margin({ top: 20 })
              .enabled(!this.verifying).onClick(() => { this.manualReload() })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 32, right: 32 })
        } else if (this.needsReveal()) {
          Column({ space: 16 }) {
            Text(AppLanguage.text($r('app.string.ui_read_with_care'), this.languageRevision)).fontSize(20).fontColor(ThemeColors.error)
            Text(AppLanguage.text($r('app.string.ui_this_post_has_starred_tags_its_content_is_collap'), this.languageRevision)).fontSize(14).fontColor(ThemeColors.textSecondary)
            Button(AppLanguage.text($r('app.string.ui_view_content'), this.languageRevision)).onClick(() => {
              this.revealed = true; this.resumeDeadline = Date.now() + 6000; this.restoreReading(); this.continueLocate()
            })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 14, scroller: this.scroller }) {
            // ── opening post ──
            ListItem() {
              if (this.windowStart > 0) {
                Row({ space: 8 }) {
                  if (this.loadingEarlier) LoadingProgress().width(18).height(18).color(ThemeColors.primary)
                  if (this.earlierError) ErrorNotice({ message: this.earlierError, controlId: 'thread-earlier-diagnostics' })
                  else Text($r('app.string.detail_load_more')).fontSize(13).fontColor(ThemeColors.textSecondary)
                }.width('100%').height(40).justifyContent(FlexAlign.Center)
                  .id('thread-earlier-boundary').onClick(() => { this.loadEarlier() })
              } else {
              Column() {
                if (this.hole !== null && this.hole.tags.length > 0) {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.hole.tags, (tag: ForumTag) => {
                      ForumTagChip({ name: tag.name, onSelect: (name: string) => {
                        router.pushUrl({ url: 'pages/ForumAccountPage', params: new ForumListRouteParams('tag', name) })
                          .catch((diagnosticFailure: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.ui_retry'))) })
                      } })
                        .margin({ right: 6, bottom: 4 })
                    }, (tag: ForumTag) => String(tag.tagId) + tag.name)
                  }
                  .width('100%')
                  .margin({ bottom: 10 })
                }

                if (this.openingFloor !== null) {
                  ForEach([this.openingFloor], (floor: ForumFloor) => {
                    Column({ space: 8 }) {
                      this.FloorHeader(floor)
                      this.FloorBody(floor, 18)
                      this.FloorFooter(floor)
                    }.width('100%')
                  }, (floor: ForumFloor) => floor.floorId + ':' + (this.floorRenderVersions.get(floor.floorId) ?? 0))
                } else {
                  Text($r('app.string.ui_this_floor_was_deleted')).fontSize(14).lineHeight(22).fontColor(ThemeColors.textHint)
                }
                if (!ForumDetailRules.canReply(this.hole)) {
                  Text($r('app.string.detail_reply_unavailable')).fontSize(12).fontColor(ThemeColors.warning).margin({ top: 8 })
                }

                Row() {
                  Blank()
                  Text(this.hole !== null ? this.hole.reply + AppLanguage.text($r('app.string.ui_replies'), this.languageRevision) : '')
                    .fontSize(ThemeDimens.textSizeSmall)
                    .fontColor(ThemeColors.textHint)
                  Text(' · ' + (this.hole !== null ? this.hole.view : 0) + AppLanguage.text($r('app.string.ui_views'), this.languageRevision))
                    .fontSize(ThemeDimens.textSizeSmall)
                    .fontColor(ThemeColors.textHint)
                }
                .width('100%')
                .margin({ top: 14 })
              }
              .width('100%')
              .padding(ThemeDimens.cardInset)
              .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
              .borderRadius(ThemeDimens.radiusLarge)
              .outline({ width: this.openingFloor?.floorId === this.highlightId ? 2 : 0,
                color: ThemeColors.primary, radius: ThemeDimens.radiusLarge })
              .onSizeChange(() => { this.readingLayoutChanged(this.openingFloor?.floorId ?? 0) })
              .gesture(LongPressGesture().onAction(() => { this.openMenu('floor', this.openingFloor) }))
              }
            }

            LazyForEach(this.floorSource, (floor: ForumFloor) => {
              ListItem() {
                this.FloorCard(floor)
              }
            }, (floor: ForumFloor) => this.holeId + ':' + floor.floorId + ':' + (this.floorRenderVersions.get(floor.floorId) ?? 0))

            if (this.hasMore) {
              ListItem() {
                Row() {
                  if (this.isLoadingMore) {
                    LoadingProgress().width(22).height(22).color(ThemeColors.primary)
                  } else if (this.moreError) {
                    ErrorNotice({ message: this.moreDiagnosticError, controlId: 'thread-more-diagnostics' })
                  } else {
                    Text(this.moreError ? AppLanguage.text($r('app.string.ui_loading_failed_tap_to_retry'), this.languageRevision) : AppLanguage.text($r('app.string.ui_scroll_up_for_more_replies'), this.languageRevision))
                      .fontSize(ThemeDimens.textSizeBody)
                      .fontColor(ThemeColors.primary)
                  }
                }
                .width('100%')
                .constraintSize({ minHeight: 48 })
                .justifyContent(FlexAlign.Center)
                .onClick(() => this.loadMore())
              }
            }
            if (!this.hasMore) {
              ListItem() {
                Text(this.filterAuthor && this.replies().length === 0 ? $r('app.string.detail_filter_none') : $r('app.string.detail_all_loaded'))
                  .fontSize(12).fontColor(ThemeColors.textHint).width('100%').textAlign(TextAlign.Center).padding(16)
              }
            }
            ListItem() { Column().height(Math.max(16, px2vp(this.bottomPx)) + 90) }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })
          .contentStartOffset(this.topInset() + 72)
          .maintainVisibleContentPosition(true).cachedCount(4)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .backToTop(true)
          .scrollBar(BarState.Off)
          .onWillScroll((offset: number, _state: ScrollState, source: ScrollSource) => { return this.systemTopScroll(offset, source) })
          .onScrollIndex((start: number, end: number) => { this.visibleStart = start; this.visibleEnd = end; this.prefetch() })
          .onDidScroll(() => { this.captureReading() })
          .onScrollStop(() => { this.captureReading(); this.saveReading(); this.prefetch() })
          .onTouch((event: TouchEvent) => { if (event.type === TouchType.Down) this.cancelResume(); settleScrollTouch(this.scroller, event) })
        }

        }.width('100%').height('100%').opacity(this.listOpacity)
        }.height('100%').width('100%').onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => { this.load() })
        CenterLoadingProgress({ busy: (this.isLoading && !this.refreshing) || this.locating || this.contentSettling })
        TopFade({ extent: this.topInset() + 56 })
      FeedRefreshProgress({ topInset: this.topInset() + 84, pullOffset: this.pullOffset, refreshing: this.refreshing })
        Column() {
        // ── header ──
        Row({ space: 8 }) {
          Row() { FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48,
            onAction: () => { this.onBack() } }).width(48) }.width(104)
          Column({ space: 2 }) {
          Text(this.locating || this.loadToEnd ? AppLanguage.text($r('app.string.ui_locating_tap_to_cancel'), this.languageRevision) : this.locateError ? AppLanguage.text($r('app.string.ui_could_not_locate_tap_to_retry'), this.languageRevision) : AppLanguage.text($r('app.string.ui_post_details'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeTitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary)
            .width('100%').textAlign(TextAlign.Center).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              if (this.locating || this.loadToEnd) {
                this.cancelLocation()
              }
              else if (this.locateError) this.retryLocate()
            })
            if (this.filterAuthor) {
              Text(this.filterAuthor === this.openingFloor?.anonyname ? $r('app.string.detail_only_op') : this.filterAuthor)
                .fontSize(11).fontColor(ThemeColors.primary).maxLines(1)
                .accessibilityText(this.text($r('app.string.detail_show_all')))
                .onClick(() => { this.selectAuthor(this.filterAuthor) })
            }
            if (this.locateError) { DiagnosticLink({ message: this.locateDiagnosticError, controlId: 'thread-locate-diagnostics', controlHeight: 28 }) }
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
          Row({ space: 8 }) {
            if (this.summaryEnabled && this.hole?.aiSummaryAvailable) {
              FloatingActionButton({ label: $r('app.string.detail_summary'), icon: 'summary', labelColor: $r('app.color.ai_summary_icon'), controlHeight: 48, controlId: 'thread-summary',
                onAction: () => { this.showSheetTransition.open(() => {
                  if (this.active) this.openSummary()
                }, () => this.getUIContext()) } }).width(48)
            }
            FloatingActionButton({ label: $r('app.string.detail_more'), icon: 'more', controlHeight: 48, controlId: 'thread-more',
              onAction: () => { this.openMenu('hole') } }).width(48)
          }.width(104).justifyContent(FlexAlign.End)
        }
        .width('100%')
        .height(56)
        .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter })

        }.width('100%').padding({ top: this.topInset() }).hitTestBehavior(HitTestMode.Transparent)
      }.width('100%').height('100%')

        BottomFade({ extent: Math.max(16, px2vp(this.bottomPx)) + 12 })

        // The reply surface alone intercepts touches; surrounding content scrolls beneath it.
        FloatingSurface({ radius: this.replyTarget === null ? 31 : 42, acceptsInput: true, content: () => { this.ReplyControls() } })
        .height(this.replyTarget === null ? 62 : 84).width('92%')
        .margin({ bottom: Math.max(16, px2vp(this.bottomPx)) + 12 })
        .zIndex(2).hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showSheet, this.SheetContents(), this.showSheetTransition.options(this.showSheet, this.sheetOptions()))
  }
}
