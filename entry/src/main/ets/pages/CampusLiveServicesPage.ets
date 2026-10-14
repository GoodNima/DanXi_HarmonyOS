import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { ErrorNotice } from '../components/ErrorNotice'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { settleScrollTouch } from '../common/ScrollTouch'

import { router, promptAction } from '@kit.ArkUI'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { common } from '@kit.AbilityKit'
import { AppLanguage } from '../common/AppLanguage'
import { AppState } from '../common/AppState'
import { CampusService } from '../common/CampusService'
import { FduRepository } from '../repository/FduRepository'
import { HttpError } from '../util/HttpUtil'
import { CampusPreference } from '../common/CampusPreference'
import { CampusFilterPreference } from '../common/CampusFilterPreference'
import { CampusSignal } from '../common/CampusSignal'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { CampusLiveServices, CampusLiveSource, DefaultCampusLiveSource } from '../common/CampusLiveServices'
import { CampusLiveData, CampusLiveParams, DiningCampusData, DiningTraffic, LibraryVisitors } from '../model/CampusLiveData'
import { DeveloperNotice } from '../model/AnnouncementConfigData'
import { Constant } from '../common/Constant'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { adaptiveMaterial, nativeFloatingBackground } from '../common/AdaptiveMaterial'
import { BrowserLink } from '../common/BrowserLink'
import { TopFade } from '../components/TopFade'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { getSymbolIcon } from '../common/DanXiIcons'
import { DiningPresentation } from '../common/DiningPresentation'
import { CampusCategory } from '../common/CampusCategory'
import { EmptyRefreshIndicator, FeedRefreshProgress } from '../components/FeedRefreshProgress'

/** Materialize a region before entering ArkUI builders. Nested list callbacks
 * must not capture the campus/region iterator while filtering live rows. */
class DiningSection {
  campus: string = ''
  zone: string = ''
  first: boolean = false
  error: string = ''
  traffic: DiningTraffic[] = []
}

/** Original developer announcements, dining traffic, library visitors and dorm
 * electricity, with common floating navigation and account-scoped refresh. */
@Entry
@Component
export struct CampusLiveServicesPage {
  private noticeSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  source: CampusLiveSource = new DefaultCampusLiveSource()
  initialFeature: string = ''
  sheetMode: boolean = false
  onSheetClose: () => void = () => {}
  private touchScroller: Scroller = new Scroller()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') personJson: string = ''
  @StorageLink(AppState.KEY_IS_LOGGED_IN) @Watch('accountChanged') loggedIn: boolean = false
  @StorageLink(CampusPreference.KEY) @Watch('systemCampusChanged') systemCampus: string = '邯郸'
  @State feature: string = 'developer_notice'
  @State campus: string = CampusPreference.current()
  @State private diningFilter: string = ''
  @State data: CampusLiveData = new CampusLiveData()
  @State error: string = ''
  @State verificationRequired: boolean = false
  @State verifying: boolean = false
  @State failure: Object | null = null
  @State loading: boolean = true
  @State private readPending: boolean = false
  @State private contentOpacity: number = 1
  private contentRevision: number = 0
  @State refreshing: boolean = false
  @State pullOffset: number = 0
  @State allNotices: boolean = false
  @State noticeSheet: boolean = false
  @State selectedNotice: DeveloperNotice = new DeveloperNotice()
  private active: boolean = false
  private loadVersion: number = 0
  private boundOwner: string = ''
  private loadFlight: Promise<void> | null = null
  private loadKey: string = ''
  private resumeVerified: boolean = false
  private campusScope: string = ''

