import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice } from './ErrorNotice'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { AcademicCalendar } from '../common/AcademicCalendar'
import { AppLanguage } from '../common/AppLanguage'
import { ThemeColors } from '../common/Theme'
import { getSymbolIcon } from '../common/DanXiIcons'
import { BrowserLink } from '../common/BrowserLink'
import { CalendarTerm, TeachingCalendar } from '../model/TeachingCalendar'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { CalendarRepository } from '../repository/CalendarRepository'

@Component
export struct CalendarSettings {
  @Prop authenticationVisible: boolean = true
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(AcademicCalendar.KEY_MODE) mode: string = 'manual'
  @StorageLink(AcademicCalendar.KEY_START) start: string = ''
  @StorageLink('calendar_source') source: string = ''
  @StorageLink('calendar_updated') updatedAt: number = 0
  @State private syncing: boolean = false
  @State private error: string = ''
  private active: boolean = false
  private generation: number = 0

  aboutToAppear(): void {
    this.active = true
  }

  aboutToDisappear(): void { this.active = false; this.generation++; this.syncing = false }

  private async sync(allowAuthentication: boolean = true): Promise<void> {
    if (this.syncing) return
    this.syncing = true; this.error = ''
    const generation: number = ++this.generation
    const owner: string = AppStorage.get<string>('app_person') ?? ''
    try {
      const terms: CalendarTerm[] = await CalendarRepository.sync(allowAuthentication, allowAuthentication,
      (): boolean => this.active && this.authenticationVisible && AppStorage.get<boolean>('app_foreground') !== false &&
        generation === this.generation && owner === (AppStorage.get<string>('app_person') ?? ''))
      if (!this.active || !this.authenticationVisible || AppStorage.get<boolean>('app_foreground') === false ||
        generation !== this.generation || owner !== (AppStorage.get<string>('app_person') ?? '')) return
      const term: CalendarTerm | undefined = TeachingCalendar.termAtDate(terms)
      if (term === undefined) throw new Error(AppLanguage.text($r('app.string.calendar_sync_failed'), this.languageRevision))
      await AcademicCalendar.setManual(term.startDate, term.source)
    }
    catch (e) {
      if (this.active && this.authenticationVisible && AppStorage.get<boolean>('app_foreground') !== false &&
        generation === this.generation && owner === (AppStorage.get<string>('app_person') ?? '')) {
        this.error = ErrorDiagnostics.message(e as Object)
      }
    } finally { if (this.active && generation === this.generation) this.syncing = false }
  }

  private chooseMonday(): void {
    const date = this.start ? new Date(this.start + 'T00:00:00') : new Date()
    if (!this.start) date.setDate(date.getDate() - (date.getDay() + 6) % 7)
    this.getUIContext().showDatePickerDialog({ selected: date,
      onDateAccept: (value: Date): void => { this.saveMonday(value) } })
  }

  private async saveMonday(date: Date): Promise<void> {
    const value = TeachingCalendar.iso(date)
    if (!TeachingCalendar.validMonday(value)) {
      promptAction.showToast({ message: $r('app.string.ui_choose_the_monday_of_the_first_teaching_week') }); return
    }
    this.generation++; this.syncing = false
    try { await AcademicCalendar.setManual(value); this.error = '' }
    catch (e) { DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.ui_could_not_save_semester_start_please_retry'))) }
  }

  @Builder
  ChoiceNote() {
    Column() {
      Text($r('app.string.calendar_choice_hint')).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
    }.width(268).padding({ left: 8, right: 8, top: 8, bottom: 8 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  Choices() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.calendar_manual') })
          .onClick(() => { this.chooseMonday() })
        MenuItem({ content: $r('app.string.calendar_sync_now') }).enabled(!this.syncing)
          .onClick(() => { this.sync() })
      }
      MenuItem(() => { this.ChoiceNote() }).enabled(false)
    }.width(300)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        SymbolGlyph(getSymbolIcon('timetable')).fontSize(22).fontColor([ThemeColors.primary])
        Text($r('app.string.ui_monday_of_the_first_teaching_week')).fontSize(14).lineHeight(20).fontColor(ThemeColors.textPrimary)
          .layoutWeight(1)
        Row({ space: 4 }) {
          Text($r('app.string.calendar_manual'))
            .fontSize(13).fontColor(ThemeColors.primary)
          SymbolGlyph(getSymbolIcon('expand')).fontSize(16).fontColor([ThemeColors.textSecondary])
        }.height(28).padding({ left: 6, right: 6 }).borderRadius(12).bindMenu(this.Choices)
          .accessibilityRole(AccessibilityRoleType.BUTTON)
      }.alignItems(VerticalAlign.Center)
      Text(this.start || $r('app.string.calendar_date_unknown')).fontSize(13).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%')
      if (this.syncing) {
        Row({ space: 8 }) { LoadingProgress().width(18).height(18); Text($r('app.string.calendar_syncing')).fontSize(12) }
      }
      if (this.error) {
        ErrorNotice({ message: this.error, controlId: 'calendarsettings-diagnostics', textSize: 12, textColor: ThemeColors.error }).width('100%')
      }
      Text($r('app.string.calendar_manual_sync_hint')).fontSize(12).lineHeight(18)
        .fontColor(ThemeColors.textSecondary).width('100%')
      if (this.source) {
        Text(AppLanguage.text($r('app.string.calendar_source'), this.languageRevision) + ' · ' +
          (this.source.includes('fdjwgl') ? AppLanguage.text($r('app.string.calendar_source_account'), this.languageRevision) :
            AppLanguage.text($r('app.string.calendar_source_official'), this.languageRevision)) +
          (this.updatedAt > 0 ? ' · ' + TeachingCalendar.iso(new Date(this.updatedAt)) : ''))
          .fontSize(12).lineHeight(18).fontColor(ThemeColors.primary).width('100%')
          .onClick(() => { BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, this.source)
            .catch((diagnosticFailure: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.announcement_open_failed'))) }) })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
      .backgroundColor($r('app.color.surface_fallback')).borderRadius(16)
  }
}
