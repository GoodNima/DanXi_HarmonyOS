import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice } from '../components/ErrorNotice'
import { ForumTagChip } from '../components/ForumTagChip'
import { ForumSpecialTag } from '../components/ForumSpecialTag'
import { settleScrollTouch } from '../common/ScrollTouch'
import { getSymbolIcon } from '../common/DanXiIcons'
import { SearchClearButton } from '../components/SearchClearButton'
import { router, promptAction } from '@kit.ArkUI'
import { Constant } from '../common/Constant'
import { AppLanguage } from '../common/AppLanguage'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { adaptiveMaterial, nativeFloatingBackground } from '../common/AdaptiveMaterial'
import { ForumRepository } from '../repository/ForumRepository'
import { ForumPreferences } from '../common/ForumPreferences'
import { SettingsRouteParams, HoleRouteParams } from '../common/RouteParams'
import { ForumFloor, ForumHole, ForumTag } from '../model/Forum'
import { ForumPunishment } from '../model/ForumAccount'
import { ForumDetailRules } from '../model/ForumDetail'
import { ForumPresentation } from '../common/ForumPresentation'
import { ForumContentView } from '../components/ForumContentView'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { TopFade } from '../components/TopFade'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { HttpError } from '../util/HttpUtil'
import { FduRepository } from '../repository/FduRepository'
import { ForumRoute } from '../common/ForumRoute'
import { ForumListRouteParams } from '../common/ForumListRoute'
import { ForumMessage } from '../model/ForumMessage'

@Entry
@Component
struct ForumAccountPage {
  private showMessageTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private touchScroller: Scroller = new Scroller()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink(Constant.KEY_FORUM_FOLD_BEHAVIOR) foldMode: string = 'fold'
  @StorageLink(ForumRepository.KEY_SESSION_REVISION) @Watch('onSessionChanged') sessionRevision: number = 0
  @StorageLink(ForumPreferences.SORT) @Watch('onOrderChanged') sortOrder: string = 'time_updated'
  @State section: string = 'posts'
  @State tags: ForumTag[] = []
  @State tagQuery: string = ''
  @State tag: string = ''
  @State messages: ForumMessage[] = []
  @State unreadOnly: boolean = false
  @State messageDetail: ForumMessage | null = null
  @State showMessage: boolean = false
  @State readError: string = ''
  @State holes: ForumHole[] = []
  @State replies: ForumFloor[] = []
  @State punishments: ForumPunishment[] = []
  @State revealed: number[] = []
  @State loading: boolean = true
  @State loadingMore: boolean = false
  @State refreshing: boolean = false
  @State hasMore: boolean = false
  @State error: string = ''
  @State verificationRequired: boolean = false
  @State verifying: boolean = false
  @State moreError: string = ''
  @State pullOffset: number = 0
  private active: boolean = false
  private generation: number = 0
  private cursor: number = Date.now()
  private pageOffset: number = 0
  private ids: number[] = []
  private collectionHoles: ForumHole[] = []
  private repo: ForumRepository = ForumRepository.getInstance()
  private scope: number = -1
  private reloadFlight: Promise<void> | null = null
  private reloadKey: string = ''
  private readingMessages: Set<string> = new Set<string>()

