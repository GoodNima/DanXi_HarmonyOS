import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { ErrorNotice } from './ErrorNotice'
import { EmptyClassroom } from '../model/Academic'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { AppLanguage } from '../common/AppLanguage'
import { CampusPreference } from '../common/CampusPreference'
import { ClassroomPresentation, ClassroomPeriodGroup } from '../common/ClassroomPresentation'
import { ClassroomPreference } from '../common/ClassroomPreference'
import { classroomRowKey } from '../common/ClassroomRequest'
import { ClassroomCard } from './ClassroomCard'
import { FloatingActionButton } from './FloatingActionButton'
import { getSymbolIcon } from '../common/DanXiIcons'
import { promptAction } from '@kit.ArkUI'

/** The host owns authentication and versioned requests; local filters need no extra network calls. */
@Component
export struct ClassroomContent {
  @Prop items: EmptyClassroom[] = []
  @Prop building: string = 'HGD'
  @Prop day: string = ''
  @Prop loading: boolean = false
  @Prop loadingOverlay: boolean = false
  @Prop error: string = ''
  onQuery: (building: string, campus: string, day: string, force: boolean) => void =
    (_building: string, _campus: string, _day: string, _force: boolean) => {}
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink(ClassroomPreference.KEY_ONLY_FREE) onlyFree: boolean = false
  @StorageLink(ClassroomPreference.KEY_HIGH_CONTRAST) highContrast: boolean = false
  @StorageLink(ClassroomPreference.KEY_REMEMBER_BUILDING) rememberBuilding: boolean = true
  @State private selectedCampus: string = '邯郸'
  @State private selectedBuilding: string = 'HGD'
  @State private queryDay: string = ClassroomPresentation.day(new Date())
  @State private startSlot: number = 0
  @State private endSlot: number = 0
  @State private now: Date = new Date()
  private version: number = 0
  private timer: number = -1

  aboutToAppear(): void {
    this.initialize()
    this.timer = setInterval(() => { this.now = new Date() }, 60000)
  }

  aboutToDisappear(): void {
    this.version++
    if (this.timer >= 0) clearInterval(this.timer)
    this.timer = -1
  }

  private async initialize(): Promise<void> {
    const version = ++this.version
    const campus = CampusPreference.current()
    let building = ClassroomPresentation.buildings(campus)[0]
    try { await ClassroomPreference.init(); building = await ClassroomPreference.building(campus) }
    catch (e) { /* A preference read failure must not hide the actual campus query. */ }
    if (version !== this.version) return
    this.selectedCampus = campus
    this.selectedBuilding = building
    this.queryDay = ClassroomPresentation.validDay(this.day) ? this.day : ClassroomPresentation.day(new Date())
    this.onQuery(building, campus, this.queryDay, false)
  }

  private request(force: boolean = false): void {
    this.onQuery(this.selectedBuilding, this.selectedCampus, this.queryDay, force)
  }

