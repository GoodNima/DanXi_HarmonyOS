import { ReadableText } from '../common/ReadableText'
import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice } from '../components/ErrorNotice'
import { settleScrollTouch } from '../common/ScrollTouch'
import { ForumPresentation } from '../common/ForumPresentation'
import { AppLanguage } from '../common/AppLanguage'
import { SearchClearButton } from '../components/SearchClearButton'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { adaptiveMaterial, nativeFloatingBackground } from '../common/AdaptiveMaterial'
import { TopFade } from '../components/TopFade'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { picker, fileIo as fs } from '@kit.CoreFileKit'
import { Constant } from '../common/Constant'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { getSymbolIcon } from '../common/DanXiIcons'
import { ForumRepository } from '../repository/ForumRepository'
import { ForumLocalState } from '../common/ForumLocalState'
import { ForumPreferences } from '../common/ForumPreferences'
import { BrowserLink } from '../common/BrowserLink'
import { SettingsRouteParams } from '../common/RouteParams'
import { ForumTag } from '../model/Forum'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { ForumImageCache } from '../util/ForumImageCache'
import { AnnouncementConfig } from '../common/AnnouncementConfig'

@Entry
@Component
export struct ForumSettingsPage {
  private tagsSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  private touchScroller: Scroller = new Scroller()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink(Constant.KEY_FORUM_FOLD_BEHAVIOR) mode: string = 'fold'
  @StorageLink(Constant.KEY_FORUM_LOGGED_IN) loggedIn: boolean = false
  @StorageLink(ForumPreferences.USER_ID) userId: number = 0
  @StorageLink(ForumPreferences.SUMMARY) summaryEnabled: boolean = true
  @StorageLink(ForumPreferences.CLEAN) cleanEnabled: boolean = false
  @StorageLink(ForumPreferences.ACTIVITIES) activitiesEnabled: boolean = true
  @StorageLink(AnnouncementConfig.KEY_REVISION) activitiesRevision: number = 0
  @StorageLink(ForumPreferences.SORT) order: string = 'time_updated'
  @StorageLink(ForumPreferences.HIDDEN_TAGS) tagsJson: string = '[]'
  @StorageLink(ForumPreferences.BACKGROUND) backgroundSource: string = ''
  @StorageLink(ForumRepository.KEY_SESSION_REVISION) @Watch('sessionChanged') sessionRevision: number = 0
  @State loading: boolean = true
  @State saving: boolean = false
  @State error: string = ''
  @State refreshing: boolean = false
  @State private pullOffset: number = 0
  @State tagsSheet: boolean = false
  @State tagsDraft: string[] = []
  @State tagQuery: string = ''
  @State suggestions: ForumTag[] = []
  @State tagsLoading: boolean = false
  private repo: ForumRepository = ForumRepository.getInstance()
  private active: boolean = false
  private loadVersion: number = 0
  private loadFlight: Promise<void> | null = null
  private loadScope: number = -1
  private checkedScope: number = -1
  private checkedAt: number = 0

