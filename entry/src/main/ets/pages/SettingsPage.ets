import { ReadableText } from '../common/ReadableText'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { settleScrollTouch } from '../common/ScrollTouch'
import { ClassroomPreference } from '../common/ClassroomPreference'
import { HapticFeedback } from '../common/HapticFeedback'
import { NetworkProxy } from '../common/NetworkProxy'
import { SettingsRouteParams } from '../common/RouteParams'
import { router, promptAction } from '@kit.ArkUI'
import { AppState } from '../common/AppState'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { Constant } from '../common/Constant'
import { Person } from '../model/Person'
import { getSymbolIcon } from '../common/DanXiIcons'
import { ForumRepository } from '../repository/ForumRepository'
import { ForumPreferences } from '../common/ForumPreferences'
import { CampusPreference } from '../common/CampusPreference'
import { Appearance } from '../common/Appearance'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { AppLanguage } from '../common/AppLanguage'
import { CalendarSettings } from '../components/CalendarSettings'
import { TopFade } from '../components/TopFade'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
import { AccountIdentity } from '../common/AccountIdentity'
import { FloatingSurface } from '../components/FloatingSurface'
import { ForumProfileSource } from '../common/ForumProfileSource'

@Component
export struct SettingsPage {
  private touchScroller: Scroller = new Scroller()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(ClassroomPreference.KEY_HIGH_CONTRAST) highContrast: boolean = false
  @StorageLink(HapticFeedback.KEY_ENABLED) hapticsEnabled: boolean = false
  @StorageLink(NetworkProxy.KEY_ACTIVE) activeProxy: string = ''
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(AppState.KEY_IS_LOGGED_IN) @Watch('onCampusLoginChanged') isLoggedIn: boolean = false
  @StorageLink(AppState.KEY_PERSON) @Watch('onPersonChanged') personJson: string = ''
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink('app_theme_mode') themeMode: string = 'system'
  @StorageLink(AppLanguage.KEY_MODE) languageMode: string = 'system'
  @StorageLink(Constant.KEY_USE_WEBVPN) useWebVpn: boolean = true
  @StorageLink(CampusPreference.KEY) campus: string = '邯郸'
  @StorageLink(Constant.KEY_FORUM_LOGGED_IN) @Watch('onForumLoginChanged') forumLoggedIn: boolean = false
  @StorageLink(ForumPreferences.USER_ID) forumUserId: number = 0
  @StorageLink(ForumRepository.KEY_SESSION_REVISION) @Watch('onForumSessionChanged') forumSessionRevision: number = 0
  @StorageLink('main_active_tab') @Watch('onActiveTabChanged') activeTab: number = 0
  @StorageLink('main_route_visible') mainVisible: boolean = true
  @StorageLink('profile_refresh') @Watch('refreshProfile') profileRefresh: number = 0
  @StorageLink(AccountIdentity.KEY_REVISION) identityRevision: number = 0
  @State refreshing: boolean = false
  @State savingChoice: boolean = false
  @State verifiedName: string = ''
  @State failedAvatar: string = ''
  private active: boolean = false
  private profileGeneration: number = 0
  private profileLoading: boolean = false
  private profileScope: number = -1
  private profileReadScope: number = -1
  private profileReadAt: number = 0
  private profileRetryAt: number = 0
  private identityGeneration: number = 0
  private identityScope: string = ''
  private identityLoading: boolean = false
  private identityRetryAt: number = 0
  forumProfileSource: ForumProfileSource = new ForumProfileSource()

