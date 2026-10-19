import { ReadableText } from '../common/ReadableText'
import { ErrorNotice } from '../components/ErrorNotice'
import { settleScrollTouch } from '../common/ScrollTouch'
import { AppLanguage } from '../common/AppLanguage'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'
import { SettingsRouteParams } from '../common/RouteParams'
import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
import { AppState } from '../common/AppState'
import { Constant } from '../common/Constant'
import { ForumRepository } from '../repository/ForumRepository'
import { CalendarSettings } from '../components/CalendarSettings'
import { TopFade } from '../components/TopFade'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { getSymbolIcon } from '../common/DanXiIcons'

@Entry
@Component
struct AppSettingsPage {
  private touchScroller: Scroller = new Scroller()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @State section: string = 'notifications'
  @State group: string = 'unknown'
  @State notify: string[] = []
  @State notificationsAllowed: boolean = false
  @State permissionKnown: boolean = false
  @State sessionActive: boolean = false
  @State refreshing: boolean = false
  @State private pullOffset: number = 0
  @State saving: boolean = false
  @State loadingPreferences: boolean = true
  @State error: string = ''
  @State private visible: boolean = true
  private readFlight: Promise<void> | null = null
  private permissionReadFlight: Promise<void> | null = null
  @State private permissionPending: boolean = false

  aboutToAppear(): void {
    const params = router.getParams() as SettingsRouteParams
    this.section = params?.section === 'account' ? 'account' : 'notifications'
    this.group = AppState.getPerson().academicGroup
    if (this.section === 'notifications') this.reload()
  }
  onPageShow(): void { this.visible = true; this.readPermission() }
  onPageHide(): void { this.visible = false }

