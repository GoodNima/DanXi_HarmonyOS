import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { router, ColorMetrics } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { TabSegmentButtonV2, SegmentButtonV2Items } from '@ohos.arkui.advanced.SegmentButtonV2'
import { AppLanguage } from '../common/AppLanguage'
import { AppState } from '../common/AppState'
import { Constant } from '../common/Constant'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { LibraryAccountItem, LibraryAccountParser, LibraryDataMissingError } from '../model/LibraryAccount'
import { LibraryReadDiagnostics } from '../common/LibraryReadDiagnostics'
import { BrowserLink } from '../common/BrowserLink'
import { LibraryAccountSource, LibraryAccountRepository } from '../repository/LibraryAccountRepository'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { HttpError } from '../util/HttpUtil'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { CampusActionLabel } from '../components/CampusActionLabel'
import { getSymbolIcon } from '../common/DanXiIcons'
import { LibraryVerification } from '../components/LibraryVerification'
import { TopFade } from '../components/TopFade'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { ErrorNotice } from '../components/ErrorNotice'
import { settleScrollTouch } from '../common/ScrollTouch'

interface LibraryAccountParams { kind?: string }
interface LibraryRangeSnapshot { rows: LibraryAccountItem[]; page: number; more: boolean; offset: number }
class LibraryAccountList implements IDataSource {
  rows: LibraryAccountItem[] = []
  private listeners: DataChangeListener[] = []
  totalCount(): number { return this.rows.length }
  getData(index: number): LibraryAccountItem { return this.rows[index] }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener) }
  unregisterDataChangeListener(listener: DataChangeListener): void { const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1) }
  update(rows: LibraryAccountItem[]): void { this.rows = rows; for (const listener of this.listeners) listener.onDataReloaded() }
}
@Entry
@Component
export struct LibraryAccountPage {
  private webSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  source: LibraryAccountSource = new LibraryAccountRepository()
  initialKind: string = ''
  private scroller: Scroller = new Scroller()
  private list: LibraryAccountList = new LibraryAccountList()
  private rangeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.library_current') }, { text: $r('app.string.library_history') }
  ])
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(AppState.KEY_PERSON) @Watch('accountChanged') person: string = ''
  @State private kind: string = 'loans'
  @State private history: boolean = false
  @State private displayHistory: boolean = false
  @State private contentOpacity: number = 1
  @State private switching: boolean = false
  @State private rows: LibraryAccountItem[] = []
  @State private loading: boolean = false
  @State private paging: boolean = false
  @State private more: boolean = false
  @State private refreshing: boolean = false
  @State private error: string = ''
  @State private verification: boolean = false
  @State private dataMissing: boolean = false
  @State private webSheet: boolean = false
  @State private pendingId: string = ''
  private owner: string = ''
  private active: boolean = false
  private resumeRead: boolean = false
  private revision: number = 0
  private page: number = 1
  private ranges: Map<string, LibraryRangeSnapshot> = new Map()
  private rangeKey(): string { return this.kind + '/' + this.displayHistory }
  private saveRange(): void {
    if (this.rows.length === 0 && this.error) return
    this.ranges.set(this.rangeKey(), { rows: this.rows.slice(), page: this.page, more: this.more,
      offset: this.scroller.currentOffset()?.yOffset ?? 0 })
  }
  private restoreRange(): void {
    const saved = this.ranges.get(this.rangeKey())
    this.updateRows(saved?.rows ?? []); this.page = saved?.page ?? 1; this.more = saved?.more ?? false
    this.scroller.scrollTo({ xOffset: 0, yOffset: saved?.offset ?? 0 })
  }
  aboutToAppear(): void {
    this.active = true; const params = router.getParams() as LibraryAccountParams
    this.kind = (this.initialKind || params?.kind) === 'requests' ? 'requests' : 'loans'; this.load(false)
  }
  onPageShow(): void {
    this.active = true
    if (this.owner && this.owner !== this.source.owner()) this.accountChanged()
    else if (this.switching) { this.displayHistory = this.history; this.restoreRange(); this.switching = false; this.contentOpacity = 0; this.load(false) }
    else if (this.resumeRead) { this.resumeRead = false; this.load(false) }
  }
  onPageHide(): void { this.resumeRead = this.resumeRead || this.loading; this.active = false; this.revision++; this.loading = false; this.paging = false; this.refreshing = false }
  aboutToDisappear(): void { this.active = false; this.revision++; this.switching = false }
  accountChanged(): void { if (!this.active || this.owner === this.source.owner()) return; this.ranges.clear(); this.revision++; this.loading = false; this.paging = false; this.switching = false; this.displayHistory = this.history; this.contentOpacity = 1; this.updateRows([]); this.pendingId = ''; this.webSheet = false; this.load(false) }
  private updateRows(rows: LibraryAccountItem[]): void { this.rows = rows; this.list.update(rows) }
  private async load(force: boolean): Promise<void> {
    if (!this.active || this.loading) return
    this.resumeRead = false
    const revision = ++this.revision, owner = this.source.owner(); this.owner = owner; this.loading = true; this.error = ''; this.verification = false; this.dataMissing = false
    try { const result = await this.source.list(this.kind, this.history, 1, force)
      if (this.active && revision === this.revision && owner === this.source.owner()) {
        // Only opacity animates; replacing rows must not animate list geometry.
        this.updateRows(result.rows); this.more = result.hasMore; this.page = 1
        this.saveRange()
      }
    } catch (e) { if (this.active && revision === this.revision) { this.error = ErrorDiagnostics.message(e as Object); this.verification = e instanceof HttpError && e.statusCode === -2; this.dataMissing = this.kind === 'loans' && this.history && e instanceof LibraryDataMissingError; this.more = false } }
    finally { if (revision === this.revision) {
      this.loading = false; this.refreshing = false; this.switching = false
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.contentOpacity = 1 })
    } }
  }
  private async next(): Promise<void> {
    if (!this.active || this.loading || this.paging || !this.more) return
    const revision = this.revision, owner = this.owner; this.paging = true
    try { const result = await this.source.list(this.kind, this.history, this.page + 1, false)
      if (this.active && revision === this.revision && owner === this.source.owner()) { this.updateRows(this.rows.concat(result.rows.filter(row => !this.rows.some(old => old.id === row.id)))); this.page++; this.more = result.hasMore }
    } catch (e) { if (this.active && revision === this.revision) {
      this.error = ErrorDiagnostics.message(e as Object)
      this.verification = e instanceof HttpError && e.statusCode === -2
      this.dataMissing = this.kind === 'loans' && this.history && e instanceof LibraryDataMissingError; this.more = false
    } }
    finally { if (revision === this.revision) this.paging = false }
  }
  private change(history: boolean): void {
    if (history === this.history || this.pendingId) return
    this.saveRange()
    const revision: number = ++this.revision
    this.loading = true; this.paging = false; this.history = history; this.switching = true; this.more = false
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut, onFinish: () => {
      if (!this.active || revision !== this.revision) return
      this.displayHistory = history; this.restoreRange(); this.error = ''; this.dataMissing = false; this.loading = false
      this.load(false)
    } }, () => { this.contentOpacity = 0 })
  }
  private async verify(): Promise<void> {
    if (this.source instanceof LibraryAccountRepository && !AppState.isLoggedIn()) { await router.pushUrl({ url: 'pages/LoginPage' }); return }
    this.webSheetTransition.open(() => { if (this.active) this.webSheet = true }, () => this.getUIContext())
  }
  private openOfficial(): void {
    BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, 'https://opac.fudan.edu.cn/')
      .catch((error: Object) => { if (this.active) DiagnosticNavigation.feedback(this.getUIContext(), error) })
  }
  private action(row: LibraryAccountItem): void {
    if (this.pendingId) return
    this.getUIContext().showAlertDialog({ title: AppLanguage.text(this.kind === 'requests' ? $r('app.string.library_cancel_request') : $r('app.string.library_renew_confirm')), message: row.title,
      primaryButton: { value: AppLanguage.text($r('app.string.settings_cancel')), action: () => {} },
      secondaryButton: { value: AppLanguage.text(this.kind === 'requests' ? $r('app.string.library_cancel_request') : $r('app.string.library_renew')), action: () => { this.commit(row) } } })
  }
  private async commit(row: LibraryAccountItem): Promise<void> {
    if (this.pendingId) return
    this.pendingId = row.id; const owner = this.owner, revision = this.revision
    try { if (this.kind === 'requests') await this.source.cancel(row.requestId); else await this.source.renew(row)
      if (this.active && revision === this.revision && owner === this.source.owner()) this.load(true)
    } catch (e) { if (this.active) DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.library_action_failed'))) }
    finally { this.pendingId = '' }
  }
  @Builder
  Card(row: LibraryAccountItem) {
    Column({ space: 10 }) {
      Row({ space: 12 }) { Text(row.title).fontSize(18).lineHeight(26).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        if (row.status) Text(row.status).fontSize(13).fontColor(ThemeColors.primary) }.width('100%')
      if (row.author) Text(row.author).fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).width('100%')
      if (this.kind === 'loans') {
        if (row.dueDate) Text(AppLanguage.text($r('app.string.library_due'), this.languageRevision, row.dueDate.slice(0, 10))).fontSize(15).fontWeight(FontWeight.Medium).fontColor(!this.displayHistory && LibraryAccountParser.overdue(row.dueDate) ? CampusContentStyle.attention : ThemeColors.textPrimary).width('100%')
        if (row.loanDate) Text(AppLanguage.text($r('app.string.library_borrowed'), this.languageRevision, row.loanDate.slice(0, 10))).fontSize(13).fontColor(ThemeColors.textSecondary).width('100%')
        if (row.returnDate) Text(AppLanguage.text($r('app.string.library_returned'), this.languageRevision, row.returnDate.slice(0, 10))).fontSize(13).fontColor(ThemeColors.textSecondary).width('100%')
        if (!this.displayHistory) Row() { Text(AppLanguage.text($r('app.string.library_renew_count'), this.languageRevision, row.renewals)).fontSize(13).fontColor(ThemeColors.textSecondary).layoutWeight(1)
          Button() { CampusActionLabel({ label: $r('app.string.library_renew'), symbol: getSymbolIcon('refresh'), color: Color.White }) }
            .height(40).enabled(!this.pendingId && (row.renewalLimit < 0 || row.renewals < row.renewalLimit)).opacity(this.pendingId === row.id ? 0.5 : 1).backgroundColor(ThemeColors.primary).id('library-renew-' + row.id).onClick(() => { this.action(row) }) }.width('100%')
        if (row.library || row.location) Text([row.library, row.location].filter((value: string) => !!value).join(' · ')).fontSize(12).lineHeight(19).fontColor(ThemeColors.textSecondary).width('100%')
      } else {
        Text(row.pickup).fontSize(14).lineHeight(22).fontColor(ThemeColors.textSecondary).width('100%')
        if (row.expected) Text(AppLanguage.text($r('app.string.library_expected'), this.languageRevision, row.expected.slice(0, 10))).fontSize(13).fontColor(ThemeColors.textSecondary).width('100%')
        if (!this.displayHistory) Row() { if (row.queue > 0) Text(AppLanguage.text($r('app.string.library_queue'), this.languageRevision, row.queue)).fontSize(13).fontColor(ThemeColors.textSecondary).layoutWeight(1)
          else Blank().layoutWeight(1)
          Button() { CampusActionLabel({ label: $r('app.string.library_cancel_request'), symbol: getSymbolIcon('delete'), color: CampusContentStyle.attention }) }
            .height(40).backgroundColor(Color.Transparent).enabled(!this.pendingId).opacity(this.pendingId === row.id ? 0.5 : 1).id('library-cancel-' + row.id).onClick(() => { this.action(row) }) }.width('100%')
      }
    }.width('100%').padding(ThemeDimens.cardInset).backgroundColor($r('app.color.surface_fallback')).borderRadius(22).alignItems(HorizontalAlign.Start)
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          ListItem() {
            TabSegmentButtonV2({ items: this.rangeItems, selectedIndex: this.history ? 1 : 0,
              $selectedIndex: (index: number) => { this.change(index === 1) }, enableStateAnimation: true,
              itemFontColor: ColorMetrics.resourceColor(ThemeColors.textSecondary),
              itemSelectedFontColor: ColorMetrics.rgba(255, 255, 255),
              itemSelectedBackgroundColor: ColorMetrics.resourceColor(ThemeColors.primary),
              buttonBackgroundColor: ColorMetrics.resourceColor($r('app.color.campus_search_surface'))
            }).width('100%').id('library-range')
          }.padding({ top: px2vp(this.topPx) + 76 })
          ListItemGroup({ space: 12 }) {
          if (this.error) ListItem() {
            Column({ space: 12 }) {
              ErrorNotice({ message: this.error, summary: this.dataMissing ? AppLanguage.text($r('app.string.library_history_missing')) : '',
                logs: (): string => LibraryReadDiagnostics.report(this.source.owner()), controlId: 'library-account-diagnostics' })
              if (this.verification) FloatingActionButton({ label: $r('app.string.campus_verify_continue'), onAction: () => { this.verify() } }).width(160)
              else if (this.dataMissing) {
                Row({ space: 12 }) {
                  FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', onCard: true, controlHeight: 40,
                    actionEnabled: !this.loading, controlId: 'library-history-retry', onAction: () => { this.load(true) } }).width(40)
                  Button() { CampusActionLabel({ label: $r('app.string.library_official_query'), symbol: getSymbolIcon('web') }) }
                    .height(40).backgroundColor(Color.Transparent).id('library-history-official').onClick(() => { this.openOfficial() })
                }.width('100%').alignItems(VerticalAlign.Center)
              }
            }.width('100%').padding(ThemeDimens.cardInset).backgroundColor($r('app.color.surface_fallback')).borderRadius(22)
          }
          // Keep immutable response content in the key: renewal counts, due
          // dates and queue status can change while the item ID stays fixed.
          LazyForEach(this.list, (row: LibraryAccountItem) => { ListItem() { this.Card(row) } }, (row: LibraryAccountItem): string => this.kind + '/' + this.displayHistory + '/' + JSON.stringify(row))
          if (!this.loading && !this.error && this.rows.length === 0) ListItem() { Text($r('app.string.library_account_empty')).fontColor(ThemeColors.textSecondary).width('100%').padding(24) }
          if (this.more) ListItem() { Button($r('app.string.books_load_more')).enabled(!this.paging).onClick(() => { this.next() }) }
          }.opacity(this.contentOpacity).enabled(!this.switching)
        }.width('100%').height('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, bottom: Math.max(20, px2vp(this.bottomPx)) + 24 })
          .cachedCount(3).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).onReachEnd(() => { this.next() }).onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) })
      CenterLoadingProgress({ busy: this.loading })
      TopFade({ extent: px2vp(this.topPx) + 62 })
      Row({ space: 12 }) {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 44, onAction: () => { router.back() } }).width(44)
        Text(this.kind === 'requests' ? $r('app.string.library_my_requests') : $r('app.string.library_my_loans')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44, actionEnabled: !this.loading && !this.paging, controlId: 'library-account-refresh', onAction: () => { this.verification ? this.verify() : this.load(true) } }).width(44)
      }.height(56).width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter }).margin({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgEnd).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.webSheet, this.Verification(), this.webSheetTransition.options(this.webSheet, { height: '94%', showClose: false, dragBar: true }))
  }
  @Builder
  Verification() { LibraryVerification({ onVerified: () => { this.webSheet = false; this.load(true) }, onClose: () => { this.webSheet = false } }) }
}
