import { ThemeColors } from '../common/Theme'
import { TimetableHelper } from '../model/Academic'
import { TimetableSchedule } from '../model/TimetableSchedule'

/** Shared native ArkUI grid for period labels. The enclosing native Scroll or
 * List owns all motion; this fixed grid never installs a competing gesture. */
@Component
export struct PeriodTimeAxis {
  @Prop periodCount: number = 15
  @Prop rowHeight: number = 58
  @Prop axisWidth: number = 52
  @Prop topDivider: boolean = false
  @Prop controlPrefix: string = 'timetable-period-'
  build() {
    Grid() {
      ForEach(TimetableSchedule.UNITS.slice(0, this.periodCount), (unit: number) => {
        GridItem() {
          Column({ space: 4 }) {
            Text(String(unit)).fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
            Text(TimetableHelper.getSlotStartTime(unit) + '\n' + TimetableSchedule.endTime(unit))
              .fontSize(10).lineHeight(13).fontColor($r('app.color.calendar_time_label')).textAlign(TextAlign.Center).width('100%')
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
            .id(this.controlPrefix + unit)
            .accessibilityText(String(unit) + ' · ' + TimetableHelper.getSlotStartTime(unit) + ' – ' + TimetableSchedule.endTime(unit))
        }.border({ width: { top: this.topDivider ? 0.5 : 0 }, color: $r('app.color.calendar_grid_line') })
      }, (unit: number): string => String(unit))
    }.columnsTemplate('1fr')
      .rowsTemplate(TimetableSchedule.UNITS.slice(0, this.periodCount).map((_unit: number): string => '1fr').join(' '))
      .width(this.axisWidth).height(this.rowHeight * this.periodCount)
      .enableScrollInteraction(false).scrollBar(BarState.Off).hitTestBehavior(HitTestMode.None)
  }
}
