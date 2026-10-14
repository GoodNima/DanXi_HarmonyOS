import { ErrorNotice } from './ErrorNotice'
import { AppLanguage } from '../common/AppLanguage'
import { ThemeColors } from '../common/Theme'
import { ForumPresentation } from '../common/ForumPresentation'
import { ForumFloor } from '../model/Forum'
import { ForumDetailSource, SummaryBranch } from '../model/ForumDetail'
import { ForumContentParser } from '../model/ForumContent'
import { ForumSummaryRules } from '../model/ForumSummaryRules'
import { ForumRepository } from '../repository/ForumRepository'
import { ForumContentView } from './ForumContentView'

/** Representative replies follow the original expandable branch layout.
 * Resolve only on expansion, cache locally, and never read the whole thread. */
@Component
export struct ForumSummaryBranchView {
  @Prop branch: SummaryBranch = new SummaryBranch()
  @Prop holeId: number = 0
  @Prop total: number = 0
  source: ForumDetailSource = ForumRepository.getInstance()
  onLocate: (id: number) => void = () => {}
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @State private expanded: boolean = false
  @State private floors: ForumFloor[] = []
  @State private loading: boolean = false
  @State private error: string = ''
  private active: boolean = true
  private revision: number = 0
  private cache: Map<number, ForumFloor> = new Map()

  aboutToDisappear(): void { this.active = false; this.revision++ }

  private async toggle(): Promise<void> {
    this.expanded = !this.expanded
    this.revision++
    if (!this.expanded) { this.loading = false; return }
    const revision: number = this.revision
    const current = (): boolean => this.active && this.expanded && revision === this.revision
    this.loading = true; this.error = ''
    for (const id of this.branch.floors) {
      if (!current()) return
      try {
        let floor: ForumFloor | undefined = this.cache.get(id)
        if (floor === undefined) floor = await ForumSummaryRules.resolve(this.source, this.holeId, id, this.total, current)
        if (!current()) return
        this.cache.set(id, floor)
        this.floors = this.branch.floors.map((reference: number) => this.cache.get(reference))
          .filter((value: ForumFloor | undefined) => value !== undefined) as ForumFloor[]
      } catch (e) { if (current()) this.error = ForumRepository.describeError(e) }
    }
    if (current()) this.loading = false
  }

  build() {
    Column({ space: 10 }) {
      Button() {
        Row({ space: 8 }) {
          Row() {}.width(4).height(18).borderRadius(2).backgroundColor(ForumSummaryRules.color(this.branch.color, this.darkMode))
          Text(this.branch.label).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          if (this.branch.floors.length > 0) SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(14).fontColor([ThemeColors.textHint])
            .rotate({ angle: this.expanded ? 180 : 0 }).animation({ duration: 180 })
        }.width('100%')
      }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(Color.Transparent).stateEffect(false)
        .onClick(() => { this.toggle() })
      if (this.branch.content) ForumContentView({ content: this.branch.content, textSize: 14 })
      if (this.expanded && this.branch.floors.length > 0) {
        Text($r('app.string.summary_references')).fontSize(12).fontColor(ThemeColors.textHint)
        ForEach(this.floors, (floor: ForumFloor) => {
          Button() {
            Column({ space: 6 }) {
              Text(floor.anonyname + ' · ##' + floor.floorId).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(ForumPresentation.authorColor(floor.anonyname, this.darkMode)).width('100%')
              Text(floor.deleted ? $r('app.string.ui_this_floor_was_deleted') : ForumContentParser.summary(floor.content, false))
                .fontSize(13).lineHeight(20).fontColor(ThemeColors.textSecondary).maxLines(4)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width('100%').padding(12).borderRadius(12).backgroundColor(ThemeColors.cardBg).stateEffect(false)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 }).onClick(() => { this.onLocate(floor.floorId) })
        }, (floor: ForumFloor) => String(floor.floorId))
        if (this.loading) LoadingProgress().width(22).height(22).color(ThemeColors.primary)
        if (this.error) {
          ErrorNotice({ message: this.error, controlId: 'forumsummarybranchview-diagnostics', textSize: 12, textColor: ThemeColors.error }).width('100%')
          Button($r('app.string.ui_retry')).fontSize(13).height(36).backgroundColor(ThemeColors.cardBg).fontColor(ThemeColors.primary)
            .onClick(() => { this.expanded = false; this.toggle() })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(14)
      .backgroundColor($r('app.color.input_surface')).borderRadius(16)
  }
}