  private readPermission(): Promise<void> {
    if (this.permissionReadFlight !== null) return this.permissionReadFlight
    const task: Promise<void> = this.queryPermission()
    this.permissionReadFlight = task
    task.finally(() => { if (this.permissionReadFlight === task) this.permissionReadFlight = null })
    return task
  }
  private async queryPermission(): Promise<void> {
    try {
      this.notificationsAllowed = await notificationManager.isNotificationEnabled()
      this.permissionKnown = true
    } catch (e) { this.permissionKnown = false }
  }
  private reload(): Promise<void> {
    if (this.saving) { this.refreshing = false; return Promise.resolve() }
    if (this.readFlight !== null) return this.readFlight
    const task: Promise<void> = this.readPreferences()
    this.readFlight = task
    task.finally(() => { if (this.readFlight === task) this.readFlight = null })
    return task
  }
  private async readPreferences(): Promise<void> {
    this.loadingPreferences = true
    this.error = ''
    await this.readPermission()
    try {
      const repo = ForumRepository.getInstance()
      this.sessionActive = await repo.restoreSession()
      if (this.sessionActive) this.notify = (await repo.getMe()).notify
    } catch (e) { this.error = ForumRepository.describeError(e) }
    finally { this.refreshing = false; this.loadingPreferences = false }
  }
  private async saveGroup(value: string): Promise<void> {
    const person = AppState.getPerson()
    person.academicGroup = value
    await AppState.setPerson(person)
    this.group = value
    AppStorage.setOrCreate<number>('academic_account_revision', Date.now())
  }
  private async toggle(type: string, value: boolean): Promise<void> {
    if (this.saving) return
    this.saving = true
    try { this.notify = (await ForumRepository.getInstance().setNotificationType(type, value)).notify }
    catch (e) { this.error = ForumRepository.describeError(e); this.notify = this.notify.slice() }
    finally { this.saving = false }
  }
  private async permission(): Promise<void> {
    if (this.permissionPending) return
    this.permissionPending = true
    try {
      try { await notificationManager.requestEnableNotification(this.getUIContext().getHostContext() as common.UIAbilityContext) }
      catch (e) {
        promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_adjust_permission_sound_and_vibration_in_system_'), this.languageRevision) })
      }
      await this.readPermission()
    }
    finally { this.permissionPending = false }
  }
  @Builder
  Choice(label: Resource, selected: boolean, action: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(getSymbolIcon('academic')).fontSize(22).fontColor([ThemeColors.primary])
      Text(label).fontSize(16).fontColor(ThemeColors.textPrimary).layoutWeight(1)
      Radio({ value: String(label.id), group: 'setting_' + String(label.id) }).checked(selected).hitTestBehavior(HitTestMode.None)
    }.width('100%').padding(14).onClick(action)
  }
  @Builder
  NotificationRow(label: Resource, type: string) {
    Row({ space: 12 }) {
      SymbolGlyph(getSymbolIcon(type === 'favorite' ? 'star' : type === 'report' ? 'campus_access' : 'forum'))
        .fontSize(22).fontColor([ThemeColors.primary])
      Text(label).fontSize(16).fontColor(ThemeColors.textPrimary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.notify.includes(type) })
        .enabled(this.sessionActive && !this.saving && !this.loadingPreferences && !this.error)
        .onChange((value: boolean) => { this.toggle(type, value) })
    }.width('100%').padding(14)
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
        Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
          Scroll(this.touchScroller) {
            Column({ space: 16 }) {
              if (this.section === 'account' && AppState.isLoggedIn()) {
                Text($r('app.string.account_type')).fontColor(ThemeColors.textSecondary).width('100%')
                Column() {
                  this.Choice($r('app.string.account_undergraduate'), this.group === 'undergraduate', () => { this.saveGroup('undergraduate') })
                  this.Choice($r('app.string.account_postgraduate'), this.group === 'postgraduate', () => { this.saveGroup('postgraduate') })
                  Text(ReadableText.resource($r('app.string.account_choice_hint'))).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).padding(12).lineBreakStrategy(LineBreakStrategy.GREEDY)
                  CalendarSettings({ authenticationVisible: this.visible })
                }.borderRadius(20).backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
              }
              if (this.section === 'notifications') {
              Text($r('app.string.notification_settings')).fontColor(ThemeColors.textSecondary).width('100%')
              Column() {
                Text(this.permissionKnown ? (this.notificationsAllowed ? $r('app.string.notification_allowed') : $r('app.string.notification_denied')) : $r('app.string.notification_unknown'))
                  .fontColor(ThemeColors.textSecondary).padding(12)
                Button($r('app.string.notification_permission')).enabled(!this.permissionPending).onClick(() => { this.permission() }).margin(8)
                Text(ReadableText.resource($r('app.string.notification_system_hint'))).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).padding(12).lineBreakStrategy(LineBreakStrategy.GREEDY)
                if (!this.sessionActive) { Text($r('app.string.notification_login')).fontColor(ThemeColors.textSecondary).padding(12) }
                this.NotificationRow($r('app.string.notification_mention'), 'mention')
                this.NotificationRow($r('app.string.notification_favorite'), 'favorite')
                this.NotificationRow($r('app.string.notification_report'), 'report')
                Text($r('app.string.notification_delivery')).fontSize(13).fontColor(ThemeColors.textHint).padding(12)
                if (this.error) { ErrorNotice({ message: this.error, controlId: 'appsettingspage-diagnostics', textColor: ThemeColors.error }).padding(12) }
              }.borderRadius(20).backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
              }
            }.padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: px2vp(this.topPx) + 76, bottom: px2vp(this.bottomPx) + 32 }).width('100%')
          }.onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) }).align(Alignment.Top).width('100%').height('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }.width('100%').height('100%').onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => { if (this.section === 'notifications') this.reload(); else this.refreshing = false })
      TopFade({ extent: px2vp(this.topPx) + 56 })
      FeedRefreshProgress({ topInset: px2vp(this.topPx) + 88, pullOffset: this.pullOffset, refreshing: this.refreshing })
      Column() {
      Row({ space: 12 }) {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48,
          onAction: () => { router.back() }  }).width(48)
        Text(this.section === 'account' ? $r('app.string.account_type') : $r('app.string.notification_settings')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      }.width('100%').height(56).padding({ left: 20, right: 20 })
      }.width('100%').padding({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(ThemeColors.bgEnd)
  }
}
