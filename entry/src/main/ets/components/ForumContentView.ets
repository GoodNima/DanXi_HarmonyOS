import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { DiagnosticLink } from './ErrorNotice'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { AppLanguage } from '../common/AppLanguage'
import { ForumContentParser, ForumContentPart } from '../model/ForumContent'
import { ForumStickers } from '../common/ForumStickers'
import { ThemeColors } from '../common/Theme'
import { router, promptAction } from '@kit.ArkUI'
import { ForumRepository } from '../repository/ForumRepository'
import { ForumFloor, ForumHole } from '../model/Forum'
import { ForumQuoteCache, ForumQuoteContent } from '../model/ForumQuoteCache'
import { ForumQuoteRepository } from '../model/ForumQuoteRepository'
import { HoleRouteParams, ImageRouteParams, ImageOpening } from '../common/RouteParams'
import { ForumImageTransition } from '../common/ForumImageTransition'
import { adaptiveMaterial, nativeFloatingBackground } from '../common/AdaptiveMaterial'
import { Constant } from '../common/Constant'
import { ForumPresentation } from '../common/ForumPresentation'
import { ForumRichText } from './ForumRichText'
import { ForumRemoteImage } from './ForumRemoteImage'
import { ForumPreferences } from '../common/ForumPreferences'
import { FloatingActionButton } from './FloatingActionButton'
import { ForumPreviewWork } from '../common/ForumPreviewWork'

@Component
struct ForumMedia {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @Prop @Watch('sourceChanged') source: string = ''
  @Prop label: string = ''
  @Prop sticker: boolean = false
  @Prop preview: boolean = false
  @Prop coordinatedPreview: boolean = false
  onPrepared: () => void = () => {}
  @Prop gallery: string[] = []
  onPreviewOpen: (() => void) | undefined = undefined
  @State failed: boolean = false

  private sourceChanged(): void { this.failed = false }

  build() {
    if (!this.sticker) {
      ForumRemoteImage({ source: this.source, label: this.label,
        preview: this.preview,
        coordinatedPreview: this.coordinatedPreview, onPrepared: this.onPrepared,
        allowOpen: !this.preview || this.onPreviewOpen !== undefined,
        onOpen: (opening: ImageOpening | undefined) => {
          // A thumbnail owns a native click recognizer. Forward that action
          // explicitly instead of swallowing it behind allowOpen=false.
          if (this.preview) { this.onPreviewOpen?.(); return }
          const sourceIndex: number = router.getState().index
          ForumImageTransition.beginSource(sourceIndex, AppStorage.get<number>(Constant.KEY_STATUS_BAR_INSET_PX) ?? 0)
          router.pushUrl({ url: 'pages/ForumImagePage', params: new ImageRouteParams(this.source, this.gallery, opening,
            ForumImageTransition.forGallery(this.gallery)) })
            .catch((diagnosticFailure: Object) => {
              ForumImageTransition.finishSource(sourceIndex)
              DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object,
                AppLanguage.text($r('app.string.ui_could_not_open_image_please_retry'), this.languageRevision))
            })
        } })
    } else if (this.failed || ForumStickers.resource(this.source) === undefined) {
      Text('[' + this.label + AppLanguage.text($r('app.string.ui_image_unavailable'), this.languageRevision)).fontSize(13).fontColor(ThemeColors.textHint)
        .onAppear(() => { this.onPrepared() })
        .hitTestBehavior(this.preview ? HitTestMode.None : HitTestMode.Default)
        .onClick(() => { this.failed = false })
    } else {
      Image(this.sticker ? ForumStickers.resource(this.source) : this.source)
        .width(this.sticker ? 50 : '100%').height(this.sticker ? 50 : 220)
        .objectFit(ImageFit.Contain).accessibilityText(this.label)
        .onComplete(() => { this.onPrepared() })
        .onError(() => { this.failed = true; this.onPrepared() })
        .hitTestBehavior(HitTestMode.None)
    }
  }
}

@Component
export struct ForumContentView {
  previewWork: ForumPreviewWork | undefined = undefined
  @StorageLink(ForumPreferences.CLEAN) @Watch('prepareContent') cleanMode: boolean = false
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @Prop @Watch('prepareContent') content: string = ''
  @Prop textSize: number = 16
  @Prop preview: boolean = false
  @Prop coordinatedPreview: boolean = false
  onPrepared: () => void = () => {}
  private preparedParts: Set<number> = new Set<number>()
  private preparation: number = 0
  private preparing: boolean = false
  @Prop mentions: ForumFloor[] = []
  @Prop depth: number = 0
  @Prop gallery: string[] = []
  onPreviewOpen: (() => void) | undefined = undefined
  quoteRepository: ForumQuoteRepository = ForumRepository.getInstance()
  onLocate: (floor: ForumFloor) => void = (floor: ForumFloor) => {
    router.pushUrl({ url: 'pages/ForumDetailPage', params: new HoleRouteParams(floor.holeId, floor.floorId) })
      .catch((diagnosticFailure: Object) => { DiagnosticNavigation.feedback(this.getUIContext(), diagnosticFailure as Object, AppLanguage.text($r('app.string.ui_could_not_open_the_quoted_post'), this.languageRevision)) })
  }

