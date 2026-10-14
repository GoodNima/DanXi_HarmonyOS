import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { LibraryHolding } from '../model/LibraryBooks'
import { LibraryRequestOptions, LibraryPickup } from '../model/LibraryAccount'
import { LibraryAccountRepository, LibraryAccountSource } from '../repository/LibraryAccountRepository'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { HttpError } from '../util/HttpUtil'
import { ThemeColors } from '../common/Theme'
import { AppLanguage } from '../common/AppLanguage'
import { ClassroomPresentation } from '../common/ClassroomPresentation'
import { LibraryVerification } from './LibraryVerification'
import { ErrorNotice } from './ErrorNotice'
import { CenterLoadingProgress } from './CenterLoadingProgress'
import { FloatingActionButton } from './FloatingActionButton'
import { CampusActionLabel } from './CampusActionLabel'
import { getSymbolIcon } from '../common/DanXiIcons'

@Component
export struct LibraryRequestEditor {
  private webSheetTransition: SheetTransitionGuard = new SheetTransitionGuard()
  holding: LibraryHolding = new LibraryHolding()
  source: LibraryAccountSource = new LibraryAccountRepository()
  onCompleted: () => void = () => {}
  @State private options: LibraryRequestOptions | undefined = undefined
  @State private pickup: string = ''
  @State private day: string = ClassroomPresentation.day(new Date())
  @State private replace: boolean = true
  @State private loading: boolean = false
  @State private error: string = ''
  @State private verification: boolean = false
  @State private webSheet: boolean = false
  private active: boolean = false
  aboutToAppear(): void { this.active = true; this.load() }
  aboutToDisappear(): void { this.active = false }
  private async load(): Promise<void> {
    if (this.loading) return; this.loading = true; this.error = ''; this.verification = false
    const owner = this.source.owner()
    try { const options = await this.source.options(this.holding)
      if (this.active && owner === this.source.owner()) { this.options = options; this.pickup = options.locations[0]?.code ?? ''; this.day = ClassroomPresentation.day(ClassroomPresentation.dateOffset(new Date(), Math.max(0, options.policy.requestDateRange))) }
    } catch (e) { if (this.active) { this.error = ErrorDiagnostics.message(e as Object); this.verification = e instanceof HttpError && e.statusCode === -2 } }
    finally { this.loading = false }
  }
  private date(): void {
    if (!this.options) return
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.day + 'T12:00:00'), start: new Date(), end: ClassroomPresentation.dateOffset(new Date(), Math.max(0, this.options.policy.requestDateRange)), onDateAccept: (value: Date) => { this.day = ClassroomPresentation.day(value) } })
  }
  private async submit(): Promise<void> {
    if (this.loading || !this.pickup || !this.options) return; this.loading = true; this.error = ''; const owner = this.source.owner()
    try { await this.source.request(this.holding, this.pickup, this.day, this.replace); if (this.active && owner === this.source.owner()) this.onCompleted() }
    catch (e) { if (this.active) { this.error = ErrorDiagnostics.message(e as Object); this.verification = e instanceof HttpError && e.statusCode === -2 } }
    finally { this.loading = false }
  }
  @Builder
  Verification() { LibraryVerification({ onVerified: () => { this.webSheet = false; this.load() } }) }
  build() {
    Stack() {
      Scroll() { Column({ space: 18 }) {
        Text($r('app.string.library_request_book')).fontSize(21).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
        Text([this.holding.library, this.holding.location, this.holding.callNumber].filter((value: string) => !!value).join('\n')).fontSize(14).lineHeight(23).fontColor(ThemeColors.textSecondary).width('100%')
        if (this.error) ErrorNotice({ message: this.error, controlId: 'library-request-diagnostics' })
        if (this.verification) Button($r('app.string.campus_verify_continue')).onClick(() => {
          this.webSheetTransition.open(() => { if (this.active) this.webSheet = true }, () => this.getUIContext())
        })
        else if (this.error && this.options === undefined) FloatingActionButton({ label: $r('app.string.ui_reload'), icon: 'refresh', zeroContentPadding: true, controlHeight: 44, actionEnabled: !this.loading, onAction: () => { this.load() } }).width(44)
        if (this.options !== undefined) {
          if (this.options.locations.length === 0) Text($r('app.string.library_no_pickup')).fontColor(ThemeColors.textSecondary)
          else Column({ space: 8 }) { Text($r('app.string.library_pickup')).fontColor(ThemeColors.textSecondary).width('100%')
            Select(this.options.locations.map((row: LibraryPickup): SelectOption => ({ value: row.name }))).selected(this.options.locations.findIndex((row: LibraryPickup) => row.code === this.pickup)).value(this.options.locations.find((row: LibraryPickup) => row.code === this.pickup)?.name ?? '').width('100%').onSelect((index: number) => { this.pickup = this.options?.locations[index]?.code ?? '' }) }.width('100%')
          Row() { Text($r('app.string.library_pickup_date')).fontColor(ThemeColors.textSecondary).layoutWeight(1)
            Button() { CampusActionLabel({ label: this.day, symbol: getSymbolIcon('timetable') }) }
              .height(40).backgroundColor(Color.Transparent).onClick(() => { this.date() }) }.width('100%')
          Row() { Text($r('app.string.library_allow_replace')).fontColor(ThemeColors.textPrimary).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.replace }).onChange((value: boolean) => { this.replace = value }) }.width('100%')
          Button() { CampusActionLabel({ label: $r('app.string.library_submit_request'), symbol: getSymbolIcon('check'), color: Color.White }) }
            .width('100%').height(44).backgroundColor(ThemeColors.primary).enabled(!this.loading && !!this.pickup).onClick(() => { this.submit() })
        }
      }.width('100%').padding({ left: 20, right: 20, top: 48, bottom: 24 }).alignItems(HorizontalAlign.Start) }.width('100%').constraintSize({ maxHeight: 600 }).align(Alignment.Top)
      CenterLoadingProgress({ busy: this.loading }).width(36).height(36)
      Row().width(0).height(0).bindSheet($$this.webSheet, this.Verification(), this.webSheetTransition.options(this.webSheet, { height: '90%', showClose: true, dragBar: false }))
    }.width('100%')
  }
}
