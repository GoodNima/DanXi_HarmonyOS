import { ErrorNotice } from './ErrorNotice'
import { AppLanguage } from '../common/AppLanguage'
import { ThemeColors } from '../common/Theme'
import { ForumPresentation } from '../common/ForumPresentation'
import { ForumSummary, SummaryBranch, SummaryInteraction, ForumDetailSource } from '../model/ForumDetail'
import { ForumSummaryRules } from '../model/ForumSummaryRules'
import { ForumContentView } from './ForumContentView'
import { ForumSummaryBranchView } from './ForumSummaryBranchView'
import { ForumRepository } from '../repository/ForumRepository'

/** Stable sections replace the old unlabelled text and bottom loading ball.
 * Native progress is indeterminate: no invented percentage for server work. */
@Component
export struct ForumSummaryView {
  @Prop value: ForumSummary | null = null
  @Prop @Watch('phaseChanged') phase: string = 'loading'
  @Prop error: string = ''
  @Prop count: number = 0
  @Prop feedbackSent: boolean = false
  @Prop feedbackPending: boolean = false
  @Prop feedbackType: string = ''
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @Prop holeId: number = 0
  source: ForumDetailSource = ForumRepository.getInstance()
  @State private resultOpacity: number = 1
  private motionTimer: number = -1
  private motionRevision: number = 0