  aboutToAppear(): void { this.active = true; this.load(); AnnouncementConfig.load().catch(() => {}) }
  onPageShow(): void { this.active = true; this.load() }
  onPageHide(): void { this.active = false; this.loadVersion++; this.loadFlight = null; this.refreshing = false }
  aboutToDisappear(): void { this.onPageHide() }
  sessionChanged(): void { if (this.active) this.load() }
  private load(force: boolean = false): Promise<void> {
    if (!this.active) return Promise.resolve()
    const scope: number = this.repo.sessionRevision()
    if (this.loadFlight !== null && this.loadScope === scope) return this.loadFlight
    // Login/ID are reactive local state. Settings return and profile publication
    // must not poll /users/me or repeat a failed read every time the page shows.
    if (!force && this.checkedScope === scope && Date.now() - this.checkedAt < 300000) {
      this.loading = false; this.refreshing = false
      return Promise.resolve()
    }
    this.loadScope = scope
    const task: Promise<void> = this.read(force)
    this.loadFlight = task
    task.finally(() => { if (this.loadFlight === task) this.loadFlight = null })
    return task
  }
  private async read(force: boolean = false): Promise<void> {
    const version: number = ++this.loadVersion
    this.loading = true
    this.error = ''
    try {
      await this.repo.restoreSession()
      if (!this.active || version !== this.loadVersion) return
      this.checkedScope = this.repo.sessionRevision(); this.checkedAt = Date.now()
      // Repository alone publishes identity. An earlier restore return value must
      // never write this StorageLink over a login/logout from another page.
      if (this.repo.isLoggedIn()) await this.repo.getMe(force)
    } catch (e) {
      if (this.active && version === this.loadVersion) this.error = ForumRepository.describeError(e)
    } finally {
      if (this.active && version === this.loadVersion) { this.loading = false; this.refreshing = false }
    }
  }
  private status(): string {
    return this.loggedIn ? (this.userId > 0 ? AppLanguage.text($r('app.string.forum_account_id'), this.languageRevision, this.userId) :
      AppLanguage.text($r('app.string.forum_signed_in'), this.languageRevision)) : AppLanguage.text($r('app.string.forum_signed_out'), this.languageRevision)
  }
  private async select(mode: string): Promise<void> {
    if (this.saving || this.loading || !this.loggedIn || mode === this.mode) return
    this.saving = true
    try { await this.repo.setFoldBehavior(mode); AppStorage.setOrCreate<number>('forum_feed_refresh', Date.now()) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e)) }
    finally { this.saving = false }
  }
  private async setBoolean(key: string, value: boolean): Promise<void> {
    if (this.saving) return
    this.saving = true
    try {
      await PreferencesUtil.getInstance().putBoolean(key, value)
      AppStorage.setOrCreate<boolean>(key, value)
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.profile_save_failed'))) }
    finally { this.saving = false }
  }
  private async setOrder(value: string): Promise<void> {
    if (this.saving || value === this.order) return
    this.saving = true
    try { await ForumPreferences.write(ForumPreferences.SORT, value) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.profile_save_failed'))) }
    finally { this.saving = false }
  }
  private openTags(): void {
    this.tagsSheetTransition.open(() => { if (this.active) this.loadTags() }, () => this.getUIContext())
  }
  private async loadTags(): Promise<void> {
    if (this.tagsLoading) { this.tagsSheet = true; return }
    this.tagsDraft = ForumPreferences.hiddenTags()
    this.tagQuery = ''
    this.tagsSheet = true
    this.tagsLoading = true
    try { this.suggestions = await this.repo.getTags() }
    catch (e) { this.suggestions = [] }
    finally { this.tagsLoading = false }
  }
  private toggleTag(name: string): void {
    if (this.tagsDraft.includes(name)) this.tagsDraft = this.tagsDraft.filter((item: string) => item !== name)
    else if (this.tagsDraft.length < 128) this.tagsDraft = this.tagsDraft.concat([name])
  }
  private async saveTags(): Promise<void> {
    if (this.saving) return
    this.saving = true
    try { await ForumPreferences.setTags(this.tagsDraft); this.tagsSheet = false }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.profile_save_failed'))) }
    finally { this.saving = false }
  }
  private async pickBackground(): Promise<void> {
    if (this.saving) return
    this.saving = true
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    let created: string = ''
    try {
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 1
      options.fileSuffixFilters = ['.jpg,.jpeg,.png,.webp']
      const selected: string[] = await new picker.DocumentViewPicker(context).select(options)
      if (!this.active || selected.length === 0) return
      const file: fs.File = await fs.open(selected[0], fs.OpenMode.READ_ONLY)
      try {
        if ((await fs.stat(file.fd)).size > 20 * 1024 * 1024) throw new Error(AppLanguage.text($r('app.string.forum_background_limit'), this.languageRevision))
        created = context.filesDir + '/danxi-forum-background-' + Date.now()
        await fs.copyFile(file.fd, created)
      } finally { await fs.close(file) }
      const old = this.backgroundSource
      await ForumPreferences.write(ForumPreferences.BACKGROUND, 'file://' + created)
      created = ''
      await this.removeOwnedBackground(old, context.filesDir)
    } catch (e) {
      DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e))
    } finally {
      if (created) { try { await fs.unlink(created) } catch (e) {} }
      this.saving = false
    }
  }
  private async removeOwnedBackground(source: string, filesDir: string): Promise<void> {
    const prefix: string = 'file://' + filesDir + '/'
    if (!source.startsWith(prefix) || !/^danxi-forum-background-\d+$/.test(source.substring(prefix.length))) return
    try { await fs.unlink(source.substring(7)) } catch (e) {}
  }
  private async clearBackground(): Promise<void> {
    if (this.saving) return
    this.saving = true
    try {
      const old = this.backgroundSource
      await ForumPreferences.write(ForumPreferences.BACKGROUND, '')
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await this.removeOwnedBackground(old, context.filesDir)
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.profile_save_failed'))) }
    finally { this.saving = false }
  }
  private async clearCache(): Promise<void> {
    if (this.saving) return
    this.saving = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await ForumImageCache.clearCompleted(context.cacheDir)
      promptAction.showToast({ message: $r('app.string.forum_cache_cleared') })
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e)) }
    finally { this.saving = false }
  }
  private async password(): Promise<void> {
    try { await BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, 'https://auth.fduhole.com/register?type=forget_password') }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.ui_retry'))) }
  }
  private list(section: string): void { router.pushUrl({ url: 'pages/ForumAccountPage', params: new SettingsRouteParams(section) }) }
  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({ title: $r('app.string.ui_log_out'), message: $r('app.string.forum_logout_hint'),
      primaryButton: { value: AppLanguage.text($r('app.string.forum_cancel'), this.languageRevision), action: () => {} },
      secondaryButton: { value: AppLanguage.text($r('app.string.ui_log_out'), this.languageRevision), fontColor: ThemeColors.error,
        action: () => { this.repo.forgetSession().catch((e: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e)) }) } } })
  }
  @Builder
  FoldNote() {
    Column() {
      Text(ReadableText.resource($r('app.string.caution_choice_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
    }.width(248).padding({ left: 8, right: 8, top: 8, bottom: 8 }).alignItems(HorizontalAlign.Start)
  }
  @Builder
  FoldMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.caution_fold'), labelInfo: $r('app.string.caution_fold_hint') }).selected(this.mode === 'fold').selectIcon(true).onClick(() => { this.select('fold') })
        MenuItem({ content: $r('app.string.caution_hide'), labelInfo: $r('app.string.caution_hide_hint') }).selected(this.mode === 'hide').selectIcon(true).onClick(() => { this.select('hide') })
        MenuItem({ content: $r('app.string.caution_show'), labelInfo: $r('app.string.caution_show_hint') }).selected(this.mode === 'show').selectIcon(true).onClick(() => { this.select('show') })
      }
      MenuItem(() => { this.FoldNote() }).enabled(false)
    }.width(280)
  }
  @Builder
  SortMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.forum_sort_replied') }).selected(this.order === 'time_updated').selectIcon(true).onClick(() => { this.setOrder('time_updated') })
      MenuItem({ content: $r('app.string.forum_sort_created') }).selected(this.order === 'time_created').selectIcon(true).onClick(() => { this.setOrder('time_created') })
    }.width(240)
  }
  @Builder
  RowContents(icon: string, label: Resource, detail: () => ResourceStr) {
    SymbolGlyph(getSymbolIcon(icon)).fontSize(22).fontColor([ThemeColors.primary])
    Column({ space: 4 }) {
      Text(label).fontSize(15).fontColor(ThemeColors.textPrimary)
      if (detail() !== '') { Text(detail()).fontSize(12).lineHeight(17).fontColor(ThemeColors.textSecondary) }
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }
  @Builder
  Action(icon: string, label: Resource, detail: () => ResourceStr, action: () => void) {
    Row({ space: 12 }) {
      this.RowContents(icon, label, detail)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([ThemeColors.textHint])
    }
      .padding(16).width('100%').onClick(action).enabled(!this.saving)
  }
  @Builder
  Switch(icon: string, label: Resource, detail: Resource, key: string, value: () => boolean) {
    Row({ space: 12 }) {
      this.RowContents(icon, label, () => detail)
      Toggle({ type: ToggleType.Switch, isOn: value() }).enabled(!this.saving).onChange((next: boolean) => { this.setBoolean(key, next) })
    }.padding(16).width('100%')
  }
  @Builder
  GroupTitle(title: Resource) { Text(title).fontSize(13).fontColor(ThemeColors.textSecondary).width('100%').margin({ top: 8 }) }
  @Builder
  TagOption(name: string, removable: boolean) {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 6 }) {
        Text(ForumPresentation.tagLabel(name)).fontSize(12)
          .fontColor(ForumPresentation.featured(name) ? Color.White : ForumPresentation.tagColor(name, this.darkMode))
        if (removable) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(12)
            .fontColor([ForumPresentation.featured(name) ? Color.White : ForumPresentation.tagColor(name, this.darkMode)])
        }
      }.alignItems(VerticalAlign.Center).hitTestBehavior(HitTestMode.None)
    }.height(32).padding({ left: 12, right: 12 })
      .backgroundColor(ForumPresentation.tagBackground(name, this.darkMode))
      .linearGradient({ direction: GradientDirection.Right, colors: ForumPresentation.featured(name) ? [['#007AFF', 0], ['#009AD8', 1]] : [[Color.Transparent, 0], [Color.Transparent, 1]] })
      .borderRadius(8).clip(true).margin({ right: 6, bottom: 6 })
      .id((removable ? 'hidden-tag-remove-' : 'hidden-tag-add-') + name)
      .accessibilityText(removable ? AppLanguage.text($r('app.string.forum_remove_hidden_tag'), this.languageRevision, ForumPresentation.tagLabel(name)) : ForumPresentation.tagLabel(name))
      .onClick(() => { this.toggleTag(name) })
  }
  @Builder
  TagsSheet() {
    Column({ space: 12 }) {
      Text(ReadableText.resource($r('app.string.forum_hidden_tags_hint'))).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
      Row({ space: 8 }) {
        TextInput({ text: this.tagQuery, placeholder: $r('app.string.forum_tag_search') }).layoutWeight(1).height(44)
          .cancelButton({ style: CancelButtonStyle.INVISIBLE }).id('hidden-tag-input')
          .fontColor(ThemeColors.textPrimary).backgroundColor($r('app.color.input_surface')).onChange((value: string) => { this.tagQuery = value })
        if (this.tagQuery.length > 0) {
          SearchClearButton({ controlId: 'hidden-tag-clear', onClear: () => { this.tagQuery = '' } })
        }
        FloatingActionButton({ label: $r('app.string.forum_tag_add'), actionEnabled: this.tagQuery.trim().length > 0,
          onAction: () => { this.toggleTag(this.tagQuery.trim().slice(0, 128)); this.tagQuery = '' } }).width(64)
      }.width('100%')
      Scroll() {
        Column({ space: 8 }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.tagsDraft, (name: string) => {
              this.TagOption(name, true)
            }, (name: string) => name)
          }.width('100%')
          if (this.tagsLoading) { LoadingProgress().width(24).height(24) }
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.suggestions.filter((tag: ForumTag) => !this.tagsDraft.includes(tag.name) && tag.name.toLowerCase().includes(this.tagQuery.toLowerCase())).slice(0, 24), (tag: ForumTag) => {
              this.TagOption(tag.name, false)
            }, (tag: ForumTag) => String(tag.tagId))
          }.width('100%')
        }.width('100%')
      }.constraintSize({ maxHeight: 280 }).width('100%').scrollBar(BarState.Off)
      Row({ space: 12 }) {
        Button($r('app.string.forum_cancel'), { type: ButtonType.Capsule }).layoutWeight(1).backgroundColor($r('app.color.input_surface'))
          .fontColor(ThemeColors.textPrimary).onClick(() => { this.tagsSheet = false })
        Button($r('app.string.save_settings'), { type: ButtonType.Capsule }).layoutWeight(1).backgroundColor(ThemeColors.primary)
          .fontColor(Color.White).onClick(() => { this.saveTags() })
      }.width('100%').enabled(!this.saving)
    }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: Math.max(16, px2vp(this.bottomPx)) + 12 })
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        Scroll(this.touchScroller) {
          Column({ space: 12 }) {
            Column({ space: 8 }) {
              Row({ space: 12 }) {
                SymbolGlyph(getSymbolIcon('forum')).fontSize(32).fontColor([ThemeColors.primary])
                Column({ space: 4 }) {
                  Text(this.status()).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                  Text(ReadableText.resource($r('app.string.forum_account_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).lineBreakStrategy(LineBreakStrategy.GREEDY)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.loading) { LoadingProgress().width(22).height(22) }
              }.width('100%')
              if (this.error) { ErrorNotice({ message: this.error, controlId: 'forumsettingspage-diagnostics', textSize: 12, textColor: ThemeColors.error }).width('100%'); Button($r('app.string.ui_retry')).onClick(() => { this.load(true) }) }
              Button(this.loggedIn ? $r('app.string.ui_log_out') : $r('app.string.ui_log_in_to_forum'), { type: ButtonType.Capsule })
                .backgroundColor($r('app.color.input_surface')).fontColor(this.loggedIn ? ThemeColors.error : ThemeColors.primary).height(40)
                .enabled(!this.saving).onClick(() => { if (this.loggedIn) this.confirmLogout(); else router.pushUrl({ url: 'pages/ForumLoginPage' }) })
            }.width('100%').padding(18).backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
              .borderRadius(24)
            this.GroupTitle($r('app.string.forum_browsing_settings'))
            Column() {
              Row({ space: 12 }) {
                this.RowContents('eye_slash', $r('app.string.caution_settings_title'), () => this.mode === 'show' ? $r('app.string.caution_show') : this.mode === 'hide' ? $r('app.string.caution_hide') : $r('app.string.caution_fold'))
                SymbolGlyph(getSymbolIcon('expand')).fontSize(16).fontColor([ThemeColors.textHint])
              }.padding(16).width('100%').enabled(this.loggedIn && !this.loading && !this.saving && !this.error)
                .bindMenu(this.FoldMenu(), { placement: Placement.BottomRight })
              this.Switch('announcement', $r('app.string.forum_activities_title'), $r('app.string.forum_activities_hint'), ForumPreferences.ACTIVITIES, () => this.activitiesEnabled)
              if (this.activitiesEnabled && AnnouncementConfig.peek().error.length > 0 && this.activitiesRevision >= 0) {
                Row({ space: 8 }) {
                  Text(AnnouncementConfig.peek().cachedAt > 0 ? $r('app.string.forum_activities_cached') : $r('app.string.forum_activities_unavailable'))
                    .fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).layoutWeight(1)
                  FloatingActionButton({ label: $r('app.string.ui_retry'), controlHeight: 32,
                    onAction: () => { AnnouncementConfig.load(true).catch(() => {}) } }).width(64)
                }.padding({ left: 16, right: 16, bottom: 14 }).width('100%')
              }
              this.Switch('eye_slash', $r('app.string.forum_clean_title'), $r('app.string.forum_clean_hint'), ForumPreferences.CLEAN, () => this.cleanEnabled)
              this.Switch('about', $r('app.string.detail_summary'), $r('app.string.forum_summary_hint'), ForumPreferences.SUMMARY, () => this.summaryEnabled)
              this.Action('tag', $r('app.string.forum_hidden_tags'), () => AppLanguage.text($r('app.string.forum_hidden_tag_count'), this.languageRevision, ForumPreferences.parseTags(this.tagsJson).length), () => { this.openTags() })
              this.Action('notification_setting', $r('app.string.notification_settings'), () => $r('app.string.ui_system_permission_forum_notification_types'), () => {
                router.pushUrl({ url: 'pages/AppSettingsPage', params: new SettingsRouteParams('notifications') })
              })
            }.width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
            if (this.loggedIn) {
              this.GroupTitle($r('app.string.forum_account_content'))
              Column() {
                this.Action('about', $r('app.string.forum_punishments'), () => '', () => { this.list('punishments') })
                this.Action('person', $r('app.string.forum_change_password'), () => '', () => { this.password() })
              }.width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
            }
            this.GroupTitle($r('app.string.forum_display_storage'))
            Column() {
              this.Action('image', $r('app.string.forum_background'), () => this.backgroundSource ? $r('app.string.forum_background_set') : $r('app.string.forum_background_hint'), () => { this.pickBackground() })
              if (this.backgroundSource) this.Action('image', $r('app.string.forum_background_remove'), () => '', () => { this.clearBackground() })
              this.Action('history', $r('app.string.forum_clear_cache'), () => $r('app.string.forum_clear_cache_hint'), () => { this.clearCache() })
              this.Action('eye_slash', $r('app.string.detail_restore_hidden'), () => '', () => {
                ForumLocalState.clear().then(() => { promptAction.showToast({ message: $r('app.string.detail_operation_success') }) }).catch((e: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e)) })
              })
            }.width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
          }.width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: px2vp(this.topPx) + 76, bottom: Math.max(16, px2vp(this.bottomPx)) + 32 })
        }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) })
      }.width('100%').height('100%').onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => { this.load(true) })
      TopFade({ extent: px2vp(this.topPx) + 56 })
      FeedRefreshProgress({ topInset: px2vp(this.topPx) + 88, pullOffset: this.pullOffset, refreshing: this.refreshing })
      Column() {
        Row() {
          FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48, onAction: () => { router.back() }  }).width(48)
          Text($r('app.string.ui_forum')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
          Blank().width(72)
        }.width('100%').height(56).padding({ left: 20, right: 20 })
      }.width('100%').padding({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(ThemeColors.bgEnd)
      .bindSheet($$this.tagsSheet, this.TagsSheet(), this.tagsSheetTransition.options(this.tagsSheet, { height: SheetSize.FIT_CONTENT, showClose: false, dragBar: true,
        backgroundColor: nativeFloatingBackground(this.materialRevision), systemMaterial: adaptiveMaterial(this.materialRevision) }))
  }
}
