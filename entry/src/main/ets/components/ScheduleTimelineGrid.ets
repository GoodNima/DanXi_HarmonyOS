import { ThemeColors } from '../common/Theme'
import { TimetableSchedule } from '../model/TimetableSchedule'

/** Calendar-style time lanes. Native Scroll/List owns motion and hit testing;
 * the decorative grid cannot intercept an event or start its own gesture. */
@Component
export struct ScheduleTimelineGrid {
  @Prop periodCount: number = 15
  @Prop rowHeight: number = 58
  @Prop freePeriods: number[] = []
  @Prop showAvailability: boolean = false
  @Prop highContrast: boolean = false
  build() {
    Grid() {
      ForEach(TimetableSchedule.UNITS.slice(0, this.periodCount), (unit: number) => {
        GridItem() {
          Stack() {
            if (this.showAvailability && this.freePeriods.includes(unit)) {
              Text($r('app.string.classroom_free')).fontSize(11).fontColor(ThemeColors.textSecondary)
            }
          }.width('100%').height('100%')
            .border({ width: { top: this.highContrast ? 0.8 : 0.5 },
              color: this.highContrast ? ThemeColors.textPrimary : $r('app.color.calendar_grid_line') })
        }
      }, (unit: number): string => String(unit))
    }.width('100%').height(this.periodCount * this.rowHeight).columnsTemplate('1fr')
      .rowsTemplate(TimetableSchedule.UNITS.slice(0, this.periodCount).map((_unit: number): string => '1fr').join(' '))
      .enableScrollInteraction(false).scrollBar(BarState.Off).hitTestBehavior(HitTestMode.None)
      .border({ width: { left: 0.5 }, color: $r('app.color.calendar_grid_line') })
  }
}
