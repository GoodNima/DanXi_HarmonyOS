import { CampusFormRow } from '../CampusFormData'

const storage: LocalStorage = new LocalStorage()

@Entry(storage)
@Component
struct CampusWidget {
  @LocalStorageProp('feature') feature: string = 'timetable'
  @LocalStorageProp('value') value: string = ''
  @LocalStorageProp('description') description: string = ''
  @LocalStorageProp('secondary') secondary: string = ''
  @LocalStorageProp('tone') tone: string = ''
  @LocalStorageProp('updatedLabel') updatedLabel: string = ''
  @LocalStorageProp('stale') stale: boolean = false
  @LocalStorageProp('rows') rows: CampusFormRow[] = []
  @LocalStorageProp('dimension') dimension: number = 2

  private title(): Resource {
    if (this.feature === 'card') return $r('app.string.desktop_forms_card')
    if (this.feature === 'electricity') return $r('app.string.desktop_forms_electricity')
    if (this.feature === 'bus') return $r('app.string.desktop_forms_bus')
    return $r('app.string.desktop_forms_timetable')
  }
  private icon(): Resource {
    if (this.feature === 'card') return $r('sys.symbol.creditcard')
    if (this.feature === 'electricity') return $r('sys.symbol.bolt')
    if (this.feature === 'bus') return $r('sys.symbol.car')
    return $r('sys.symbol.calendar')
  }
  private theme(): ResourceColor {
    if (this.feature === 'card' || this.feature === 'electricity') return $r('app.color.campus_palette_yellow')
    if (this.feature === 'bus') return $r('app.color.campus_palette_blue')
    return $r('app.color.campus_palette_indigo')
  }
  private valueColor(): ResourceColor {
    if (this.tone === 'critical') return $r('app.color.campus_text_attention')
    if (this.tone === 'warning') return $r('app.color.campus_text_warning')
    if (this.tone === 'normal') return $r('app.color.campus_text_available')
    return $r('app.color.theme_text_primary')
  }
  private open(): void {
    postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { desktopFeature: this.feature } })
  }
  private compactCourseWraps(): boolean {
    return this.dimension === 1 && this.feature === 'timetable' && this.value.length > 10
  }
  private caption(): ResourceStr {
    if (!this.value) return $r('app.string.desktop_forms_hint')
    if (this.feature === 'timetable' && this.rows.length > 0) {
      return this.rows[0].value + (this.rows[0].detail ? ' · ' + this.rows[0].detail : '')
    }
    return this.description.split('\n')[0]
  }
  private compactCaption(): ResourceStr {
    if (this.feature === 'card') return $r('app.string.desktop_forms_balance')
    if (this.feature === 'electricity') return $r('app.string.desktop_forms_remaining')
    if (!this.value) return $r('app.string.desktop_forms_hint')
    return this.caption()
  }
  @Builder
  Heading() {
    Row({ space: 6 }) {
      SymbolGlyph(this.icon()).fontSize(this.dimension === 1 ? 12 : 18).fontColor([this.theme()])
      if (this.dimension === 1) {
        Text(this.title()).fontSize(11).fontWeight(FontWeight.Bold).fontColor(this.theme()).maxLines(1)
        Text(this.compactCaption()).fontSize(10).minFontSize(9).maxFontSize(10).maxLines(1)
          .fontColor($r('app.color.theme_text_secondary')).textAlign(TextAlign.End).layoutWeight(1)
      } else {
        Text(this.title()).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.theme()).maxLines(1).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([$r('app.color.theme_text_hint')])
      }
    }.width('100%')
  }
  @Builder
  MainValue() {
    Text(this.value || $r('app.string.desktop_forms_empty'))
      .fontSize(this.compactCourseWraps() ? 13 : this.dimension === 1 ? 16 : 26).fontWeight(FontWeight.Bold).fontColor(this.valueColor())
      .minFontSize(this.dimension === 1 ? 11 : this.feature === 'timetable' && this.rows.length === 0 ? 12 : 18)
      .maxFontSize(this.compactCourseWraps() ? 13 : this.dimension === 1 ? 16 : 26)
      .maxLines(this.dimension === 2 && this.feature === 'timetable' && this.rows.length === 0 ? 1 : this.dimension === 1 && !this.compactCourseWraps() ? 1 : 2)
      .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
  }
  @Builder
  UpdateLabel() {
    Text(this.stale ? $r('app.string.desktop_forms_old') : this.updatedLabel || '—')
      .fontSize(10).fontColor($r('app.color.theme_text_hint')).maxLines(1)
  }
  @Builder
  BusDepartures() {
    Column({ space: 3 }) {
      Row({ space: 10 }) {
        Text($r('app.string.desktop_bus_direction')).layoutWeight(1).fontSize(10)
          .fontColor($r('app.color.theme_text_secondary')).maxLines(1)
        Text($r('app.string.desktop_bus_next')).width('23%').fontSize(10).textAlign(TextAlign.End)
          .fontColor($r('app.color.theme_text_secondary')).maxLines(1)
        Text($r('app.string.desktop_bus_later')).width('23%').fontSize(10).textAlign(TextAlign.End)
          .fontColor($r('app.color.theme_text_secondary')).maxLines(1)
      }.width('100%')
      ForEach(this.rows.slice(0, 2), (row: CampusFormRow, index: number) => {
        Row({ space: 10 }) {
          Text(row.label).layoutWeight(1).fontSize(14).minFontSize(11).maxFontSize(14).maxLines(2)
            .fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_primary'))
            .id('desktop-bus-route-' + String(index))
          Text(row.value || '—').width('23%').fontSize(20).minFontSize(16).maxFontSize(20).maxLines(1)
            .fontWeight(FontWeight.Bold).fontColor(this.valueColor()).textAlign(TextAlign.End)
            .id('desktop-bus-next-' + String(index))
          Text(row.detail || '—').width('23%').fontSize(14).minFontSize(12).maxFontSize(14).maxLines(1)
            .fontColor($r('app.color.theme_text_secondary')).textAlign(TextAlign.End)
            .id('desktop-bus-later-' + String(index))
        }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Center)
      }, (row: CampusFormRow, index: number) => String(index) + ':' + row.label + ':' + row.value + ':' + row.detail)
    }.width('100%').layoutWeight(1)
  }
  build() {
    Column({ space: this.dimension === 1 ? 5 : 6 }) {
      this.Heading()
      if (this.dimension === 1) {
        this.MainValue()
      } else {
        Column({ space: 4 }) {
          if (this.dimension === 3 && this.feature === 'bus' && this.rows.length > 0) {
            this.BusDepartures()
          } else if (this.dimension === 3 && this.rows.length > 0) {
            ForEach(this.rows.slice(0, 3), (row: CampusFormRow) => {
              if (this.feature === 'timetable') {
                Row({ space: 10 }) {
                  Text(row.label).fontSize(14).minFontSize(12).maxFontSize(14).maxLines(2)
                    .fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_text_primary')).layoutWeight(1)
                  Column({ space: 1 }) {
                    Text(row.value).fontSize(12).fontColor($r('app.color.theme_text_primary')).maxLines(1)
                    if (row.detail) {
                      Text(row.detail).fontSize(10).fontColor($r('app.color.theme_text_secondary')).maxLines(1)
                    }
                  }.width('32%').alignItems(HorizontalAlign.End)
                }.width('100%').layoutWeight(1)
              } else {
                Column({ space: 2 }) {
                Row({ space: 12 }) {
                  Text(row.label).fontSize(16).minFontSize(13).maxFontSize(16).fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.theme_text_primary')).layoutWeight(1).maxLines(2)
                  Text(row.value || '—').fontSize(14).fontWeight(FontWeight.Bold)
                    .fontColor(this.valueColor()).maxLines(1)
                }.width('100%')
                if (row.detail) {
                  Text(row.detail)
                    .fontSize(11).fontColor($r('app.color.theme_text_secondary')).width('100%').maxLines(2)
                }
                }.width('100%')
              }
            }, (row: CampusFormRow, index: number) => String(index) + row.label)
          } else if (this.dimension === 3 && this.value && (this.feature === 'card' || this.feature === 'electricity')) {
            Row({ space: 20 }) {
              Column({ space: 6 }) {
                Text(this.value).fontSize(32).minFontSize(22).maxFontSize(32).fontWeight(FontWeight.Bold)
                  .fontColor(this.valueColor()).maxLines(1).width('100%')
                Text(this.caption()).fontSize(12).fontColor($r('app.color.theme_text_secondary')).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (this.secondary) {
                Text(this.secondary).fontSize(14).lineHeight(20).fontColor($r('app.color.theme_text_secondary'))
                  .width('36%').maxLines(3)
              }
            }.width('100%')
          } else {
            this.MainValue()
            Text(this.caption()).fontSize(12).lineHeight(17).fontColor($r('app.color.theme_text_secondary'))
              .width('100%').maxLines(2)
            if (this.dimension === 3 && this.secondary) {
              Text(this.secondary).fontSize(12).lineHeight(17).fontColor($r('app.color.theme_text_secondary'))
                .width('100%').maxLines(2)
            }
          }
        }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
        if (this.dimension === 2 && this.secondary) {
          Column({ space: 2 }) {
            if (this.stale) {
              this.UpdateLabel()
            } else {
              Text(this.secondary).fontSize(11).lineHeight(15).fontColor($r('app.color.theme_text_secondary'))
                .width('100%').maxLines(2)
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else {
          Row({ space: 8 }) {
          if (this.dimension === 3 && this.rows.length > 0) {
            Text(this.secondary).fontSize(11).minFontSize(9).maxFontSize(11)
              .fontColor($r('app.color.theme_text_secondary')).layoutWeight(1).maxLines(1)
          }
          this.UpdateLabel()
          }.width('100%')
        }
      }
    }.width('100%').height('100%').padding({ left: 14, right: 14, top: this.dimension === 1 ? 5 : 12, bottom: this.dimension === 1 ? 5 : 12 })
      .alignItems(HorizontalAlign.Start).justifyContent(this.dimension === 1 ? FlexAlign.Center : FlexAlign.Start)
      .borderRadius(24).backgroundColor($r('app.color.theme_card_bg'))
      .onClick(() => { this.open() })
  }
}