  private imageSources(): string[] {
    if (this.gallery.length > 0) return this.gallery
    return ForumContentParser.parse(this.content).filter((part: ForumContentPart) => part.kind === 'image')
      .map((part: ForumContentPart) => part.source)
  }

  aboutToAppear(): void { this.preparing = true; this.prepareContent() }
  aboutToDisappear(): void { this.preparing = false; this.preparation++ }

  private parts(): ForumContentPart[] {
    return ForumContentParser.displayParts(ForumPreferences.clean(this.content, this.cleanMode)).slice(0, this.preview ? 3 : undefined)
  }
  private prepareContent(): void {
    this.preparation++; this.preparedParts.clear()
    if (this.preparing && this.coordinatedPreview && this.parts().length === 0) this.onPrepared()
  }
  private partReady(index: number): () => void {
    // Full floors are already visible. Do not reparse a long body on every
    // child appearance just to count readiness for an unused card callback.
    if (!this.coordinatedPreview) return (): void => {}
    const preparation: number = this.preparation
    return (): void => {
      if (!this.preparing || preparation !== this.preparation || this.preparedParts.has(index)) return
      this.preparedParts.add(index)
      if (this.preparedParts.size === this.parts().length) this.onPrepared()
    }
  }

  build() {
    Column({ space: this.preview ? 6 : 10 }) {
      ForEach(this.parts(), (part: ForumContentPart, index: number) => {
        if (part.kind === 'inline') {
          if (part.text.length > 1200 || ForumContentParser.needsRich(part.runs.filter((run: ForumContentPart) => run.kind === 'text').map((run: ForumContentPart) => run.text).join(''))) {
            ForumRichText({ content: part.text, textSize: this.textSize, preview: this.preview, previewWork: this.previewWork,
              coordinatedPreview: this.coordinatedPreview, onPrepared: this.partReady(index) })
          } else {
            Text() {
              ForEach(part.runs, (run: ForumContentPart) => {
                if (run.kind === 'text') Span(run.text)
                else if (ForumStickers.resource(run.source) !== undefined) {
                  ImageSpan(ForumStickers.resource(run.source)!).width(36).height(36).verticalAlign(ImageSpanAlignment.CENTER)
                } else Span('[' + run.text + ']')
              })
            }.fontSize(this.textSize).fontColor(ThemeColors.textPrimary).width('100%').textAlign(TextAlign.Start)
              .lineHeight(Math.max(this.textSize + 10, 40)).maxLines(this.preview ? 4 : 100000)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onAppear(this.partReady(index))
          }
        } else if (part.kind === 'text') {
          if (ForumContentParser.needsRich(part.text)) {
            ForumRichText({ content: part.text, textSize: this.textSize, preview: this.preview, previewWork: this.previewWork,
              coordinatedPreview: this.coordinatedPreview, onPrepared: this.partReady(index) })
          } else {
            if (this.preview) {
              Text(part.text.trim()).fontSize(this.textSize).fontColor(ThemeColors.textPrimary)
                .lineHeight(this.textSize + 7).width('100%').textAlign(TextAlign.Start)
                .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
                .onAppear(this.partReady(index))
            } else {
              Column() {
                ForEach(ForumContentParser.textBlocks(part.text), (block: string) => {
                  Text(block).fontSize(this.textSize).fontColor(ThemeColors.textPrimary)
                    .lineHeight(this.textSize + 10).width('100%').textAlign(TextAlign.Start)
                })
              }.width('100%').alignItems(HorizontalAlign.Start).onAppear(this.partReady(index))
            }
          }
        } else if (part.kind === 'floor' || part.kind === 'hole') {
          ForumReference({ referenceId: Number(part.source), kind: part.kind, preview: this.preview || this.depth > 0,
            seed: this.mentions.find((floor: ForumFloor) => part.kind === 'floor' && floor.floorId === Number(part.source)),
            depth: this.depth, quoteRepository: this.quoteRepository, onLocate: this.onLocate, onPrepared: this.partReady(index) })
        } else {
          ForumMedia({ source: part.source, label: part.text, sticker: part.kind === 'sticker',
            preview: this.preview, coordinatedPreview: this.coordinatedPreview, onPrepared: this.partReady(index),
            gallery: this.imageSources(), onPreviewOpen: this.onPreviewOpen })
        }
      })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

/** Author + three-line summary appears when the card is visible. A tap opens
 * full content; it is never required just to resolve an ordinary reference. */
@Component
struct ForumReference {
  private showDetailTransition: SheetTransitionGuard = new SheetTransitionGuard()
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @Prop @Watch('referenceChanged') referenceId: number = 0
  @Prop @Watch('referenceChanged') kind: string = 'floor'
  @Prop preview: boolean = false
  @Prop @Watch('referenceChanged') seed: ForumFloor | undefined = undefined
  @Prop depth: number = 0
  @StorageLink(Constant.KEY_FORUM_FOLD_BEHAVIOR) foldMode: string = 'fold'
  @State floor: ForumFloor | null = null
  @State loading: boolean = false
  @State error: boolean = false
  @State diagnosticError: string = ''
  @State expanded: boolean = false
  @State revealed: boolean = false
  @State showDetail: boolean = false
  @State caution: boolean = false
  private active: boolean = false
  private visible: boolean = false
  private loadVersion: number = 0
  quoteRepository: ForumQuoteRepository = ForumRepository.getInstance()
  onLocate: (floor: ForumFloor) => void = () => {}
  onPrepared: () => void = () => {}

  aboutToAppear(): void {
    this.active = true
    this.referenceChanged()
  }
  aboutToDisappear(): void { this.active = false; this.visible = false; this.loadVersion++ }

  private referenceChanged(): void {
    this.loadVersion++
    // The server already includes resolved ##floor references in mention.
    // Use their author/body immediately, including references made by 0F.
    // A floor's holeId alone cannot establish that it is the hole's 0F;
    // #hole references must still resolve getHole().firstFloor upstream.
    const seed: ForumFloor | undefined = this.seed
    this.floor = this.kind === 'floor' && seed !== undefined && seed.floorId === this.referenceId ? seed : null
    this.loading = false
    this.error = false
    this.expanded = this.floor !== null
    this.revealed = false
    this.showDetail = false
    this.caution = false
    if (this.floor !== null) this.onPrepared()
    if (this.active && this.visible && !this.expanded) this.load()
  }

  private onReferenceVisible(visible: boolean): void {
    this.visible = visible
    if (visible && !this.expanded) this.load()
  }

  private async load(): Promise<void> {
    if (!this.active || this.loading || this.floor !== null) return
    const repo: ForumQuoteRepository = this.quoteRepository
    const scope: number = repo.sessionRevision()
    const version: number = ++this.loadVersion
    this.expanded = true
    this.loading = true
    this.error = false
    try {
      const kind: string = this.kind
      const id: number = this.referenceId
      const content: ForumQuoteContent = await ForumQuoteCache.load(repo, scope, kind, id, async (): Promise<ForumQuoteContent> => {
        if (kind === 'floor') return new ForumQuoteContent(await repo.getFloor(id))
        const hole: ForumHole = await repo.getHole(id)
        return ForumQuoteContent.fromHole(hole, ForumPresentation.isCaution(hole))
      })
      if (!this.active || version !== this.loadVersion || repo !== this.quoteRepository || scope !== repo.sessionRevision()) return
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.caution = content.caution
        this.floor = content.floor
        this.loading = false
      })
    } catch (e) {
      if (this.active && version === this.loadVersion && repo === this.quoteRepository && scope === repo.sessionRevision()) {
        this.error = true; this.diagnosticError = ErrorDiagnostics.message(e as Object)
      }
    } finally {
      if (this.active && version === this.loadVersion && repo === this.quoteRepository && scope === repo.sessionRevision()) {
        this.loading = false; this.onPrepared()
      }
    }
  }

  private hidden(): boolean {
    return !this.revealed && this.foldMode !== 'show' && (this.caution || (this.floor?.fold.length ?? 0) > 0)
  }

  private author(): string {
    return this.floor?.anonyname || AppLanguage.text($r('app.string.ui_anonymous'), this.languageRevision)
  }

  @Builder
  ReferenceAuthor(detail: boolean) {
    Row({ space: 6 }) {
      Row() {}.width(4).height(detail ? 22 : 18).borderRadius(2)
        .backgroundColor(ForumPresentation.authorColor(this.author(), this.darkMode))
      Text(this.floor !== null ? this.author() : AppLanguage.text($r('app.string.ui_quote'), this.languageRevision) +
        (this.kind === 'floor' ? '##' : '#') + this.referenceId)
        .fontColor(ForumPresentation.authorColor(this.author(), this.darkMode))
        .fontSize(detail ? 16 : 14).lineHeight(detail ? 24 : 21).fontWeight(FontWeight.Bold).layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Center).padding({ right: detail ? 40 : 0 })
  }

  @Builder
  ReferenceDetail() {
    Column({ space: 12 }) {
      this.ReferenceAuthor(true)
      Scroll() {
        Column() {
          if (this.floor?.deleted) { Text(AppLanguage.text($r('app.string.ui_this_floor_was_deleted'), this.languageRevision)).fontColor(ThemeColors.textSecondary).lineHeight(22) }
          else if (this.hidden()) {
            Text(AppLanguage.text($r('app.string.ui_quoted_content_collapsed'), this.languageRevision) + (this.floor?.getFoldReason() || AppLanguage.text($r('app.string.ui_read_with_care'), this.languageRevision))).fontColor(ThemeColors.textSecondary).lineHeight(22)
            Button(AppLanguage.text($r('app.string.ui_expand_content'), this.languageRevision)).onClick(() => { this.revealed = true })
          } else if (this.depth < 6) {
            ForumContentView({ content: this.floor?.content ?? '', mentions: this.floor?.mention ?? [],
              depth: this.depth + 1, quoteRepository: this.quoteRepository, onLocate: (floor: ForumFloor) => {
                this.showDetail = false
                this.onLocate(floor)
              } })
          } else {
            Text(ForumContentParser.summary(this.floor?.content ?? '')).width('100%').fontColor(ThemeColors.textPrimary).lineHeight(23)
          }
        // Keep the detail body distinct from the gray references rendered inside it.
        }.width('100%').padding(14).borderRadius(14).backgroundColor(ThemeColors.cardBg)
      }.constraintSize({ maxHeight: 420 }).width('100%').scrollBar(BarState.Off)
      Row({ space: 12 }) {
        FloatingActionButton({ label: $r('app.string.ui_go_to_quoted_floor'), actionEnabled: ForumQuoteContent.canNavigate(this.floor),
          onAction: () => {
            this.showDetail = false
            if (this.floor !== null) this.onLocate(this.floor)
          } }).layoutWeight(1)
        FloatingActionButton({ label: $r('app.string.ui_close'), onAction: () => { this.showDetail = false } }).layoutWeight(1)
      }.width('100%')
    }.width('100%').padding(20)
  }

  private previewText(): string {
    return this.error ? AppLanguage.text($r('app.string.ui_quote_not_found_tap_to_retry'), this.languageRevision) : this.loading ? AppLanguage.text($r('app.string.ui_loading_quote'), this.languageRevision) :
      this.floor === null ? AppLanguage.text($r('app.string.ui_loading_quote'), this.languageRevision) : this.floor.deleted ? AppLanguage.text($r('app.string.ui_this_floor_was_deleted'), this.languageRevision) :
      this.hidden() ? AppLanguage.text($r('app.string.ui_quoted_content_collapsed_tap_to_view'), this.languageRevision) : ForumContentParser.summary(this.floor.content, false)
  }

  build() {
    Column({ space: 8 }) {
      this.ReferenceAuthor(false)
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach([this.previewText()], (text: string) => {
          Text(text).fontSize(13).lineHeight(20).fontColor(ThemeColors.textSecondary)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
        }, (text: string) => text)
      }.width('100%')
      if (this.error) { DiagnosticLink({ message: this.diagnosticError,
        summary: AppLanguage.text($r('app.string.ui_quote_not_found_tap_to_retry'), this.languageRevision), controlId: 'quote-read-diagnostics' }) }
    }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 }).borderRadius(12).backgroundColor($r('app.color.quote_surface'))
      
      .alignItems(HorizontalAlign.Start)
      .onVisibleAreaChange([0.01], (visible: boolean) => { this.onReferenceVisible(visible) })
      .onClick(() => {
        if (this.floor === null) this.load()
        else this.showDetailTransition.open(() => {
          if (this.active && this.floor !== null) this.showDetail = true
        }, () => this.getUIContext())
      })
      .bindSheet($$this.showDetail, this.ReferenceDetail(), this.showDetailTransition.options(this.showDetail, { height: SheetSize.FIT_CONTENT, showClose: true, dragBar: true,
        backgroundColor: nativeFloatingBackground(this.materialRevision), systemMaterial: adaptiveMaterial(this.materialRevision) }))
  }
}
