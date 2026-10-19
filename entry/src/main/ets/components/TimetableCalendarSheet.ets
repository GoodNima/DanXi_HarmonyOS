import { ReadableText } from '../common/ReadableText'
import { common } from '@kit.AbilityKit'
import { AppLanguage } from '../common/AppLanguage'
import { ThemeColors } from '../common/Theme'
import { Course } from '../model/Academic'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { TimetableCalendar } from '../model/TimetableCalendar'
import { TimetableCalendarRepository, CalendarExportResult } from '../repository/TimetableCalendarRepository'
import { FloatingActionButton } from './FloatingActionButton'
import { CenterLoadingProgress } from './CenterLoadingProgress'
import { ErrorNotice } from './ErrorNotice'

@Component
export struct TimetableCalendarSheet {
  courses: Course[] = []
  monday: string = ''
  owner: string = ''
  onBusy: (value: boolean) => void = () => {}
  @State private selected: string[] = []
  @State private busy: boolean = false
  @State private error: string = ''
  @State private result: string = ''
  private active: boolean = false
  aboutToAppear(): void { this.active = true; this.selected = this.groups().map((course: Course) => TimetableCalendar.group(course)) }
  aboutToDisappear(): void { this.active = false }
  private groups(): Course[] { return this.courses.filter((course: Course, index: number) =>
    this.courses.findIndex((row: Course) => TimetableCalendar.group(row) === TimetableCalendar.group(course)) === index) }
  private toggle(group: string): void {
    if (this.busy) return
    this.selected = this.selected.includes(group) ? this.selected.filter((value: string) => value !== group) : this.selected.concat([group])
    this.result = ''; this.error = ''
  }
  private async write(): Promise<void> {
    if (this.busy || this.selected.length === 0) return
    this.busy = true; this.onBusy(true); this.error = ''; this.result = ''
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const courses: Course[] = this.courses.filter((course: Course) => this.selected.includes(TimetableCalendar.group(course)))
      const result: CalendarExportResult = await TimetableCalendarRepository.export(context, this.owner, courses, this.monday)
      if (this.active) this.result = AppLanguage.text($r('app.string.timetable_calendar_done'), 0, String(result.total), String(result.added + result.updated), String(result.unchanged))
    } catch (e) { if (this.active) this.error = ErrorDiagnostics.message(e as Object) }
    finally { this.busy = false; this.onBusy(false) }
  }
  build() {
    Stack() {
      Column({ space: 14 }) {
        Row({ space: 12 }) {
          Text($r('app.string.timetable_export')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          FloatingActionButton({ label: this.selected.length === this.groups().length ? $r('app.string.timetable_unselect_all') : $r('app.string.timetable_select_all'),
            actionEnabled: !this.busy, onAction: () => { this.selected = this.selected.length === this.groups().length ? [] :
              this.groups().map((course: Course) => TimetableCalendar.group(course)); this.result = '' } }).width(88)
        }.width('100%').padding({ right: 52 })
        Text(ReadableText.keepWords(AppLanguage.text($r('app.string.timetable_calendar_hint'), 0, this.monday))).fontSize(13).lineHeight(21).lineBreakStrategy(LineBreakStrategy.GREEDY).fontColor(ThemeColors.textSecondary).width('100%')
        List({ space: 10 }) {
          ForEach(this.groups(), (course: Course) => {
            ListItem() {
              Row({ space: 12 }) {
                Checkbox({ name: course.name }).select(this.selected.includes(TimetableCalendar.group(course))).enabled(!this.busy)
                  .onChange(() => { this.toggle(TimetableCalendar.group(course)) })
                Column({ space: 5 }) {
                  Text(course.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('100%')
                  if (course.code) Text(course.code).fontSize(12).fontColor(ThemeColors.textSecondary)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.padding(12).width('100%').backgroundColor(ThemeColors.cardBg).borderRadius(16)
            }.id('calendar-course-' + course.id)
          }, (course: Course) => TimetableCalendar.group(course))
        }.width('100%').height(Math.max(72, Math.min(this.groups().length * 82, 300)))
        if (this.error) ErrorNotice({ message: this.error, controlId: 'calendar-export-diagnostics' }).width('100%')
        if (this.result) Text(this.result).fontSize(14).lineHeight(22).fontColor(ThemeColors.primary).width('100%').id('calendar-export-result')
        Button($r('app.string.timetable_export')).enabled(!this.busy && this.selected.length > 0).width('100%').height(44)
          .backgroundColor(ThemeColors.primary).fontColor(Color.White).onClick(() => { this.write() }).id('calendar-export-confirm')
      }.width('100%').padding({ top: 8, bottom: 20, left: 20, right: 20 }).alignItems(HorizontalAlign.Start)
      // Bound the overlay itself so it cannot expand a FIT_CONTENT sheet.
      CenterLoadingProgress({ busy: this.busy }).width(48).height(48)
    }.width('100%').backgroundColor(ThemeColors.bgStart)
  }
}