  aboutToAppear(): void { this.active = true; this.reloadProfile(); this.loadIdentity() }
  aboutToDisappear(): void {
    this.active = false; this.profileGeneration++; this.identityGeneration++
    this.identityLoading = false
    this.profileLoading = false; this.refreshing = false
  }
  onActiveTabChanged(): void {
    if (this.active && this.activeTab === 4) { this.reloadProfile(); this.loadIdentity() }
  }
  refreshProfile(): void { this.reloadProfile(this.refreshing); this.loadIdentity(this.refreshing) }
  async reloadProfile(force: boolean = false): Promise<void> {
    if (!this.active) { this.refreshing = false; return }
    const repo: ForumProfileSource = this.forumProfileSource
    if (this.profileLoading && this.profileScope === repo.sessionRevision()) return
    const generation: number = ++this.profileGeneration
    this.profileScope = repo.sessionRevision(); this.profileLoading = true
    try {
      const session: boolean = await repo.restoreSession()
      if (!this.active || generation !== this.profileGeneration || !session || !repo.isLoggedIn() || this.activeTab !== 4) return
      this.profileScope = repo.sessionRevision()
      if (!force && this.profileReadScope === this.profileScope &&
        (Date.now() - this.profileReadAt < 5 * 60 * 1000 || Date.now() < this.profileRetryAt)) return
      this.profileReadScope = this.profileScope
      await repo.getMe()
      if (this.active && generation === this.profileGeneration && this.profileScope === repo.sessionRevision()) {
        this.profileReadAt = Date.now(); this.profileRetryAt = 0
      }
    } catch (e) {
      if (generation === this.profileGeneration && this.profileScope === repo.sessionRevision()) this.profileRetryAt = Date.now() + 60000
      if (this.active && generation === this.profileGeneration && this.profileScope === repo.sessionRevision() && this.refreshing) {
        DiagnosticNavigation.feedback(this.getUIContext(), ForumRepository.describeError(e))
      }
    } finally {
      if (this.active && generation === this.profileGeneration) { this.profileLoading = false; this.refreshing = false }
    }
  }
  onForumLoginChanged(): void { this.onForumSessionChanged() }
  onForumSessionChanged(): void {
    this.profileGeneration++; this.profileLoading = false; this.refreshing = false
    if (this.active && this.activeTab === 4 && this.forumLoggedIn) this.reloadProfile()
  }
  onPersonChanged(): void {
    this.identityGeneration++; this.verifiedName = ''; this.failedAvatar = ''
    this.identityLoading = false
    AccountIdentity.clearIfOwnerChanged(this.profile())
    if (this.active) this.loadIdentity()
  }
  onCampusLoginChanged(): void {
    if (!this.isLoggedIn) { this.identityGeneration++; this.identityLoading = false; this.identityRetryAt = 0; this.verifiedName = ''; this.failedAvatar = ''; AccountIdentity.clearName() }
    else if (this.active) this.loadIdentity()
  }
  private async loadIdentity(force: boolean = false): Promise<void> {
    if (!this.active || !this.isLoggedIn || AccountIdentity.profileName(this.profile(), this.verifiedName) || AccountIdentity.cachedName(this.profile())) return
    if (this.identityScope === this.personJson && (this.identityLoading || (!force && Date.now() < this.identityRetryAt))) return
    const generation: number = ++this.identityGeneration
    const owner: string = this.personJson
    this.identityScope = owner; this.identityLoading = true
    try {
      const name: string = await AccountIdentity.syncName(this.profile(), force)
      if (this.active && generation === this.identityGeneration && owner === this.personJson && this.isLoggedIn) {
        this.verifiedName = name
        AccountIdentity.publishName(this.profile(), name)
      }
    } catch (e) { /* Optional identity must not force authentication. */ }
    finally {
      if (generation === this.identityGeneration) { this.identityLoading = false; this.identityRetryAt = Date.now() + 5 * 60 * 1000 }
    }
  }
  private profile(): Person { return Person.fromJson(this.personJson) }
  private displayName(): string {
    this.identityRevision
    return AccountIdentity.profileName(this.profile(), this.verifiedName) || AccountIdentity.cachedName(this.profile()) ||
      AppLanguage.text($r('app.string.account_signed_in'), this.languageRevision)
  }
  private avatarSource(): string { return AccountIdentity.avatar(this.profile()) }
  private avatarFailed(source: string, owner: string): void {
    if (owner === this.personJson && source === this.avatarSource()) this.failedAvatar = source
  }
  private async selectTheme(mode: string): Promise<void> {
    if (this.savingChoice || mode === this.themeMode) return
    this.savingChoice = true
    try { await Appearance.apply(mode) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.ui_could_not_save_theme_please_retry'))) }
    finally { this.savingChoice = false }
  }
  private async selectLanguage(mode: string): Promise<void> {
    if (this.savingChoice || mode === this.languageMode) return
    this.savingChoice = true
    try { await AppLanguage.apply(mode) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.language_save_failed'))) }
    finally { this.savingChoice = false }
  }
  private async selectCampus(value: string): Promise<void> {
    if (this.savingChoice || this.campus === value) return
    this.savingChoice = true
    try { await CampusPreference.set(value) }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.profile_save_failed'))) }
    finally { this.savingChoice = false }
  }
  private async saveWebVpn(value: boolean): Promise<void> {
    try { await PreferencesUtil.getInstance().putBoolean(Constant.KEY_USE_WEBVPN, value); this.useWebVpn = value }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.webvpn_save_failed'))) }
  }
  private async selectAccount(group: string): Promise<void> {
    if (this.savingChoice || !this.isLoggedIn) return
    this.savingChoice = true
    try {
      const person = AppState.getPerson()
      person.academicGroup = group
      await AppState.setPerson(person)
      AppStorage.setOrCreate<number>('academic_account_revision', Date.now())
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.ui_could_not_save_account_type_please_retry'))) }
    finally { this.savingChoice = false }
  }
  private summary(kind: string): string {
    if (kind === 'theme') return AppLanguage.text(this.themeMode === 'system' ? $r('app.string.theme_system') :
      this.themeMode === 'dark' ? $r('app.string.theme_dark') : $r('app.string.theme_light'), this.languageRevision)
    if (kind === 'language') return AppLanguage.text(AppLanguage.title(this.languageMode), this.languageRevision)
    if (kind === 'campus') return AppLanguage.campus(this.campus, this.languageRevision)
    const group = this.profile().academicGroup
    return AppLanguage.text(group === 'postgraduate' ? $r('app.string.ui_graduate') :
      group === 'undergraduate' ? $r('app.string.ui_undergraduate') : $r('app.string.ui_choose'), this.languageRevision)
  }
  private forumSummary(): string {
    return this.forumLoggedIn ? (this.forumUserId > 0 ? AppLanguage.text($r('app.string.forum_account_id'), this.languageRevision, this.forumUserId) :
      AppLanguage.text($r('app.string.forum_signed_in'), this.languageRevision)) : AppLanguage.text($r('app.string.forum_signed_out'), this.languageRevision)
  }
  private async goToLogin(): Promise<void> {
    await AppState.clearGuest()
    router.clear()
    router.pushUrl({ url: 'pages/LoginPage' })
  }
  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({ title: $r('app.string.ui_log_out'), message: $r('app.string.profile_logout_hint'),
      primaryButton: { value: AppLanguage.text($r('app.string.forum_cancel'), this.languageRevision), action: () => {} },
      secondaryButton: { value: AppLanguage.text($r('app.string.ui_log_out'), this.languageRevision), fontColor: ThemeColors.error,
        action: () => { this.logout() } } })
  }
  private async logout(): Promise<void> {
    if (this.savingChoice) return
    this.savingChoice = true
    try {
      await AppState.logout()
      router.clear()
      router.pushUrl({ url: 'pages/LoginPage' })
    } catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.ui_could_not_log_out'))) }
    finally { this.savingChoice = false }
  }
  private choiceHint(kind: string): Resource {
    if (kind === 'theme') return $r('app.string.theme_choice_hint')
    if (kind === 'language') return $r('app.string.language_choice_hint')
    if (kind === 'campus') return $r('app.string.profile_campus_hint')
    return $r('app.string.account_choice_hint')
  }
  @Builder
  ChoiceNote(hint: Resource) {
    Column() {
      Text(ReadableText.resource(hint)).fontSize(12).lineHeight(20).lineBreakStrategy(LineBreakStrategy.GREEDY).fontColor(ThemeColors.textSecondary).width('100%')
    }.width(240).padding({ left: 8, right: 8, top: 8, bottom: 8 }).alignItems(HorizontalAlign.Start)
  }
  @Builder
  ChoiceMenu(kind: string) {
    Menu() {
      MenuItemGroup() {
        if (kind === 'theme') {
          MenuItem({ content: $r('app.string.theme_system') }).selected(this.themeMode === 'system').selectIcon(true).onClick(() => { this.selectTheme('system') })
          MenuItem({ content: $r('app.string.theme_light') }).selected(this.themeMode === 'light').selectIcon(true).onClick(() => { this.selectTheme('light') })
          MenuItem({ content: $r('app.string.theme_dark') }).selected(this.themeMode === 'dark').selectIcon(true).onClick(() => { this.selectTheme('dark') })
        } else if (kind === 'language') {
          ForEach(AppLanguage.CHOICES, (mode: string) => {
            MenuItem({ content: AppLanguage.title(mode) }).selected(this.languageMode === mode).selectIcon(true).onClick(() => { this.selectLanguage(mode) })
          }, (mode: string) => mode)
        } else if (kind === 'campus') {
          ForEach(CampusPreference.CHOICES, (value: string) => {
            MenuItem({ content: CampusPreference.title(value) }).selected(this.campus === value).selectIcon(true).onClick(() => { this.selectCampus(value) })
          }, (value: string) => value)
        } else if (kind === 'account') {
          MenuItem({ content: $r('app.string.account_undergraduate') }).selected(this.profile().academicGroup === 'undergraduate').selectIcon(true).onClick(() => { this.selectAccount('undergraduate') })
          MenuItem({ content: $r('app.string.account_postgraduate') }).selected(this.profile().academicGroup === 'postgraduate').selectIcon(true).onClick(() => { this.selectAccount('postgraduate') })
        }
      }
      MenuItem(() => { this.ChoiceNote(this.choiceHint(kind)) }).enabled(false)
    }.width(272)
  }
  @Builder
  ChoiceItem(icon: string, title: Resource, kind: string) {
    Row({ space: 12 }) {
      SymbolGlyph(getSymbolIcon(icon)).fontSize(22).fontColor([ThemeColors.primary])
      Text(title).fontSize(15).fontColor(ThemeColors.textPrimary).layoutWeight(1)
      Text(this.summary(kind)).fontSize(13).fontColor(ThemeColors.textSecondary)
      SymbolGlyph(getSymbolIcon('expand')).fontSize(16).fontColor([ThemeColors.textHint])
    }.width('100%').padding(16).enabled(!this.savingChoice)
      .bindMenu(this.ChoiceMenu(kind), { placement: Placement.BottomRight })
  }
  @Builder
  SettingsItem(icon: string, title: Resource, subtitle: () => string, action: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(getSymbolIcon(icon)).fontSize(22).fontColor([ThemeColors.primary])
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontColor(ThemeColors.textPrimary)
        if (subtitle().length > 0) { Text(subtitle()).fontSize(13).fontColor(ThemeColors.textSecondary) }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([ThemeColors.textHint])
    }.width('100%').padding(16).backgroundColor($r('app.color.surface_fallback'))
      .borderRadius(20).onClick(action)
  }
  @Builder
  AccountImage(source: string, owner: string) {
    Image(source).width(58).height(58).objectFit(ImageFit.Cover).onError(() => { this.avatarFailed(source, owner) })
  }
  @Builder
  AccountAvatar() {
    Stack() {
      SymbolGlyph(getSymbolIcon('person')).fontSize(30).fontColor([Color.White])
      if (this.avatarSource() && this.avatarSource() !== this.failedAvatar) {
        ForEach([this.avatarSource()], (source: string) => {
          this.AccountImage(source, this.personJson)
        }, (source: string) => AccountIdentity.id(this.profile()) + ':' + this.identityGeneration + ':' + source)
      }
    }.width(58).height(58).backgroundColor(ThemeColors.primary).borderRadius(29).clip(true)
      .accessibilityText($r('app.string.account_avatar'))
  }
  @Builder
  LogoutControl() {
    Button($r('app.string.ui_log_out'), { type: ButtonType.Capsule }).width('100%').height('100%').padding(0)
      .fontSize(12).fontColor(ThemeColors.error).backgroundColor(Color.Transparent)
      .stateEffect(false).hoverEffect(HoverEffect.None).enabled(!this.savingChoice)
      .onClick(() => { this.confirmLogout() })
  }
  @Builder
  AccountCard() {
    Column() {
      if (this.isLoggedIn) {
        Row({ space: 12 }) {
          this.AccountAvatar()
          Column({ space: 4 }) {
            Text(this.displayName()).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (AccountIdentity.id(this.profile())) {
              Text(AppLanguage.text($r('app.string.account_fudan_id'), this.languageRevision, AccountIdentity.id(this.profile())))
                .fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.primary).width('100%')
            }
            if (AccountIdentity.details(this.profile())) {
              Text(AccountIdentity.details(this.profile())).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
            }
            if (AccountIdentity.email(this.profile())) {
              Text(AccountIdentity.email(this.profile())).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
            }
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.padding({ left: 18, right: 18, top: 18, bottom: 12 }).width('100%').alignItems(VerticalAlign.Center)
        Row() {
          Text($r('app.string.account_verified')).fontSize(12).fontColor(ThemeColors.success).layoutWeight(1)
          FloatingSurface({ radius: 18, acceptsInput: true, content: () => { this.LogoutControl() } }).width(88).height(36)
        }.width('100%').padding({ left: 18, right: 18, bottom: 14 })
      } else {
        Row({ space: 12 }) {
          SymbolGlyph(getSymbolIcon('person')).fontSize(36).fontColor([ThemeColors.primary])
          Column({ space: 4 }) {
            Text($r('app.string.ui_welcome_to_danxi')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            Text($r('app.string.ui_log_in_to_view_grades_timetables_and_campus_serv')).fontSize(13).fontColor(ThemeColors.textSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.padding(18)
      }
      Divider().color($r('app.color.surface_outline')).margin({ left: 16, right: 16 })
      this.ChoiceItem('location', $r('app.string.profile_current_campus'), 'campus')
      if (this.isLoggedIn) {
        this.ChoiceItem('person', $r('app.string.account_type'), 'account')
      } else {
        Button($r('app.string.ui_log_in'), { type: ButtonType.Capsule }).height(40).backgroundColor(ThemeColors.primary).fontColor(Color.White)
          .margin({ left: 18, right: 18, bottom: 16 }).width('88%').onClick(() => { this.goToLogin() })
      }
    }.width('100%').backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      .borderRadius(24)
  }
  @Builder
  UtilityToggle(title: ResourceStr, hint: ResourceStr, value: boolean, key: string) {
    Row({ space: 12 }) {
      SymbolGlyph(getSymbolIcon(key === HapticFeedback.KEY_ENABLED ? 'haptics' : 'contrast')).fontSize(22).fontColor([ThemeColors.primary])
      Column({ space: 5 }) {
        Text(title).fontSize(15).fontColor(ThemeColors.textPrimary)
        Text(ReadableText.resource(hint)).fontSize(12).lineHeight(20).lineBreakStrategy(LineBreakStrategy.GREEDY).fontColor(ThemeColors.textSecondary)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: value }).onChange((enabled: boolean) => {
        const save = key === HapticFeedback.KEY_ENABLED ? HapticFeedback.set(enabled) : ClassroomPreference.set(key, enabled)
        save.catch((e: Error) => { DiagnosticNavigation.feedback(this.getUIContext(), String(e)) })
      })
    }.padding(16).width('100%')
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
        Scroll(this.touchScroller) {
          Column({ space: 12 }) {
            this.AccountCard()
            this.SettingsItem('forum', $r('app.string.ui_forum'), () => this.forumSummary(), () => { router.pushUrl({ url: 'pages/ForumSettingsPage' }) })
            Text($r('app.string.ui_general')).fontSize(13).fontColor(ThemeColors.textSecondary).width('100%').margin({ top: 8 })
            Column() {
              this.ChoiceItem('theme', $r('app.string.theme_mode'), 'theme')
              this.ChoiceItem('language', $r('app.string.ui_language'), 'language')
              this.UtilityToggle($r('app.string.settings_high_contrast'), $r('app.string.settings_high_contrast_hint'), this.highContrast, ClassroomPreference.KEY_HIGH_CONTRAST)
              this.UtilityToggle($r('app.string.settings_haptics'), $r('app.string.settings_haptics_hint'), this.hapticsEnabled, HapticFeedback.KEY_ENABLED)
              Row({ space: 12 }) {
                SymbolGlyph(getSymbolIcon('proxy')).fontSize(22).fontColor([ThemeColors.primary])
                Column({ space: 5 }) {
                  Text($r('app.string.webvpn_auto')).fontSize(15).fontColor(ThemeColors.textPrimary)
                  Text(ReadableText.resource($r('app.string.webvpn_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).lineBreakStrategy(LineBreakStrategy.GREEDY)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.useWebVpn }).onChange((value: boolean) => { this.saveWebVpn(value) })
              }.padding(16).width('100%')
            }.width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
            this.SettingsItem('proxy', $r('app.string.settings_proxy'), () => this.activeProxy || AppLanguage.text($r('app.string.settings_proxy_none'), this.languageRevision), () => {
              router.pushUrl({ url: 'pages/SettingsUtilitiesPage', params: new SettingsRouteParams('proxy') })
            })
            CalendarSettings({ authenticationVisible: this.activeTab === 4 && this.mainVisible })
            Text($r('app.string.ui_about')).fontSize(13).fontColor(ThemeColors.textSecondary).width('100%').margin({ top: 8 })
            this.SettingsItem('about', $r('app.string.ui_about_danxi'), () => 'v' + Constant.APP_DISPLAY_VERSION, () => {
              router.pushUrl({ url: 'pages/SettingsUtilitiesPage', params: new SettingsRouteParams('about') })
            })
          }.width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: px2vp(this.topPx) + 76, bottom: Math.max(16, px2vp(this.bottomPx)) + 112 })
            .alignItems(HorizontalAlign.Start)
        }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) })
      TopFade({ extent: px2vp(this.topPx) + 56 })
      Column() {
        Text($r('app.string.ui_me')).fontSize(ThemeDimens.textSizeXLarge).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .width('100%').height(64).padding({ left: 20, right: 20 })
      }.width('100%').padding({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