  aboutToAppear(): void {
    this.active = true
    const params = router.getParams() as ForumListRouteParams
    const requested = params?.section ?? 'posts'
    this.tag = params?.tag?.trim().slice(0, 128) ?? ''
    this.section = ['posts', 'replies', 'history', 'favorites', 'subscriptions', 'punishments', 'messages', 'tag', 'tags'].includes(requested) ? requested : 'posts'
    if (this.section === 'tag' && !this.tag) this.section = 'posts'
    this.reload()
  }
  aboutToDisappear(): void { this.active = false; this.generation++; this.reloadFlight = null }
  private title(): ResourceStr {
    if (this.section === 'tags') return $r('app.string.forum_all_tags')
    if (this.section === 'tag') return ForumPresentation.tagLabel(this.tag)
    if (this.section === 'messages') return $r('app.string.forum_messages')
    if (this.section === 'replies') return $r('app.string.forum_my_replies')
    if (this.section === 'history') return $r('app.string.forum_view_history')
    if (this.section === 'favorites') return $r('app.string.forum_favorites')
    if (this.section === 'subscriptions') return $r('app.string.forum_subscriptions')
    if (this.section === 'punishments') return $r('app.string.forum_punishments')
    return $r('app.string.forum_my_posts')
  }
  onSessionChanged(): void { if (this.active) { this.showMessage = false; this.reload() } }
  onOrderChanged(): void { if (this.active && this.section === 'tag') this.reload() }
  private current(version: number): boolean {
    return this.active && version === this.generation && this.scope === this.repo.sessionRevision()
  }
  private reload(): Promise<void> {
    if (!this.active) return Promise.resolve()
    const key: string = this.repo.sessionRevision() + '/' + this.section + '/' + encodeURIComponent(this.tag) +
      '/' + this.sortOrder + '/' + this.unreadOnly
    if (this.reloadFlight !== null && this.reloadKey === key) return this.reloadFlight
    this.reloadKey = key
    const task: Promise<void> = this.read()
    this.reloadFlight = task
    task.finally(() => { if (this.reloadFlight === task) this.reloadFlight = null })
    return task
  }
  private async read(): Promise<void> {
    const version = ++this.generation
    this.loading = !this.refreshing
    this.error = ''
    this.verificationRequired = false
    this.moreError = ''
    this.hasMore = false
    this.loadingMore = false
    this.pageOffset = 0
    this.cursor = Date.now()
    this.revealed = []
    this.readError = ''
    try {
      if (!await this.repo.restoreSession()) throw new Error(AppLanguage.text($r('app.string.ui_please_log_in_to_the_forum_first'), this.languageRevision))
      if (!this.active || version !== this.generation) return
      this.scope = this.repo.sessionRevision()
      if (this.section === 'history') this.ids = ForumPreferences.history()
      else if (this.section === 'favorites') {
        const favorites: ForumHole[] = await this.repo.getFavoriteHoles()
        if (!this.current(version)) return
        this.collectionHoles = favorites
      }
      else if (this.section === 'subscriptions') this.ids = await this.repo.getSubscribedHoleIds()
      if (!this.current(version)) return
      this.holes = []
      this.replies = []
      this.punishments = []
      this.messages = []
      if (this.section === 'tags') {
        const tags: ForumTag[] = await this.repo.getTags()
        if (this.current(version)) this.tags = tags.slice().sort((left: ForumTag, right: ForumTag) => right.temperature - left.temperature)
      } else await this.page(version)
    } catch (e) {
      if (this.active && version === this.generation) {
        this.verificationRequired = e instanceof HttpError && e.statusCode === -2
        this.error = ErrorDiagnostics.message(e as Object, this.verificationRequired ?
          AppLanguage.text($r('app.string.forum_webvpn_verification_hint'), this.languageRevision) : '')
      }
    } finally {
      if (this.active && version === this.generation) { this.loading = false; this.refreshing = false }
    }
  }
  private async manualReload(): Promise<void> {
    if (this.verifying || this.loading) return
    if (!this.verificationRequired) { await this.reload(); return }
    if (!FduRepository.getInstance().canLoginOnDemand()) { router.pushUrl({ url: 'pages/LoginPage' }); return }
    const scope: number = this.repo.sessionRevision()
    this.verifying = true
    try {
      await FduRepository.getInstance().verifyService(ForumRoute.LOGIN_URL)
      if (this.active && scope === this.repo.sessionRevision()) await this.reload()
    } catch (e) { if (this.active && scope === this.repo.sessionRevision()) this.error = ForumRepository.describeError(e) }
    finally { this.verifying = false }
  }
  private async page(version: number): Promise<void> {
    if (this.section === 'tag') {
      const rows = await this.repo.getDivisionHoles(this.cursor, 0, this.tag, 10, this.sortOrder)
      if (!this.current(version)) return
      const times = rows.map((hole: ForumHole) => Date.parse(this.sortOrder === 'time_created' ? hole.timeCreated : hole.timeUpdated)).filter((time: number) => Number.isFinite(time))
      const next: number = times.length > 0 ? Math.min(...times) : NaN
      this.hasMore = rows.length >= 10 && Number.isFinite(next) && next < this.cursor
      if (Number.isFinite(next)) this.cursor = next
      const known = new Set<number>(this.holes.map((hole: ForumHole) => hole.holeId))
      this.holes = this.holes.concat(rows.filter((hole: ForumHole) => !known.has(hole.holeId)))
    } else if (this.section === 'messages') {
      const rows = await this.repo.getMessages(this.unreadOnly, this.cursor)
      if (!this.current(version)) return
      const times = rows.map((row: ForumMessage) => Date.parse(row.created)).filter((time: number) => Number.isFinite(time))
      const next: number = times.length > 0 ? Math.min(...times) : NaN
      this.hasMore = rows.length >= Constant.POST_COUNT_PER_PAGE && Number.isFinite(next) && next < this.cursor
      if (Number.isFinite(next)) this.cursor = next
      const known = new Set<number>(this.messages.map((row: ForumMessage) => row.messageId))
      this.messages = this.messages.concat(rows.filter((row: ForumMessage) => row.messageId > 0 && !known.has(row.messageId)))
      // Upstream clears the global unread marker after reading a successful page.
      // Preserve the loaded row flags until each detail is opened, as upstream does.
      this.repo.clearMessages().catch((e: Object) => {
        if (this.current(version)) this.readError = ForumRepository.describeError(e)
      })
    } else if (this.section === 'punishments') {
      const rows = await this.repo.getPunishments()
      if (this.current(version)) { this.punishments = rows.map((row: Record<string, Object>) => ForumPunishment.fromJson(row)); this.hasMore = false }
    } else if (this.section === 'replies') {
      const rows = await this.repo.getMyReplies(this.pageOffset, 10)
      if (!this.current(version)) return
      this.pageOffset += rows.length
      this.hasMore = rows.length === 10
      const known = new Set<number>(this.replies.map((floor: ForumFloor) => floor.floorId))
      this.replies = this.replies.concat(rows.filter((floor: ForumFloor) => !known.has(floor.floorId)))
    } else if (this.section === 'posts') {
      const rows = await this.repo.getMyHoles(this.cursor, 10)
      if (!this.current(version)) return
      const next = rows.length > 0 ? Date.parse(rows[rows.length - 1].timeCreated) : NaN
      this.hasMore = rows.length === 10 && Number.isFinite(next) && next < this.cursor
      if (Number.isFinite(next)) this.cursor = next
      const known = new Set<number>(this.holes.map((hole: ForumHole) => hole.holeId))
      this.holes = this.holes.concat(rows.filter((hole: ForumHole) => !known.has(hole.holeId)))
    } else if (this.section === 'favorites') {
      // iOS FavoritePage preserves the full /user/favorites response order.
      // Append locally in small batches without re-reading each favorite hole.
      const batch: ForumHole[] = this.collectionHoles.slice(this.pageOffset, this.pageOffset + 10)
      this.pageOffset += batch.length
      this.holes = this.holes.concat(batch)
      this.hasMore = this.pageOffset < this.collectionHoles.length
    } else {
      const batch = this.ids.slice(this.pageOffset, this.pageOffset + 10)
      const rows: ForumHole[] = []
      // Small batches keep history/subscriptions responsive without an unbounded request burst.
      for (let index: number = 0; index < batch.length; index += 3) {
        const next = await Promise.all(batch.slice(index, index + 3).map((id: number): Promise<ForumHole | null> =>
          this.repo.getHole(id).then((hole: ForumHole): ForumHole | null => hole).catch((e: Object): ForumHole | null => {
            if (e instanceof HttpError && (e.statusCode === 404 || e.statusCode === 410)) return null
            throw e as Error
          })))
        if (!this.current(version)) return
        for (const hole of next) { if (hole !== null) rows.push(hole) }
      }
      if (!this.current(version)) return
      this.pageOffset += batch.length
      this.holes = this.holes.concat(rows)
      this.hasMore = this.pageOffset < this.ids.length
    }
  }
  private openMessage(row: ForumMessage): void {
    this.showMessageTransition.open(() => {
      if (!this.active) return
      this.messageDetail = row; this.showMessage = true
      this.readMessage(row)
    }, () => this.getUIContext())
  }
  private readMessage(row: ForumMessage): void {
    const owner: number = this.repo.sessionRevision()
    const key: string = owner + '/' + row.messageId
    if (row.read || this.readingMessages.has(key)) return
    this.readingMessages.add(key)
    this.repo.markMessageRead(row.messageId).then(() => {
      if (!this.active || owner !== this.repo.sessionRevision()) return
      row.read = true
      const current: ForumMessage | undefined = this.messages.find((item: ForumMessage) => item.messageId === row.messageId)
      if (current !== undefined) current.read = true
      this.messages = this.messages.slice()
    }).catch((e: Object) => { if (this.active && owner === this.repo.sessionRevision()) this.readError = ForumRepository.describeError(e) })
      .finally(() => { this.readingMessages.delete(key) })
  }
  private async more(): Promise<void> {
    if (!this.active || this.loading || this.refreshing || this.loadingMore || !this.hasMore) return
    const version = this.generation
    this.loadingMore = true
    this.moreError = ''
    try { await this.page(version) }
    catch (e) { if (this.current(version)) this.moreError = ForumRepository.describeError(e) }
    finally { if (this.current(version)) this.loadingMore = false }
  }
  private open(hole: number, floor: number = 0): void {
    if (hole > 0) router.pushUrl({ url: 'pages/ForumDetailPage', params: new HoleRouteParams(hole, floor) })
  }
  private clearHistory(): void {
    this.getUIContext().showAlertDialog({ title: this.title(), message: $r('app.string.forum_clear_history_hint'),
      primaryButton: { value: AppLanguage.text($r('app.string.forum_cancel'), this.languageRevision), action: () => {} },
      secondaryButton: { value: AppLanguage.text($r('app.string.forum_clear_history'), this.languageRevision), fontColor: ThemeColors.error,
        action: () => { ForumPreferences.clearHistory().then(() => { this.reload() }).catch((e: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e)) }) } } })
  }
  @Builder
  Content(floor: ForumFloor | null, hole: number, targetFloor: number = 0) {
    if (floor !== null && floor.fold.length > 0 && this.foldMode !== 'show' && !this.revealed.includes(floor.floorId)) {
      Text($r('app.string.ui_read_with_care_content_collapsed_tap_to_expand')).fontSize(14).fontColor(ThemeColors.textSecondary)
        .padding({ top: 8, bottom: 8 }).onClick(() => { this.revealed = this.revealed.concat([floor.floorId]) })
    } else {
      ForumContentView({ content: floor?.content ?? '', mentions: floor?.mention ?? [], preview: true,
        onPreviewOpen: () => { this.open(hole, targetFloor) } })
    }
    Row({ space: 8 }) {
      Text(floor?.anonyname ?? '').fontSize(12).fontColor(ForumPresentation.authorColor(floor?.anonyname ?? '', this.darkMode))
      Text(AppLanguage.relativeTime(floor?.getDisplayTime() ?? '', this.languageRevision)).fontSize(12).fontColor(ThemeColors.textHint)
      Blank()
      Text('#' + hole).fontSize(12).fontColor(ThemeColors.textSecondary)
    }.width('100%').margin({ top: 10 })
  }
  private metadataWidth(hole: ForumHole): number {
    const special: string = hole.firstFloor?.specialTag ?? ''
    const deleted: string = hole.timeDeleted ? AppLanguage.text($r('app.string.ui_this_floor_was_deleted'), this.languageRevision) : ''
    const widths: number[] = []
    const scale: number = Math.max(1, AppStorage.get<number>('app_font_scale') ?? 1)
    if (special) widths.push((Math.min(12, ForumPresentation.tagLabel(special).length) * 11 + 14) * scale)
    if (deleted) widths.push((Math.min(12, deleted.length) * 11 + 14) * scale)
    
    return Math.min(190, widths.reduce((sum: number, width: number) => sum + width, 0) + Math.max(0, widths.length - 1) * 6)
  }

  @Builder
  HoleCard(hole: ForumHole) {
    Column() {
      if (hole.tags.length > 0 || (hole.firstFloor?.specialTag.length ?? 0) > 0 || hole.timeDeleted.length > 0 ) {
        Row({ space: 8 }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(hole.tags, (tag: ForumTag) => {
              ForumTagChip({ name: tag.name, onSelect: (name: string) => { router.pushUrl({ url: 'pages/ForumAccountPage', params: new ForumListRouteParams('tag', name) }) } })
                .margin({ right: 6, bottom: 4 })
            }, (tag: ForumTag) => String(tag.tagId) + tag.name)
          }.layoutWeight(1)
          Row({ space: 6 }) {
            if (hole.firstFloor?.specialTag) ForumSpecialTag({ name: hole.firstFloor?.specialTag ?? '' })
            if (hole.timeDeleted) ForumSpecialTag({ name: AppLanguage.text($r('app.string.ui_this_floor_was_deleted'), this.languageRevision) })
            
          }.width(this.metadataWidth(hole)).justifyContent(FlexAlign.End).alignItems(VerticalAlign.Center)
        }.width('100%').justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Top).margin({ bottom: 8 })
      }

      this.Content(hole.firstFloor, hole.holeId)
    }.width('100%').padding(16).borderRadius(20)
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      .onClick(() => { this.open(hole.holeId) })
  }
  @Builder
  MessageCard(item: ForumMessage) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (!item.read) { Circle().width(6).height(6).fill(ThemeColors.primary) }
        Text(item.title || AppLanguage.text($r('app.string.forum_messages'), this.languageRevision)).fontSize(15).lineHeight(22)
          .fontWeight(item.read ? FontWeight.Regular : FontWeight.Medium).fontColor(item.read ? ThemeColors.textPrimary : ThemeColors.primary).layoutWeight(1)
      }.width('100%')
      if (item.floor !== null) { Text(item.floor.anonyname + ' · ' + item.floor.floorId).fontSize(12).fontColor(ThemeColors.textSecondary).width('100%') }
      Text(AppLanguage.relativeTime(item.created, this.languageRevision)).fontSize(12).fontColor(ThemeColors.textHint).width('100%')
    }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      .onClick(() => { this.openMessage(item) })
  }
  @Builder
  MessageDetail() {
    Column({ space: 12 }) {
      Text(this.messageDetail?.title || AppLanguage.text($r('app.string.forum_messages'), this.languageRevision))
        .fontSize(17).lineHeight(24).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%').padding({ right: 40 })
      Scroll() {
        Column({ space: 12 }) {
          if (this.messageDetail?.reportReason) { Text(this.messageDetail.reportReason).fontSize(13).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%') }
          if (this.messageDetail?.floor !== null && this.messageDetail?.floor !== undefined) {
            ForumContentView({ content: this.messageDetail.floor.content, mentions: this.messageDetail.floor.mention, onLocate: (floor: ForumFloor) => {
              this.showMessage = false; this.open(floor.holeId, floor.floorId)
            } })
          } else {
            ForumContentView({ content: this.messageDetail?.description || AppLanguage.text($r('app.string.forum_message_no_detail'), this.languageRevision) })
          }
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 420 }).scrollBar(BarState.Off)
      if (this.messageDetail?.floor !== null && this.messageDetail?.floor !== undefined) {
        FloatingActionButton({ label: $r('app.string.ui_go_to_quoted_floor'), onAction: () => {
          const floor = this.messageDetail?.floor
          this.showMessage = false
          if (floor !== null && floor !== undefined) this.open(floor.holeId, floor.floorId)
        } }).width('100%')
      }
    }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: Math.max(16, px2vp(this.bottomPx)) + 12 })
  }
  private visibleTags(): ForumTag[] {
    const query: string = this.tagQuery.trim().toLowerCase()
    return this.tags.filter((tag: ForumTag) => query ? tag.name.toLowerCase().includes(query) : tag.temperature >= 10)
  }
  @Builder
  TagsSearch() {
    Row({ space: 8 }) {
      SymbolGlyph(getSymbolIcon('search')).fontSize(18).fontColor([ThemeColors.textHint])
      TextInput({ text: this.tagQuery, placeholder: AppLanguage.text($r('app.string.forum_tags_search'), this.languageRevision) })
        .id('forum-tags-input')
        .layoutWeight(1).height(42).fontSize(14).fontColor(ThemeColors.textPrimary).backgroundColor(Color.Transparent)
        .cancelButton({ style: CancelButtonStyle.INVISIBLE }).onChange((value: string) => { this.tagQuery = value })
      if (this.tagQuery.length > 0) SearchClearButton({ controlId: 'forum-tags-clear', onClear: () => { this.tagQuery = '' } })
    }.width('100%').padding({ left: 14, right: 14 }).borderRadius(22).backgroundColor($r('app.color.input_surface'))
  }
  @Builder
  TagRow(tag: ForumTag) {
    Row({ space: 10 }) {
      SymbolGlyph(getSymbolIcon('tag')).fontSize(18).fontColor([ForumPresentation.tagColor(tag.name, this.darkMode)])
      Text(tag.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ForumPresentation.tagColor(tag.name, this.darkMode)).layoutWeight(1)
      Text(AppLanguage.text($r('app.string.forum_tag_popularity'), this.languageRevision, tag.temperature))
        .fontSize(12).fontColor(ThemeColors.textHint)
    }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
      .onClick(() => { router.pushUrl({ url: 'pages/ForumAccountPage', params: new ForumListRouteParams('tag', tag.name) }) })
  }
  @Builder
  ReplyCard(floor: ForumFloor) {
    Column() {
      Text('##' + floor.floorId).fontSize(12).fontColor(ThemeColors.primary).width('100%').margin({ bottom: 8 })
      this.Content(floor, floor.holeId, floor.floorId)
    }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.surface_fallback'))
      .onClick(() => { this.open(floor.holeId, floor.floorId) })
  }
  @Builder
  PunishmentCard(item: ForumPunishment) {
    Column({ space: 8 }) {
      Text(item.reason || AppLanguage.text($r('app.string.forum_punishments'), this.languageRevision)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.error).width('100%')
      Text(ForumDetailRules.timestamp(item.start) + ' → ' + ForumDetailRules.timestamp(item.end)).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
      if (item.deleted.length > 0) { Text($r('app.string.forum_punishment_revoked')).fontSize(12).fontColor(ThemeColors.primary).width('100%') }
      if (item.floor !== null) this.Content(item.floor, item.floor.holeId, item.floor.floorId)
      else if (item.floorId > 0) { Text('##' + item.floorId).fontSize(12).fontColor(ThemeColors.textHint).width('100%') }
    }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.surface_fallback'))
      .onClick(() => { if (item.floor !== null) this.open(item.floor.holeId, item.floor.floorId) })
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        List({ space: 12, scroller: this.touchScroller }) {
          if (this.section === 'tags') { ListItem() { this.TagsSearch() } }
          if (this.loading) { ListItem() { LoadingProgress().width(32).height(32).margin({ top: 24 }) } }
          else if (this.error) {
            ListItem() { Column({ space: 12 }) {
              ErrorNotice({ message: this.error, controlId: 'forumaccountpage-diagnostics', textSize: 14, textColor: ThemeColors.error }).width('100%')
              FloatingActionButton({ label: this.verificationRequired ? $r('app.string.campus_verify_continue') : $r('app.string.ui_retry'),
                actionEnabled: !this.verifying, onAction: () => { this.manualReload() } }).width(160)
            }.width('100%').padding(24) }
          } else {
            if (this.readError) { ListItem() { ErrorNotice({ message: this.readError,
              summary: AppLanguage.text($r('app.string.forum_message_ack_failed'), this.languageRevision), controlId: 'forum-message-diagnostics' }).padding(12) } }
            if (this.section === 'tags') {
              ForEach(this.visibleTags(), (tag: ForumTag) => { ListItem() { this.TagRow(tag) } }, (tag: ForumTag) => String(tag.tagId) + tag.name)
            }
            ForEach(this.holes, (hole: ForumHole) => { ListItem() { this.HoleCard(hole) } }, (hole: ForumHole) => String(hole.holeId))
            ForEach(this.replies, (floor: ForumFloor) => { ListItem() { this.ReplyCard(floor) } }, (floor: ForumFloor) => String(floor.floorId))
            ForEach(this.punishments, (item: ForumPunishment) => { ListItem() { this.PunishmentCard(item) } }, (item: ForumPunishment) => String(item.id))
            ForEach(this.messages, (item: ForumMessage) => { ListItem() { this.MessageCard(item) } }, (item: ForumMessage) => String(item.messageId) + ':' + String(item.read))
            if (this.holes.length + this.replies.length + this.punishments.length + this.messages.length + (this.section === 'tags' ? this.visibleTags().length : 0) === 0) {
              ListItem() { Text($r('app.string.forum_account_empty')).fontSize(14).fontColor(ThemeColors.textSecondary).width('100%').textAlign(TextAlign.Center).padding(32) }
            }
            if (this.hasMore) {
              ListItem() {
                Row({ space: 8 }) {
                  if (this.loadingMore) { LoadingProgress().width(20).height(20) }
                  if (this.moreError) { ErrorNotice({ message: this.moreError, controlId: 'forum-account-more-diagnostics' }).padding({ left: 12, right: 12 }) }
                  else Text(AppLanguage.text(this.loadingMore ? $r('app.string.ui_loading') : $r('app.string.ui_scroll_up_to_load_more'), this.languageRevision))
                    .fontSize(13).fontColor(ThemeColors.textSecondary)
                }.width('100%').constraintSize({ minHeight: 48 }).justifyContent(FlexAlign.Center).onClick(() => { this.more() })
              }
            }
          }
          ListItem() { Column() {}.width('100%').height(Math.max(16, px2vp(this.bottomPx)) + 24) }
        }.width('100%').height('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter }).contentStartOffset(px2vp(this.topPx) + 76)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) })
          .onScrollIndex((_start: number, end: number) => { if (!this.moreError && end >= this.holes.length + this.replies.length + this.messages.length - 3) this.more() })
      }.width('100%').height('100%').onRefreshing(() => { this.reload() }).onOffsetChange((offset: number) => { this.pullOffset = offset })
      TopFade({ extent: px2vp(this.topPx) + 56 })
      FeedRefreshProgress({ topInset: px2vp(this.topPx) + 88, pullOffset: this.pullOffset, refreshing: this.refreshing })
      Column() {
        Row() {
          Row() { FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48, onAction: () => { router.back() } }).width(48) }.width(72)
          Text(this.title()).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
          if (this.section === 'history') {
            FloatingActionButton({ label: $r('app.string.forum_clear_history'), onAction: () => { this.clearHistory() } }).width(72)
          } else if (this.section === 'messages') {
            FloatingActionButton({ label: this.unreadOnly ? $r('app.string.ui_all') : $r('app.string.forum_show_unread'), controlHeight: 36,
              onAction: () => { this.unreadOnly = !this.unreadOnly; this.reload() } }).width(72)
          } else { Blank().width(72) }
        }.width('100%').height(56).padding({ left: 20, right: 20 })
      }.width('100%').padding({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgEnd)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showMessage, this.MessageDetail(), this.showMessageTransition.options(this.showMessage, { height: SheetSize.FIT_CONTENT, showClose: true, dragBar: true,
        backgroundColor: nativeFloatingBackground(this.materialRevision), systemMaterial: adaptiveMaterial(this.materialRevision) }))
  }
}
