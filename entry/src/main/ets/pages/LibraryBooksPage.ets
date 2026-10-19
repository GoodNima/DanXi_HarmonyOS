import { ReadableText } from '../common/ReadableText'
import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { router } from '@kit.ArkUI'
import { AppLanguage } from '../common/AppLanguage'
import { Constant } from '../common/Constant'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { getSymbolIcon } from '../common/DanXiIcons'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { LibraryBook, LibraryHolding } from '../model/LibraryBooks'
import { LibraryBooksRepository, LibraryBooksSource, DefaultLibraryBooksSource } from '../repository/LibraryBooksRepository'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { CampusActionLabel } from '../components/CampusActionLabel'
import { LibraryRequestEditor } from '../components/LibraryRequestEditor'
import { TopFade } from '../components/TopFade'
import { ErrorNotice } from '../components/ErrorNotice'
import { CenterLoadingProgress } from '../components/CenterLoadingProgress'
import { settleScrollTouch } from '../common/ScrollTouch'

class BookListSource implements IDataSource {
  rows: LibraryBook[] = []
  listeners: DataChangeListener[] = []
  totalCount(): number { return this.rows.length }
  getData(index: number): LibraryBook { return this.rows[index] }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener) }
  unregisterDataChangeListener(listener: DataChangeListener): void { const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1) }
  update(rows: LibraryBook[]): void { this.rows = rows; for (const listener of this.listeners) listener.onDataReloaded() }
}
class HoldingListSource implements IDataSource {
  rows: LibraryHolding[] = []
  listeners: DataChangeListener[] = []
  totalCount(): number { return this.rows.length }
  getData(index: number): LibraryHolding { return this.rows[index] }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener) }
  unregisterDataChangeListener(listener: DataChangeListener): void { const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1) }
  update(rows: LibraryHolding[]): void { this.rows = rows; for (const listener of this.listeners) listener.onDataReloaded() }
}

@Entry
@Component
export struct LibraryBooksPage {
  private requestSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  source: LibraryBooksSource = new DefaultLibraryBooksSource()
  private scroller: Scroller = new Scroller()
  private list: BookListSource = new BookListSource()
  private stockList: HoldingListSource = new HoldingListSource()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @State private requestSheet: boolean = false
  @State private requestHolding: LibraryHolding = new LibraryHolding()
  @State private query: string = ''
  @State private submittedQuery: string = ''
  @State private pinned: LibraryBook[] = []
  @State private selected: LibraryBook | undefined = undefined
  @State private holdings: LibraryHolding[] = []
  @State private rowCount: number = 0
  @State private loading: boolean = false
  @State private paging: boolean = false
  @State private more: boolean = false
  @State private pinPending: boolean = false
  @State private refreshing: boolean = false
  @State private error: string = ''
  @State private holdingsError: string = ''
  private active: boolean = false
  private revision: number = 0
  private page: number = 0
  private searchTimer: number = -1
  private savedOffset: number = 0
  private savedPage: number = 0
  private savedMore: boolean = false
  private savedError: string = ''
  private savedSearchPending: boolean = false