  aboutToAppear(): void { this.phaseChanged() }
  aboutToDisappear(): void { this.motionRevision++; if (this.motionTimer >= 0) clearTimeout(this.motionTimer) }
  private phaseChanged(): void {
    this.motionRevision++
    if (this.motionTimer >= 0) clearTimeout(this.motionTimer)
    if (this.phase !== 'ready') { this.resultOpacity = 1; return }
    const revision: number = this.motionRevision
    this.resultOpacity = 0
    this.motionTimer = setTimeout(() => {
      if (revision !== this.motionRevision) return
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.resultOpacity = 1 })
    }, 16)
  }

  onRetry: () => void = () => {}
  onLocate: (id: number) => void = () => {}
  onHelpful: () => void = () => {}
  onUnhelpful: () => void = () => {}
  onCopy: (text: string) => void = () => {}

  private text(resource: Resource): string { return AppLanguage.text(resource, this.languageRevision) }

  @Builder
  Heading(title: Resource, icon: Resource) {
    Row({ space: 8 }) {
      SymbolGlyph(icon).fontSize(16).fontColor([ThemeColors.primary])
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
    }.width('100%').margin({ top: 6 })
  }

  @Builder
  FloorLink(id: number) {
    if (Number.isSafeInteger(id) && id > 0) {
      Button('#' + id, { type: ButtonType.Normal }).fontSize(13).fontColor(ThemeColors.primary)
        .backgroundColor($r('app.color.input_surface')).borderRadius(8)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 }).margin({ right: 6, bottom: 6 })
        .stateEffect(false).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
        .onClick(() => { this.onLocate(id) })
    }
  }

  @Builder
  Interaction(item: SummaryInteraction) {
    Column({ space: 10 }) {
      Text() {
        Span(item.fromUser).fontWeight(FontWeight.Medium).fontColor(ForumPresentation.authorColor(item.fromUser, this.darkMode))
        Span(' ' + this.text(ForumSummaryRules.interaction(item.kind)) + ' ').fontColor(ForumSummaryRules.interactionColor(item.kind, this.darkMode))
        Span(item.toUser).fontWeight(FontWeight.Medium).fontColor(ForumPresentation.authorColor(item.toUser, this.darkMode))
      }.fontSize(14).width('100%')
      if (item.content) ForumContentView({ content: item.content, textSize: 14 })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.FloorLink(item.fromFloor)
        if (item.toFloor !== item.fromFloor) this.FloorLink(item.toFloor)
      }.width('100%')
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.input_surface')).borderRadius(16)
  }

  @Builder
  FeedbackButton(label: Resource, symbol: Resource, type: string, action: () => void) {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph(symbol).fontSize(18).fontColor([this.feedbackType === type ? type === 'upvote' ? ThemeColors.success : ThemeColors.error : ThemeColors.primary])
          .scale({ x: this.feedbackType === type ? 1.12 : 1, y: this.feedbackType === type ? 1.12 : 1 }).animation({ duration: 180, curve: Curve.EaseOut })
        Text(label).fontSize(13).fontColor(ThemeColors.textPrimary)
      }
    }.layoutWeight(1).height(40).backgroundColor($r('app.color.input_surface')).borderRadius(12)
      .enabled(!this.feedbackPending && !this.feedbackSent && !ForumSummaryRules.waiting(this.phase))
      .stateEffect(false).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 }).onClick(action)
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Image($r('app.media.ai_summary')).width(23).height(23).fillColor(ThemeColors.primary)
        Text($r('app.string.detail_summary')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      }.width('100%').constraintSize({ minHeight: 40 }).padding({ right: 48 })
      Text($r('app.string.summary_disclaimer')).fontSize(12).fontColor(ThemeColors.textHint).width('100%')
      if (ForumSummaryRules.waiting(this.phase)) {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            LoadingProgress().width(22).height(22).color(ThemeColors.primary)
            Text(ForumSummaryRules.status(this.phase)).fontSize(15).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          }.width('100%')
          if (this.count > 0) Text(this.text($r('app.string.summary_count')).replace('%s', String(this.count)))
            .fontSize(13).fontColor(ThemeColors.textSecondary).width('100%')
          Text($r('app.string.summary_wait_note')).fontSize(12).fontColor(ThemeColors.textHint).width('100%')
          if (!ForumSummaryRules.hasContent(this.value)) {
            ForEach([92, 76, 58], (width: number) => {
              Row() {}.width(String(width) + '%').height(10).borderRadius(5).backgroundColor($r('app.color.input_surface'))
            }, (width: number) => String(width))
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 6, bottom: 8 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
      }
      if (ForumSummaryRules.hasContent(this.value) && this.value !== null) {
        Column({ space: 14 }) {
          if (this.value.keywords.length > 0) {
            this.Heading($r('app.string.summary_keywords'), $r('sys.symbol.label'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.value.keywords, (word: string) => {
                Text(word).fontSize(13).fontColor(ForumPresentation.tagColor(word, this.darkMode, false))
                  .backgroundColor(ForumPresentation.tagBackground(word, this.darkMode, false)).borderRadius(8)
                  .padding({ left: 9, right: 9, top: 5, bottom: 5 }).margin({ right: 6, bottom: 6 })
              })
            }.width('100%')
          }
          if (this.value.summary.trim()) {
            this.Heading($r('app.string.summary_core'), $r('sys.symbol.doc_text'))
            ForumContentView({ content: this.value.summary, textSize: 15 })
          }
          if (this.value.branches.length > 0) {
            this.Heading($r('app.string.summary_branches'), $r('sys.symbol.list_bullet'))
            ForEach(this.value.branches, (branch: SummaryBranch) => {
              ForumSummaryBranchView({ branch: branch, source: this.source, holeId: this.holeId, total: this.count,
                onLocate: (id: number) => { this.onLocate(id) } })
            }, (branch: SummaryBranch) => String(branch.id) + branch.label + this.value?.generatedAt)
          }
          if (this.value.interactions.length > 0) {
            this.Heading($r('app.string.summary_interactions'), $r('sys.symbol.message'))
            ForEach(this.value.interactions, (item: SummaryInteraction) => { this.Interaction(item) })
          }
          Divider().color($r('app.color.input_surface')).margin({ top: 2 })
          if (this.value.generatedAt) Text(this.text($r('app.string.summary_generated')) + ' ' + this.value.generatedAt.replace('T', ' ').replace(/\.\d+Z$/, 'Z'))
            .fontSize(11).fontColor(ThemeColors.textHint)
          Row({ space: 10 }) {
            this.FeedbackButton($r('app.string.detail_helpful'), $r('sys.symbol.hand_thumbsup'), 'upvote', () => { this.onHelpful() })
            this.FeedbackButton($r('app.string.detail_unhelpful'), $r('sys.symbol.hand_thumbsdown'), 'downvote', () => { this.onUnhelpful() })
          }.width('100%')
          // Reserve one line so submitting feedback never shifts result content.
          Text(this.feedbackSent ? $r('app.string.summary_feedback_sent') : this.feedbackPending ? $r('app.string.summary_feedback_sending') : '')
            .height(18).fontSize(12).fontColor(ThemeColors.primary).width('100%').textAlign(TextAlign.Center)
          if (this.value.traceId) Text('Trace: ' + this.value.traceId).fontSize(10).fontColor(ThemeColors.textHint)
            .copyOption(CopyOptions.LocalDevice).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start).opacity(this.resultOpacity)
      }
      if (!ForumSummaryRules.waiting(this.phase) && this.phase !== 'ready') {
        Text(ForumSummaryRules.status(this.phase)).fontSize(15).fontColor(ThemeColors.textSecondary).width('100%')
      }
      if (this.error) ErrorNotice({ message: this.error, controlId: 'forumsummaryview-diagnostics', textSize: 12, textColor: ThemeColors.error }).width('100%')
      Row({ space: 10 }) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise')).fontSize(17).fontColor([ThemeColors.primary])
            Text(ForumSummaryRules.hasContent(this.value) ? $r('app.string.detail_summary_refresh') : $r('app.string.ui_retry'))
              .fontSize(13).fontColor(ThemeColors.primary)
          }
        }.layoutWeight(1).height(42).backgroundColor($r('app.color.input_surface')).borderRadius(12)
          .enabled(!ForumSummaryRules.waiting(this.phase) && !this.feedbackPending)
          .stateEffect(false).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 }).onClick(() => { this.onRetry() })
        if (ForumSummaryRules.hasContent(this.value)) Button($r('app.string.summary_copy')).layoutWeight(1).height(42).fontSize(13)
          .backgroundColor($r('app.color.input_surface')).fontColor(ThemeColors.primary).borderRadius(12).stateEffect(false)
          .onClick(() => { this.onCopy(ForumSummaryRules.copy(this.value)) })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
