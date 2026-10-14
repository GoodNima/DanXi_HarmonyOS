import { EmptyClassroom } from '../model/Academic'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
import { AppLanguage } from '../common/AppLanguage'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { ClassroomPresentation, ClassroomPeriodGroup } from '../common/ClassroomPresentation'
import { ClassroomPreference } from '../common/ClassroomPreference'

/** Long room names and period summaries always receive the full card width. */
@Component
export struct ClassroomCard {
  @Prop item: EmptyClassroom = { building: '', room: '', capacity: 0, status: '', campus: '' }
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(ClassroomPreference.KEY_HIGH_CONTRAST) highContrast: boolean = false
  @Prop selectedStart: number = 0
  @Prop selectedEnd: number = 0
  @Prop currentSlot: number = 0
  @State private expanded: boolean = false
  @State private selectedPeriod: number = 0

  private summary(): string {
    if (this.item.freePeriods === undefined) return this.item.status
    return this.item.freePeriods.length === 0 ? AppLanguage.text($r('app.string.classroom_busy'), this.languageRevision) :
      AppLanguage.text($r('app.string.classroom_free_summary'), this.languageRevision, ClassroomPresentation.freeRanges(this.item.freePeriods))
  }

  private periodColor(slot: number): ResourceColor {
    const free = ClassroomPresentation.slotFree(this.item, slot)
    if (free === undefined) return $r('app.color.input_surface')
    if (this.highContrast) return free ? $r('app.color.input_surface') : ThemeColors.textPrimary
    return free ? $r('app.color.campus_available_surface') : $r('app.color.input_surface')
  }

  private periodTextColor(slot: number): ResourceColor {
    const free = ClassroomPresentation.slotFree(this.item, slot)
    if (this.highContrast && free === false) return $r('app.color.theme_bg_start')
    return free === true ? CampusContentStyle.available : free === false ? CampusContentStyle.attention : ThemeColors.textSecondary
  }

  private periodLabel(slot: number): string {
    const free = ClassroomPresentation.slotFree(this.item, slot)
    return free === true ? AppLanguage.text($r('app.string.classroom_period_free'), this.languageRevision, slot) :
      free === false ? AppLanguage.text($r('app.string.classroom_period_occupied'), this.languageRevision, slot,
        this.item.periods?.[slot - 1] || AppLanguage.text($r('app.string.classroom_occupied'), this.languageRevision)) :
        AppLanguage.text($r('app.string.classroom_period_unknown'), this.languageRevision, slot)
  }

  private periodBorderWidth(slot: number): number {
    if (slot === this.currentSlot || slot === this.selectedPeriod) return 1.5
    return this.selectedStart > 0 && slot >= this.selectedStart && slot <= this.selectedEnd ? 0.9 : this.highContrast ? 0.6 : 0
  }

  private periodBorderColor(slot: number): ResourceColor {
    if (slot === this.currentSlot && slot !== this.selectedPeriod) return ThemeColors.textPrimary
    return slot === this.selectedPeriod || this.selectedStart > 0 && slot >= this.selectedStart && slot <= this.selectedEnd ?
      CampusContentStyle.accent : ThemeColors.textPrimary
  }

  @Builder
  Periods(group: ClassroomPeriodGroup) {
    Column({ space: 5 }) {
      Text(group.name).fontSize(11).lineHeight(16).fontColor(ThemeColors.textSecondary).maxLines(1)
      Row({ space: 3 }) {
        ForEach(group.periods, (slot: number) => {
          Button(String(slot), { type: ButtonType.Normal }).layoutWeight(1).height(29).padding(0).fontSize(11)
            .fontColor(this.periodTextColor(slot)).backgroundColor(this.periodColor(slot)).borderRadius(5)
            .border({ width: this.periodBorderWidth(slot), color: this.periodBorderColor(slot) })
            .stateEffect(false).accessibilityText(this.periodLabel(slot))
            .onClick(() => {
              this.getUIContext().animateTo({ duration: 180, curve: Curve.Friction }, () => {
                this.selectedPeriod = slot
                this.expanded = true
              })
            })
        }, (slot: number) => String(slot))
      }.width('100%')
    }.layoutWeight(group.periods.length).alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.item.room).fontSize(19).lineHeight(26).fontWeight(FontWeight.Bold)
          .fontColor(CampusContentStyle.accent).layoutWeight(1)
        Text(this.item.capacity > 0 ? String(this.item.capacity) + AppLanguage.text($r('app.string.ui_seats'), this.languageRevision) :
          AppLanguage.text($r('app.string.ui_unknown_capacity'), this.languageRevision))
          .fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).constraintSize({ maxWidth: 110 })
      }.width('100%').alignItems(VerticalAlign.Center)
      Text(this.item.building + (this.item.campus ? ' · ' + AppLanguage.campus(this.item.campus, this.languageRevision) : ''))
        .fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
      if (this.item.freePeriods !== undefined) {
        Row({ space: 9 }) {
          ForEach(ClassroomPresentation.GROUPS, (group: ClassroomPeriodGroup) => { this.Periods(group) },
            (group: ClassroomPeriodGroup) => String(group.periods[0]))
        }.width('100%').alignItems(VerticalAlign.Top)
      }
      Text(this.summary()).fontSize(13).fontWeight(FontWeight.Medium).fontColor(CampusContentStyle.classroomColor(this.item))
        .width('100%').lineHeight(20)
      if (this.item.periods !== undefined && this.item.periods.length > 0) {
        Button(this.expanded ? $r('app.string.classroom_hide_periods') : $r('app.string.classroom_periods'))
          .fontSize(12).height(30).backgroundColor(Color.Transparent).padding(0)
          .fontColor(CampusContentStyle.accent).stateEffect(false)
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 180, curve: Curve.Friction }, () => {
              this.selectedPeriod = 0
              this.expanded = !this.expanded
            })
          })
        if (this.expanded) {
          Column({ space: 5 }) {
            ForEach(this.selectedPeriod > 0 ? [this.selectedPeriod] : this.item.periods.map((_content: string, index: number) => index + 1),
              (slot: number) => {
                Text(this.periodLabel(slot)).width('100%').fontSize(13).lineHeight(20)
                  .fontColor(ClassroomPresentation.slotFree(this.item, slot) === true ? CampusContentStyle.available : ThemeColors.textPrimary)
              }, (slot: number) => String(slot))
          }.width('100%').padding(10).backgroundColor($r('app.color.input_surface')).borderRadius(10)
            .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
        }
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding(16).margin({ top: 4 })
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      .borderRadius(ThemeDimens.radiusLarge)
  }
}