  private selectCampus(campus: string): void {
    if (campus === this.selectedCampus) return
    this.version++
    this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
      this.selectedCampus = campus
      this.selectedBuilding = ClassroomPresentation.buildings(campus)[0]
    })
    this.rememberSelection()
    this.request()
  }

  private selectBuilding(building: string): void {
    if (building === this.selectedBuilding) return
    this.version++
    this.selectedBuilding = building
    this.rememberSelection()
    this.request()
  }

  private async rememberSelection(): Promise<void> {
    const version = this.version
    try { await ClassroomPreference.remember(this.selectedCampus, this.selectedBuilding) }
    catch (e) {
      if (version === this.version) DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.classroom_save_failed')))
    }
  }

  private async savePreference(key: string, value: boolean): Promise<void> {
    const version = this.version
    try { await ClassroomPreference.set(key, value) }
    catch (e) {
      if (version === this.version) DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.classroom_save_failed')))
    }
  }

  private selectDate(): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.queryDay + 'T12:00:00'),
      start: ClassroomPresentation.dateOffset(this.now, -1), end: ClassroomPresentation.dateOffset(this.now, 14),
      onDateAccept: (date: Date): void => {
        const day = ClassroomPresentation.day(date)
        if (day === this.queryDay || !ClassroomPresentation.validDay(day)) return
        this.version++
        this.queryDay = day
        this.request()
      } })
  }

  private selectRange(start: number, end: number): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.startSlot = start
      this.endSlot = end
    })
  }

  private rangeText(): string {
    return this.startSlot === 0 ? AppLanguage.text($r('app.string.classroom_whole_day'), this.languageRevision) :
      AppLanguage.text($r('app.string.classroom_range'), this.languageRevision, this.startSlot, this.endSlot)
  }

  private visibleItems(): EmptyClassroom[] {
    return ClassroomPresentation.visible(this.scopedItems(), this.onlyFree, this.startSlot, this.endSlot)
  }

  private scopedItems(): EmptyClassroom[] {
    // A switched query may retain older rows while loading. Never label another building/date as the active result.
    return this.items.filter((item: EmptyClassroom) => item.building === this.selectedBuilding &&
      (item.day === undefined || item.day.length === 0 || item.day === this.queryDay))
  }

  @Builder
  Campuses() {
    Menu() {
      ForEach(ClassroomPresentation.CAMPUSES, (campus: string) => {
        MenuItem({ content: AppLanguage.campus(campus, this.languageRevision) })
          .selected(campus === this.selectedCampus).selectIcon(true).onClick(() => { this.selectCampus(campus) })
      }, (campus: string) => campus)
    }
  }

  @Builder
  Buildings() {
    Menu() {
      ForEach(ClassroomPresentation.buildings(this.selectedCampus), (building: string) => {
        MenuItem({ content: building }).selected(building === this.selectedBuilding).selectIcon(true)
          .onClick(() => { this.selectBuilding(building) })
      }, (building: string) => building)
    }
  }

  @Builder
  Ranges() {
    Menu() {
      MenuItem({ content: $r('app.string.classroom_whole_day') }).selected(this.startSlot === 0).selectIcon(true)
        .onClick(() => { this.selectRange(0, 0) })
      ForEach(ClassroomPresentation.GROUPS, (group: ClassroomPeriodGroup) => {
        MenuItem({ content: AppLanguage.text(group.name, this.languageRevision) + ' · ' +
          AppLanguage.text($r('app.string.classroom_range'), this.languageRevision,
            group.periods[0], group.periods[group.periods.length - 1]) })
          .selected(this.startSlot === group.periods[0] && this.endSlot === group.periods[group.periods.length - 1])
          .selectIcon(true).onClick(() => { this.selectRange(group.periods[0], group.periods[group.periods.length - 1]) })
      }, (group: ClassroomPeriodGroup) => String(group.periods[0]))
    }
  }

  @Builder
  SettingsNote() {
    Column() {
      Text($r('app.string.classroom_settings_note')).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
        .width('100%').padding({ top: 6, bottom: 12 })
    }.width(256).alignItems(HorizontalAlign.Start)
  }

  @Builder
  Settings() {
    Menu() {
      MenuItem({ content: $r('app.string.classroom_remember_building') }).selected(this.rememberBuilding).selectIcon(true)
        .onClick(() => { this.savePreference(ClassroomPreference.KEY_REMEMBER_BUILDING, !this.rememberBuilding) })
      MenuItem({ content: $r('app.string.classroom_high_contrast') }).selected(this.highContrast).selectIcon(true)
        .onClick(() => { this.savePreference(ClassroomPreference.KEY_HIGH_CONTRAST, !this.highContrast) })
      MenuItem(() => { this.SettingsNote() }).enabled(false)
    }.width(288)
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Column() {
            ClassroomQuerySelector({ label: $r('app.string.classroom_campus'), value: AppLanguage.campus(this.selectedCampus, this.languageRevision) })
          }.layoutWeight(1).bindMenu(this.Campuses)
          Column() { ClassroomQuerySelector({ label: $r('app.string.classroom_building'), value: this.selectedBuilding }) }
            .layoutWeight(1).bindMenu(this.Buildings)
        }.width('100%').alignItems(VerticalAlign.Top)
        Row({ space: 8 }) {
          Column() { ClassroomQuerySelector({ label: $r('app.string.classroom_date'), value: this.queryDay }) }
            .layoutWeight(1).onClick(() => { this.selectDate() })
          Column() { ClassroomQuerySelector({ label: $r('app.string.classroom_time_range'), value: this.rangeText() }) }
            .layoutWeight(1).bindMenu(this.Ranges)
        }.width('100%').alignItems(VerticalAlign.Top)
        Row({ space: 8 }) {
          Text($r('app.string.classroom_only_free')).fontSize(13).lineHeight(20).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.onlyFree }).selectedColor(ThemeColors.primary)
            .onChange((value: boolean) => { this.savePreference(ClassroomPreference.KEY_ONLY_FREE, value) })
          Text($r('app.string.classroom_display_settings')).fontSize(12).fontColor(ThemeColors.primary).padding(8)
            .bindMenu(this.Settings).accessibilityRole(AccessibilityRoleType.BUTTON)
        }.width('100%')
        Text($r('app.string.classroom_filter_note')).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).width('100%')
      }.width('100%').padding(14).backgroundColor($r('app.color.surface_fallback'))
        .borderRadius(ThemeDimens.radiusLarge)
      Row({ space: 8 }) {
        Text(AppLanguage.text($r('app.string.classroom_result_count'), this.languageRevision, this.visibleItems().length, this.scopedItems().length))
          .layoutWeight(1).fontSize(13).fontColor(ThemeColors.textSecondary)
        Text($r('app.string.classroom_free')).fontSize(11).fontColor($r('app.color.campus_text_available'))
        Text($r('app.string.classroom_occupied')).fontSize(11).fontColor($r('app.color.campus_text_attention'))
      }.width('100%')
      Text($r('app.string.classroom_matrix_note')).fontSize(11).lineHeight(17).fontColor(ThemeColors.textHint).width('100%')
      if (this.loading && !this.loadingOverlay) {
        Row({ space: 8 }) {
          LoadingProgress().width(22).height(22).color(ThemeColors.primary)
          Text($r('app.string.classroom_loading')).fontSize(13).fontColor(ThemeColors.textSecondary)
        }.width('100%').justifyContent(FlexAlign.Center).padding(12)
      }
      if (this.error.length > 0) {
        Column({ space: 10 }) {
          ErrorNotice({ message: this.error, controlId: 'classroomcontent-diagnostics', textSize: 13, textColor: $r('app.color.campus_text_attention') }).width('100%')
          FloatingActionButton({ label: $r('app.string.academic_retry'), onAction: () => { this.request(true) } }).width(132)
        }.width('100%').padding(16).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.surface_fallback'))
          .borderRadius(ThemeDimens.radiusLarge)
      }
      ForEach(this.visibleItems(), (item: EmptyClassroom) => {
        ClassroomCard({ item: item, selectedStart: this.startSlot, selectedEnd: this.endSlot,
          currentSlot: ClassroomPresentation.currentSlot(this.queryDay, this.now) })
      }, (item: EmptyClassroom, index: number) => classroomRowKey(item, index))
      if (!this.loading && this.error.length === 0 && this.visibleItems().length === 0) {
        Text(this.scopedItems().length > 0 ? $r('app.string.classroom_filter_empty') : $r('app.string.classroom_no_rows'))
          .width('100%').fontSize(14).lineHeight(22).padding(16).fontColor(ThemeColors.textSecondary)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

/** Props keep visible values reactive after a menu or date choice. */
@Component
struct ClassroomQuerySelector {
  @Prop label: Resource = $r('app.string.classroom_campus')
  @Prop value: string = ''
  build() {
    Column({ space: 4 }) {
      Text(this.label).fontSize(11).lineHeight(16).fontColor(ThemeColors.textSecondary)
      Row({ space: 8 }) {
        Text(this.value).fontSize(15).lineHeight(22).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        SymbolGlyph(getSymbolIcon('expand')).fontSize(16).fontColor([ThemeColors.textSecondary]).accessibilityLevel('no')
      }.width('100%').alignItems(VerticalAlign.Center)
    }.alignItems(HorizontalAlign.Start).width('100%').padding(10)
      .backgroundColor($r('app.color.input_surface')).borderRadius(12).accessibilityRole(AccessibilityRoleType.BUTTON)
  }
}