  aboutToAppear(): void { this.active = true; this.restorePinned() }
  onPageShow(): void { this.active = true }
  onPageHide(): void { this.active = false }
  aboutToDisappear(): void { this.active = false; this.revision++; if (this.searchTimer >= 0) clearTimeout(this.searchTimer) }
  onBackPress(): boolean { if (this.selected !== undefined) { this.back(); return true } return false }
  private async restorePinned(): Promise<void> {
    const pinned = await LibraryBooksRepository.pinned()
    if (!this.active) return
    this.pinned = pinned; if (!this.submittedQuery && this.selected === undefined) this.updateRows(pinned)
  }
  private updateRows(rows: LibraryBook[]): void { this.list.update(rows); this.rowCount = rows.length }
  private updateHoldings(rows: LibraryHolding[]): void { this.holdings = rows; this.stockList.update(rows) }
  private openAccount(kind: string): void {
    router.pushUrl({ url: 'pages/LibraryAccountPage', params: { kind } }).catch((failure: Object) => {
      if (this.active) DiagnosticNavigation.feedback(this.getUIContext(), failure)
    })
  }
  private searchChanged(value: string): void {
    this.query = value; this.revision++; this.loading = false; this.paging = false
    if (this.searchTimer >= 0) clearTimeout(this.searchTimer)
    this.searchTimer = -1
    if (!value.trim()) { this.submittedQuery = ''; this.error = ''; this.more = false; this.page = 0; this.updateRows(this.pinned); return }
    this.searchTimer = setTimeout(() => { this.searchTimer = -1; this.search(false) }, 320)
  }
  private async search(force: boolean): Promise<void> {
    if (!this.active || this.selected !== undefined) return
    const query: string = this.query.trim()
    if (!query) { this.submittedQuery = ''; this.updateRows(this.pinned); this.refreshing = false; return }
    if (this.loading && this.submittedQuery === query) return
    const revision: number = ++this.revision
    this.submittedQuery = query; this.loading = true; this.paging = false; this.error = ''; this.page = 0; this.more = false
    try {
      const data = await this.source.search(query, 1, force)
      if (!this.active || revision !== this.revision || this.selected !== undefined) return
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.updateRows(data.rows); this.more = data.hasMore; this.page = 1 })
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 })
    } catch (e) { if (this.active && revision === this.revision) { this.error = ErrorDiagnostics.message(e as Object); this.updateRows([]) } }
    finally { if (revision === this.revision) { this.loading = false; this.refreshing = false } }
  }
  private async next(): Promise<void> {
    if (!this.active || this.loading || this.paging || !this.more) return
    const revision: number = this.revision, page: number = this.page + 1, selected: LibraryBook | undefined = this.selected
    this.paging = true; if (selected !== undefined) this.holdingsError = ''; else this.error = ''
    try {
      if (selected !== undefined) {
        const result = await this.source.holdings(selected.id, page, false)
        if (!this.active || revision !== this.revision || this.selected?.id !== selected.id) return
        this.updateHoldings(this.holdings.concat(result.rows.filter((row: LibraryHolding) => !this.holdings.some((old: LibraryHolding) => old.id === row.id))))
        this.more = result.hasMore
      } else {
        const result = await this.source.search(this.submittedQuery, page, false)
        if (!this.active || revision !== this.revision) return
        this.updateRows(this.list.rows.concat(result.rows.filter((row: LibraryBook) => !this.list.rows.some((old: LibraryBook) => old.id === row.id))))
        this.more = result.hasMore
      }
      this.page = page
    } catch (e) { if (this.active && revision === this.revision) { if (selected !== undefined) this.holdingsError = ErrorDiagnostics.message(e as Object); else this.error = ErrorDiagnostics.message(e as Object) } }
    finally { if (revision === this.revision) this.paging = false }
  }
  private open(book: LibraryBook): void {
    this.savedOffset = this.scroller.currentOffset().yOffset; this.savedPage = this.page; this.savedMore = this.more; this.savedError = this.error
    this.savedSearchPending = this.loading || this.searchTimer >= 0
    this.revision++; this.loading = false; this.paging = false
    if (this.searchTimer >= 0) clearTimeout(this.searchTimer); this.searchTimer = -1
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.selected = book; this.updateHoldings([]); this.error = ''; this.holdingsError = '' })
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); this.loadDetail(false)
  }
  private async loadDetail(force: boolean): Promise<void> {
    if (this.selected === undefined || this.loading) return
    const id: string = this.selected.id, revision: number = ++this.revision
    this.loading = true; this.paging = false; this.more = false; this.error = ''; this.holdingsError = ''
    const detail: Promise<void> = this.source.detail(id, force).then((book: LibraryBook) => {
      if (this.active && revision === this.revision && this.selected?.id === id) this.selected = book
    }).catch((e: Object) => { if (this.active && revision === this.revision) this.error = ErrorDiagnostics.message(e) })
    const stock: Promise<void> = this.source.holdings(id, 1, force).then(result => {
      if (this.active && revision === this.revision && this.selected?.id === id) { this.updateHoldings(result.rows); this.more = result.hasMore; this.page = 1 }
    }).catch((e: Object) => { if (this.active && revision === this.revision) this.holdingsError = ErrorDiagnostics.message(e) })
    await Promise.all([detail, stock]); if (revision === this.revision) { this.loading = false; this.refreshing = false }
  }
  private back(): void {
    if (this.selected === undefined) { router.back(); return }
    this.revision++; this.loading = false; this.paging = false; this.error = this.savedError; this.holdingsError = ''
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.selected = undefined; this.more = this.savedMore })
    this.page = this.savedPage
    if (!this.submittedQuery) this.updateRows(this.pinned)
    if (this.savedSearchPending) { this.savedSearchPending = false; this.search(false); return }
    setTimeout(() => { if (this.active && this.selected === undefined) this.scroller.scrollTo({ xOffset: 0, yOffset: this.savedOffset }) }, 0)
  }
  private async togglePin(): Promise<void> {
    if (this.pinPending || this.selected === undefined) return
    const book: LibraryBook = this.selected; this.pinPending = true
    try { await LibraryBooksRepository.togglePin(book); await this.restorePinned() }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.books_pin_failed'))) }
    finally { this.pinPending = false }
  }
  private isPinned(): boolean { return this.selected !== undefined && this.pinned.some((row: LibraryBook) => row.id === this.selected?.id) }
  private reload(): void { if (this.selected !== undefined) this.loadDetail(true); else if (this.query.trim()) this.search(true); else { this.restorePinned(); this.refreshing = false } }
  @Builder
  Search() {
    Row({ space: 12 }) {
      Button() { CampusActionLabel({ label: $r('app.string.library_my_loans'), symbol: getSymbolIcon('library') }) }
        .layoutWeight(1).height(44).backgroundColor($r('app.color.surface_fallback')).id('books-my-loans').onClick(() => { this.openAccount('loans') })
      Button() { CampusActionLabel({ label: $r('app.string.library_my_requests'), symbol: getSymbolIcon('timetable') }) }
        .layoutWeight(1).height(44).backgroundColor($r('app.color.surface_fallback')).id('books-my-requests').onClick(() => { this.openAccount('requests') })
    }.width('100%')
    Row({ space: 4 }) {
      TextInput({ text: this.query, placeholder: $r('app.string.books_search') }).layoutWeight(1).height(46).fontSize(15)
        .fontColor(ThemeColors.textPrimary).backgroundColor(Color.Transparent).defaultFocus(false).enterKeyType(EnterKeyType.Search).id('books-search')
        .onChange((value: string) => { this.searchChanged(value) }).onSubmit(() => { if (this.searchTimer >= 0) clearTimeout(this.searchTimer); this.search(false) })
      if (this.query) Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(20).fontColor([ThemeColors.textSecondary]) }
        .width(38).height(38).backgroundColor(Color.Transparent).id('books-search-clear').onClick(() => { this.searchChanged('') })
    }.width('100%').padding({ left: 4, right: 8 }).backgroundColor($r('app.color.campus_search_surface')).borderRadius(24)
    Text(ReadableText.resource(this.submittedQuery ? $r('app.string.books_results_hint') : $r('app.string.books_pinned_hint'))).fontSize(12).lineHeight(20).lineBreakStrategy(LineBreakStrategy.GREEDY).fontColor(ThemeColors.textSecondary).width('100%')
  }
  @Builder
  BookCard(book: LibraryBook) {
    Column({ space: 8 }) {
      Text(book.title).fontSize(18).lineHeight(26).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
      if (book.authors.length > 0) Text(book.authors.join('、')).fontSize(14).lineHeight(21).fontColor(ThemeColors.textSecondary).width('100%')
      Text([book.publisher, book.year].filter((value: string) => value.length > 0).join(' · ')).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
      Row() { Text($r('app.string.books_view_holdings')).fontSize(13).fontColor(ThemeColors.primary).layoutWeight(1)
        SymbolGlyph(getSymbolIcon('forward')).fontSize(14).fontColor([ThemeColors.textSecondary]) }.width('100%')
    }.width('100%').padding(ThemeDimens.cardInset).borderRadius(22).backgroundColor($r('app.color.surface_fallback'))
      .onClick(() => { this.open(book) }).id('book-card-' + book.id).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
  }
  @Builder
  Field(label: ResourceStr, value: string) {
    if (value) Row({ space: 12 }) { Text(label).fontSize(12).fontColor(ThemeColors.textSecondary).width(62)
      Text(value).fontSize(14).lineHeight(22).fontColor(ThemeColors.textPrimary).layoutWeight(1).copyOption(CopyOptions.LocalDevice) }.width('100%')
  }
  @Builder
  BookDetail() {
    Column({ space: 12 }) {
      Text(this.selected?.title ?? '').fontSize(21).lineHeight(29).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
      this.Field($r('app.string.books_authors'), this.selected?.authors.join('、') ?? '')
      this.Field($r('app.string.books_publisher'), [this.selected?.publisher ?? '', this.selected?.year ?? ''].filter((value: string) => !!value).join(' · '))
      this.Field('ISBN', this.selected?.isbn ?? '')
      if (this.selected?.summary) { Divider().color(ThemeColors.divider); Text(this.selected.summary).fontSize(14).lineHeight(23).fontColor(ThemeColors.textSecondary).width('100%').copyOption(CopyOptions.LocalDevice) }
    }.width('100%').padding(ThemeDimens.cardInset).backgroundColor($r('app.color.surface_fallback')).borderRadius(22)
    Text($r('app.string.books_holdings')).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%').margin({ top: 6 })
    if (this.holdingsError) ErrorNotice({ message: this.holdingsError, controlId: 'books-holdings-diagnostics' })
    Text(ReadableText.resource($r('app.string.books_holdings_hint'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
    if (!this.loading && !this.holdingsError && this.holdings.length === 0) Text($r('app.string.books_no_holdings')).fontSize(14).fontColor(ThemeColors.textSecondary).padding(20)
  }
  @Builder
  HoldingCard(item: LibraryHolding) {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Text(item.location || item.library).fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          Text(item.status).fontSize(14).fontWeight(FontWeight.Medium).fontColor(/^(可借|可外借|可供借阅|在馆|在架)/.test(item.status) ? CampusContentStyle.available : CampusContentStyle.warning)
        }.width('100%')
        if (item.library) Text(item.library).fontSize(13).fontColor(ThemeColors.textSecondary).width('100%')
        this.Field($r('app.string.books_call_number'), item.callNumber)
        if (item.volume) Text(item.volume).fontSize(12).fontColor(ThemeColors.textSecondary).width('100%')
        if (item.barcode && item.libraryCode && item.locationCode && item.canRequest !== false) Button() {
          CampusActionLabel({ label: $r('app.string.library_request_book'), symbol: getSymbolIcon('timetable') })
        }.backgroundColor(Color.Transparent).id('book-request-' + item.id).onClick(() => { this.requestSheetTransition.open(() => {
          if (this.active) { this.requestHolding = item; this.requestSheet = true }
        }, () => this.getUIContext()) })
      }.width('100%').padding(ThemeDimens.cardInset).backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
  }
  @Builder
  RequestEditor() { LibraryRequestEditor({ holding: this.requestHolding, onCompleted: () => { this.requestSheet = false; this.getUIContext().getPromptAction().showToast({ message: AppLanguage.text($r('app.string.library_request_success')) }) } }) }
  build() {
    Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          ListItem() { Column({ space: 12 }) { if (this.selected === undefined) this.Search(); else this.BookDetail()
            if (this.error) ErrorNotice({ message: this.error, controlId: 'books-diagnostics' }).padding({ left: 12, right: 12 })
            if ((this.error || this.holdingsError) && !this.loading) FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44, onAction: () => { this.reload() } }).width(44)
          }.width('100%').padding({ top: px2vp(this.topPx) + 76 }) }
          if (this.selected === undefined) {
            LazyForEach(this.list, (book: LibraryBook) => { ListItem() { this.BookCard(book) } }, (book: LibraryBook): string => book.id)
            if (!this.loading && !this.error && this.rowCount === 0) ListItem() {
              Column({ space: 12 }) { Image($r('app.media.library_books')).width(36).height(36).fillColor(ThemeColors.textSecondary)
                Text(this.submittedQuery ? $r('app.string.ui_no_data') : $r('app.string.books_empty')).fontSize(15).fontColor(ThemeColors.textSecondary) }.width('100%').padding({ top: 32, bottom: 32 })
            }
          } else {
            LazyForEach(this.stockList, (item: LibraryHolding) => { ListItem() { this.HoldingCard(item) } }, (item: LibraryHolding): string => item.id)
          }
          if (this.more) ListItem() {
            Text(this.paging ? $r('app.string.ui_loading') : $r('app.string.books_load_more')).fontSize(13).fontColor(ThemeColors.primary).width('100%').padding(16)
              .id('books-load-more').onClick(() => { this.next() })
          }
        }.width('100%').height('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, bottom: Math.max(20, px2vp(this.bottomPx)) + 24 })
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).cachedCount(3)
          .onReachEnd(() => { this.next() }).onTouch((event: TouchEvent) => { settleScrollTouch(this.scroller, event) })
      CenterLoadingProgress({ busy: this.loading })
      TopFade({ extent: px2vp(this.topPx) + 62 })
      Row({ space: 12 }) {
        Row({ space: 12 }) {
          FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 44, onAction: () => { this.back() } }).width(44)
          if (this.selected !== undefined) Blank().width(44)
        }.width(this.selected !== undefined ? 100 : 44)
        Text($r('app.string.feature_library_books')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
        if (this.selected !== undefined) FloatingActionButton({ label: this.isPinned() ? $r('app.string.books_unpin') : $r('app.string.books_pin'), icon: 'pin', controlHeight: 44,
          labelColor: this.isPinned() ? ThemeColors.primary : ThemeColors.textPrimary, actionEnabled: !this.pinPending,
          controlId: 'book-pin', onAction: () => { this.togglePin() } }).width(44)
        FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44, actionEnabled: !this.loading && !this.paging,
          controlId: 'books-refresh', onAction: () => { this.reload() } }).width(44)
      }.height(56).width('100%').padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter }).margin({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgEnd).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.requestSheet, this.RequestEditor(), this.requestSheetTransition.options(this.requestSheet, { height: SheetSize.FIT_CONTENT, showClose: true, dragBar: false }))
  }
}