  aboutToAppear(): void {
    const params = router.getParams() as CampusLiveParams
    if (['developer_notice', 'dining', 'library', 'electricity'].includes(this.initialFeature)) this.feature = this.initialFeature
    else if (params && ['developer_notice', 'dining', 'library', 'electricity'].includes(params.feature)) this.feature = params.feature
    this.active = true; this.restoreCampus()
  }
  private async restoreCampus(): Promise<void> {
    const scope: string = CampusPreference.current()
    this.campusScope = scope; this.campus = scope; this.diningFilter = scope
    if (this.feature === 'dining') {
      const selected: string = await CampusFilterPreference.read('dining', scope, true).catch(() => scope)
      if (!this.active || scope !== this.campusScope) return
      this.diningFilter = selected
    }
    if (this.active) this.load(false)
  }
  systemCampusChanged(): void {
    if (!this.active || this.campusScope === CampusPreference.current()) return
    this.campusScope = CampusPreference.current(); this.campus = this.campusScope; this.diningFilter = this.campusScope
    this.load(false)
  }
  onPageShow(): void {
    this.active = true
    if (this.campusScope && this.campusScope !== CampusPreference.current()) { this.systemCampusChanged(); return }
    if (this.verifying || this.loadFlight !== null) return
    if (this.resumeVerified) { this.resumeVerified = false; this.load(true); return }
    if (this.privateFeature() && this.boundOwner !== this.source.owner()) {
      this.data = new CampusLiveData(); this.error = ''; this.noticeSheet = false; this.load(false)
    } else if (this.loading) this.load(false)
  }
  // Verification is an ordinary child route. Its return must retain/accept the
  // same in-flight read rather than losing the verified result until a restart.
  onPageHide(): void { this.active = false; this.refreshing = false; this.contentRevision++; this.contentOpacity = 1 }
  aboutToDisappear(): void { this.active = false; this.loadVersion++; this.contentRevision++; this.contentOpacity = 1 }
  accountChanged(): void {
    if (!this.active || !this.privateFeature()) return
    if (AppState.getPerson().isLoggedIn() !== AppState.isLoggedIn()) return
    if (this.boundOwner === this.source.owner()) return
    this.data = new CampusLiveData(); this.noticeSheet = false; this.load(false)
  }
  private privateFeature(): boolean { return this.feature === 'dining' || this.feature === 'electricity' }
  private load(force: boolean): Promise<void> {
    if (!this.active || this.verifying) return Promise.resolve()
    const key: string = this.feature + '/' + this.campus + '/' + (this.privateFeature() ? this.source.owner() : 'public')
    if (this.loadFlight !== null && this.loadKey === key) return this.loadFlight
    this.loadKey = key
    const task: Promise<void> = this.read(force)
    this.loadFlight = task
    task.finally(() => { if (this.loadFlight === task) this.loadFlight = null })
    return task
  }
  private async read(force: boolean): Promise<void> {
    const version = ++this.loadVersion; const owner = this.source.owner(); const feature = this.feature; const campus = this.campus
    this.readPending = true
    const privateFeature: boolean = this.privateFeature()
    if (privateFeature) this.boundOwner = owner
    this.loading = this.data.updatedAt <= 0; this.error = ''; this.failure = null; this.verificationRequired = false
    try {
      const data = await this.source.detail(feature, force, campus)
      if (!this.active || version !== this.loadVersion || (privateFeature && owner !== this.source.owner())) return
      await this.reveal(() => { this.data = data }, () => version === this.loadVersion && (!privateFeature || owner === this.source.owner()))
    } catch (e) {
      if (this.active && version === this.loadVersion && (!privateFeature || owner === this.source.owner())) {
        this.failure = e as Object; this.error = CampusLiveServices.describe(e as Object, this.languageRevision)
        this.verificationRequired = e instanceof HttpError && e.statusCode === -2
      }
    } finally {
      if (version === this.loadVersion) this.readPending = false
      if (this.active && version === this.loadVersion) { this.loading = false; this.refreshing = false }
    }
  }
  private async verify(): Promise<void> {
    if (!this.active || this.verifying || !this.privateFeature()) return
    if (!FduRepository.getInstance().canLoginOnDemand()) { router.pushUrl({ url: 'pages/LoginPage' }); return }
    const owner: string = this.source.owner()
    const version: number = this.loadVersion
    this.verifying = true
    try {
      const service: string = this.feature === 'electricity' ? CampusService.DORM : CampusService.MY_FUDAN
      await FduRepository.getInstance().verifyService(service)
      if (owner === this.source.owner() && version === this.loadVersion) {
        this.verifying = false; this.verificationRequired = false
        this.resumeVerified = !this.active
        if (this.active) {
          await this.load(true)
        }
      }
    } catch (e) {
      if (owner === this.source.owner() && version === this.loadVersion) { this.failure = e as Object; this.error = CampusLiveServices.describe(e as Object, this.languageRevision) }
    } finally { this.verifying = false }
  }
  private manualReload(): void {
    if (this.verificationRequired) this.verify()
    else this.load(true)
  }
  private chooseCampus(index: number): void {
    const campus = CampusPreference.CHOICES[index]
    if (!campus || campus === this.campus) return
    this.campus = campus; this.load(false)
  }
  private reveal(commit: () => void, valid: () => boolean = () => true): Promise<void> {
    const revision: number = ++this.contentRevision
    return new Promise<void>((resolve: () => void) => {
      this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut, onFinish: () => {
        if (!this.active || revision !== this.contentRevision || !valid()) {
          if (revision === this.contentRevision) this.contentOpacity = 1
          resolve(); return
        }
        commit()
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.contentOpacity = 1 })
        resolve()
      } }, () => { this.contentOpacity = 0 })
    })
  }
  private title(): string { return AppLanguage.text(CampusLiveServices.title(this.feature), this.languageRevision) }
  private notices(): DeveloperNotice[] { return this.allNotices ? this.data.notices : CampusLiveServices.currentNotices(this.data.notices) }
  private diningGroups(): DiningCampusData[] {
    if (this.data.diningCampuses.length > 0) return this.data.diningCampuses.filter((group: DiningCampusData) => !this.diningFilter || group.campus === this.diningFilter)
    if (this.data.status === 'outside') return (this.diningFilter ? [this.diningFilter] : CampusPreference.CHOICES).map((campus: string): DiningCampusData => { const group = new DiningCampusData(); group.campus = campus; return group })
    const group = new DiningCampusData(); group.campus = this.campus; group.traffic = this.data.dining
    return !this.diningFilter || this.diningFilter === group.campus ? [group] : []
  }
  private diningSections(): DiningSection[] {
    const result: DiningSection[] = []
    for (const group of this.diningGroups()) {
      const sections: DiningSection[] = []
      for (const traffic of group.traffic) {
        let section: DiningSection | undefined = sections.find((row: DiningSection) => row.zone === traffic.zone)
        if (section === undefined) { section = new DiningSection(); section.campus = group.campus; section.zone = traffic.zone; sections.push(section) }
        section.traffic.push(traffic)
      }
      if (sections.length === 0) { const empty = new DiningSection(); empty.campus = group.campus; sections.push(empty) }
      sections[0].first = true; sections[0].error = group.error
      result.push(...sections)
    }
    return result
  }
  private errorText(): string { return this.failure !== null ? CampusLiveServices.describe(this.failure, this.languageRevision) : this.error }
  private links(): string[] {
    const matches: string[] = this.selectedNotice.content.match(/https?:\/\/[^\s<>]+/g) ?? []
    return matches.filter((value: string, index: number) => matches.indexOf(value) === index)
  }
  private openLink(address: string): void {
    BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, address)
      .catch((error: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), error, AppLanguage.text($r('app.string.live_open_error'))) })
  }

  @Builder
  Hint() {
    Text(AppLanguage.text(this.feature === 'dining' ? $r('app.string.live_dining_hint') :
      this.feature === 'library' ? $r('app.string.live_library_hint') : this.feature === 'electricity' ?
        $r('app.string.live_electricity_hint') : $r('app.string.live_developer_hint'), this.languageRevision))
      .fontSize(12).lineHeight(19).fontColor(ThemeColors.textSecondary).width('100%')
  }

  @Builder
  StateCard() {
    Column({ space: 12 }) {
      if (this.error) {
        ErrorNotice({ message: this.errorText(), textSize: 14, textColor: CampusContentStyle.attention, controlId: 'campus-live-diagnostics' })
        if (!this.verificationRequired && !this.sheetMode) FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', onCard: true, zeroContentPadding: true, controlHeight: 48,
          actionEnabled: !this.loading && !this.refreshing, onAction: () => { this.manualReload() } }).width(48)
        if (this.verificationRequired) FloatingActionButton({ label: $r('app.string.campus_verify_continue'), actionEnabled: !this.verifying,
          onAction: () => { this.verify() } }).width(160)
      } else if (!this.loading && this.data.status === 'outside') {
        Text($r('app.string.live_dining_outside')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(CampusContentStyle.attention)
      }
    }.width('100%').padding(18).backgroundColor($r('app.color.surface_fallback')).borderRadius(24)
      
  }

  @Builder
  DeveloperContent() {
    Row({ space: 8 }) {
      Text($r('app.string.live_notice_range')).fontSize(14).fontColor(ThemeColors.textSecondary).layoutWeight(1)
      Select([{ value: AppLanguage.text($r('app.string.live_latest'), this.languageRevision) },
        { value: AppLanguage.text($r('app.string.live_history'), this.languageRevision) }])
        .value(AppLanguage.text(this.allNotices ? $r('app.string.live_history') : $r('app.string.live_latest'), this.languageRevision))
        .selected(this.allNotices ? 1 : 0).fontColor(ThemeColors.textPrimary)
        .onSelect((index: number) => { this.reveal(() => { this.allNotices = index === 1 }) })
    }.width('100%')
    if (!this.loading && !this.error && this.notices().length === 0) { Text($r('app.string.live_no_notices')).fontColor(ThemeColors.textSecondary).padding(18) }
    ForEach(this.notices(), (item: DeveloperNotice) => {
      Column({ space: 10 }) {
        Text(item.content).fontSize(16).lineHeight(25).fontColor(ThemeColors.textPrimary).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(CampusLiveServices.noticeDateLabel(item.updatedAt)).fontSize(12).fontColor(ThemeColors.primary).layoutWeight(1)
          Text($r('app.string.live_view_full')).fontSize(12).fontColor(ThemeColors.primary)
        }.width('100%')
      }.width('100%').padding(18).alignItems(HorizontalAlign.Start).borderRadius(24)
        .backgroundColor($r('app.color.surface_fallback'))
        .onClick(() => { this.noticeSheetTransition.open(() => {
          if (this.active) { this.selectedNotice = item; this.noticeSheet = true }
        }, () => this.getUIContext()) })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 }).renderGroup(true)
        .transition(TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.Friction }))
    }, (item: DeveloperNotice): string => item.updatedAt + item.content.slice(0, 32))
  }

  private diningColor(item: DiningTraffic): ResourceColor {
    // The count and its matching bar describe one traffic level.
    return CampusContentStyle.signalColor(CampusSignal.dining(item.current, item.maximum), ThemeColors.textSecondary)
  }

  @Builder
  DiningRow(item: DiningTraffic, controlId: string) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text(DiningPresentation.windowName(item)).fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary).layoutWeight(1)
        Text() {
          Span(String(item.current)).fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.diningColor(item))
          Span(' ').fontSize(12)
          Span($r('app.string.live_dining_people')).fontSize(12).fontColor(ThemeColors.textSecondary)
        }.maxLines(1).constraintSize({ minWidth: 68 }).textAlign(TextAlign.End).id('dining-count-' + controlId)
      }.width('100%').alignItems(VerticalAlign.Center)
      if (item.maximum > 0) {
        Progress({ value: Math.min(100, item.ratio() * 100), total: 100, type: ProgressType.Linear }).width('100%')
          .color(this.diningColor(item)).backgroundColor($r('app.color.input_surface'))
      }
      Text(AppLanguage.text(item.maximum > 0 ? $r('app.string.live_peak_reference') : $r('app.string.dining_peak_missing'),
        this.languageRevision, item.maximum)).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
    }.width('100%').padding(ThemeDimens.cardInset).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface_fallback')).borderRadius(24)
      .id(controlId)
  }

  @Builder
  DiningContent() {
    Row({ space: 12 }) {
      Text($r('app.string.live_query_campus')).fontSize(14).fontColor(ThemeColors.textSecondary).layoutWeight(1)
      Select(this.diningOptions())
        .value(this.diningFilter ? AppLanguage.campus(this.diningFilter, this.languageRevision) : AppLanguage.text($r('app.string.reservation_all_campuses'), this.languageRevision))
        .selected(this.diningFilter ? CampusPreference.CHOICES.indexOf(this.diningFilter) + 1 : 0)
        .fontColor(ThemeColors.textPrimary).id('dining-campus-filter').onSelect((index: number) => {
          const campus: string = index === 0 ? '' : CampusPreference.CHOICES[index - 1]
          CampusFilterPreference.remember('dining', campus, true).catch(() => {})
          this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.diningFilter = campus })
        })
    }.width('100%')
    ForEach(this.diningSections(), (section: DiningSection) => {
      if (section.first) Text(AppLanguage.campus(section.campus, this.languageRevision)).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%').margin({ top: 8 })
      if (section.error) ErrorNotice({ message: section.error, controlId: 'dining-campus-diagnostics-' + section.campus })
      if (section.zone && section.zone !== section.campus) {
        Row({ space: 8 }) {
          SymbolGlyph(DiningPresentation.coffee(section.zone) ? $r('sys.symbol.cup_fill') : getSymbolIcon('dining'))
            .fontSize(20).fontColor([CampusCategory.color('dining')])
          Text(section.zone).fontSize(18).lineHeight(26).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            .layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Center).margin({ top: 4 })
          .id('dining-category-' + section.campus + '-' + section.zone)
      }
      ForEach(section.traffic, (item: DiningTraffic, index: number) => {
        this.DiningRow(item, 'dining-window-' + section.campus + '-' + section.zone + '-' + String(index))
      }, (item: DiningTraffic, index: number): string => section.campus + '/' + section.zone + '/' + String(index) + '/' + item.name + '/' + String(item.current) + '/' + String(item.maximum))
    }, (section: DiningSection): string => section.campus + '/' + section.zone + '/' + section.error + '/' + JSON.stringify(section.traffic))
    if (!this.loading && !this.error && this.data.status === 'ready' && this.diningGroups().every((group: DiningCampusData) => group.traffic.length === 0 && !group.error)) { Text($r('app.string.ui_no_data')).fontColor(ThemeColors.textSecondary).padding(18) }
  }

  private diningOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: AppLanguage.text($r('app.string.reservation_all_campuses'), this.languageRevision) }]
    return options.concat(CampusPreference.CHOICES.map((value: string): SelectOption => ({ value: AppLanguage.campus(value, this.languageRevision) })))
  }

  @Builder
  LibraryContent() {
    ForEach(this.data.libraries, (item: LibraryVisitors) => {
      Column({ space: 12 }) {
        Row({ space: 16 }) {
        Column({ space: 6 }) {
          Text(item.name).fontSize(17).lineHeight(25).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          if (item.openTime) { Text(item.openTime).fontSize(12).fontColor(ThemeColors.textSecondary) }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 4 }) {
          Text(item.visitors).fontSize(32).fontWeight(FontWeight.Bold).fontColor(this.libraryColor(item))
          Text($r('app.string.live_visitors')).fontSize(12).fontColor(ThemeColors.textSecondary)
        }.alignItems(HorizontalAlign.End)
        }.width('100%')
        if (item.remaining >= 0) {
          if (item.capacity > 0) {
            Progress({ value: Math.min(100, item.ratio() * 100), total: 100, type: ProgressType.Linear })
              .color(this.libraryColor(item)).backgroundColor($r('app.color.input_surface')).width('100%')
          }
          Row() {
            Text(AppLanguage.text($r('app.string.library_remaining'), this.languageRevision, item.remaining)).fontSize(13).fontColor(this.libraryColor(item)).layoutWeight(1)
            Text(AppLanguage.text($r('app.string.library_capacity'), this.languageRevision, item.capacity)).fontSize(12).fontColor(ThemeColors.textSecondary)
          }.width('100%')
        }
      }.width('100%').padding(ThemeDimens.cardInset).backgroundColor($r('app.color.surface_fallback')).borderRadius(24)
        
    }, (item: LibraryVisitors): string => item.id || item.name)
    if (!this.loading && !this.error && this.data.libraries.length === 0) { Text($r('app.string.ui_no_data')).fontColor(ThemeColors.textSecondary).padding(18) }
  }

  private libraryColor(item: LibraryVisitors): ResourceColor {
    return item.capacity > 0 ? CampusContentStyle.signalColor(CampusSignal.dining(Number(item.visitors), item.capacity), ThemeColors.textPrimary) : ThemeColors.textPrimary
  }

  @Builder
  ElectricityContent() {
    if (this.data.electricity !== null) {
      Column({ space: 14 }) {
        Text(this.data.electricity.dormName).fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%')
        Row({ space: 20 }) {
          Column({ space: 6 }) {
            Text(this.data.electricity.available || '—').fontSize(32).fontWeight(FontWeight.Bold)
              .fontColor(CampusContentStyle.signalColor(CampusSignal.amount(this.data.electricity.available), ThemeColors.textSecondary))
            Text($r('app.string.live_remaining_kwh')).fontSize(12).fontColor(ThemeColors.textSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Column({ space: 6 }) {
            Text(this.data.electricity.used || '—').fontSize(27).fontWeight(FontWeight.Medium).fontColor(ThemeColors.primary)
            Text($r('app.string.live_used_kwh')).fontSize(12).fontColor(ThemeColors.textSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
        if (this.data.electricity.updateTime) { Text(this.data.electricity.updateTime).fontSize(12).fontColor(ThemeColors.textSecondary).width('100%') }
      }.width('100%').padding(ThemeDimens.cardInset).backgroundColor($r('app.color.surface_fallback')).borderRadius(24)
        
    }

  }

  @Builder
  ElectricitySheet() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text($r('app.string.live_electricity_title')).fontSize(20).lineHeight(28).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).layoutWeight(1).id('electricity-sheet-title')
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', controlHeight: 40,
          controlId: 'electricity-sheet-refresh', actionEnabled: !this.readPending && !this.verifying,
          onAction: () => { this.manualReload() } }).width(40)
        FloatingActionButton({ label: $r('app.string.ui_close'), icon: 'close', iconResource: $r('sys.symbol.xmark'), controlHeight: 40,
          controlId: 'electricity-sheet-close', onAction: () => { this.onSheetClose() } }).width(40)
      }.width('100%').alignItems(VerticalAlign.Center).id('electricity-sheet-header')
      if (this.loading && this.data.electricity === null) {
        Stack() { CenterLoadingProgress({ busy: true }) }.width('100%').height(152)
      } else {
        if (this.data.electricity !== null) this.ElectricityContent()
        if (this.error) this.StateCard()
        if (this.data.electricity === null && !this.error) Text($r('app.string.ui_no_data')).fontSize(14)
          .fontColor(ThemeColors.textSecondary).width('100%').padding({ top: 12, bottom: 12 })
      }
    }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: Math.max(16, px2vp(this.bottomPx)) + 8 })
      .id('electricity-sheet-content')
  }

  @Builder
  NoticeContents() {
    Column({ space: 12 }) {
      Text(CampusLiveServices.noticeDateLabel(this.selectedNotice.updatedAt)).fontSize(12).fontColor(ThemeColors.primary).width('100%')
      Scroll() {
        Column({ space: 16 }) {
          Text(this.selectedNotice.content).fontSize(16).lineHeight(26).fontColor(ThemeColors.textPrimary).width('100%').copyOption(CopyOptions.LocalDevice)
          ForEach(this.links(), (address: string) => {
            Text(address).fontSize(14).lineHeight(23).fontColor(ThemeColors.primary).width('100%').onClick(() => { this.openLink(address) })
          }, (address: string): string => address)
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 400 }).scrollBar(BarState.Auto).align(Alignment.Top)
    }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: Math.max(20, px2vp(this.bottomPx)) + 8 })
  }

  build() {
    if (this.sheetMode) {
      this.ElectricitySheet()
    } else {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        Scroll(this.touchScroller) {
          Column({ space: 12 }) {
            this.Hint()
            if (this.error || (!this.loading && this.data.status === 'outside')) this.StateCard()
            if (this.feature === 'developer_notice') this.DeveloperContent()
            else if (this.feature === 'dining') this.DiningContent()
            else if (this.feature === 'library') this.LibraryContent()
            else if (this.feature === 'electricity') this.ElectricityContent()
          }.width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: px2vp(this.topPx) + 84, bottom: Math.max(20, px2vp(this.bottomPx)) + 24 })
        }.width('100%').height('100%').align(Alignment.Top).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) })
          .renderGroup(true).opacity(this.contentOpacity * (this.readPending && !this.refreshing ? 0.45 : 1)).animation({ duration: 220, curve: Curve.EaseOut })
      }.width('100%').height('100%').onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => { this.load(true) })
      CenterLoadingProgress({ busy: this.readPending && !this.refreshing })
      TopFade({ extent: px2vp(this.topPx) + 64 })
      FeedRefreshProgress({ topInset: px2vp(this.topPx) + 88, pullOffset: this.pullOffset, refreshing: this.refreshing })
      Row({ space: 12 }) {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48, onAction: () => { router.back() }  }).width(48)
        Text(this.title()).fontSize(20).minFontSize(15).maxFontSize(20).maxLines(1).lineHeight(28).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 48,
          controlId: 'campus-detail-refresh', actionEnabled: !this.loading && !this.refreshing,
          onAction: () => { this.manualReload() } }).width(48)
      }.width('100%').height(56).padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter }).margin({ top: px2vp(this.topPx) })
        .hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(ThemeColors.bgEnd)
      .bindSheet($$this.noticeSheet, this.NoticeContents(), this.noticeSheetTransition.options(this.noticeSheet, { height: SheetSize.FIT_CONTENT,
        title: { title: $r('app.string.live_developer_title') },
        showClose: true, dragBar: false, backgroundColor: nativeFloatingBackground(this.materialRevision), systemMaterial: adaptiveMaterial(this.materialRevision) }))
    }
  }
}
