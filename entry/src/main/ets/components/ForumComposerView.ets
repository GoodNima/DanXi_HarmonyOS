import { ReadableText } from '../common/ReadableText'
import { ErrorNotice } from './ErrorNotice'
import { AppLanguage } from '../common/AppLanguage'
import { SearchClearButton } from './SearchClearButton'
import { EmptyRefreshIndicator, FeedRefreshProgress } from './FeedRefreshProgress'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
import { TopFade } from './TopFade'
import { FloatingActionButton } from './FloatingActionButton'
import { FloatingSurface } from './FloatingSurface'
/**
 * Tree Hole composer (发帖).
 *
 * Holes have no title — body, selected/custom tags and division form the payload:
 * POST /divisions/{divisionId}/holes with {content, tags}. Ported from
 * lib/page/forum/hole_editor.dart (full-screen mode).
 */

import { router, promptAction } from '@kit.ArkUI'
import { ForumRepository } from '../repository/ForumRepository'
import { ForumTag, ForumDivision } from '../model/Forum'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { Constant } from '../common/Constant'
import { ForumPresentation } from '../common/ForumPresentation'

import { ForumComposer, ForumComposerDraft } from '../common/ForumComposer'
import { ForumPreferences } from '../common/ForumPreferences'
import { ForumStickers } from '../common/ForumStickers'
import { AppState } from '../common/AppState'
import { ForumContentView } from './ForumContentView'
import { getSymbolIcon } from '../common/DanXiIcons'
import { BrowserLink } from '../common/BrowserLink'
import { common } from '@kit.AbilityKit'
import { picker, fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { ForumImage } from '../model/ForumImage'
import { PreferencesUtil } from '../util/PreferencesUtil'

export interface ForumComposerSource {
  getTags(): Promise<ForumTag[]>
  getDivisions(): Promise<ForumDivision[]>
  createHole(divisionId: number, content: string, tags: ForumTag[]): Promise<void>
  uploadImage(path: string, filename: string): Promise<string>
}
const MAX_LENGTH: number = 2000

@Component
export struct ForumComposerView {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(ForumPreferences.TAG_SUGGESTIONS) suggestionsEnabled: boolean = false
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @State content: string = ''
  @State tags: ForumTag[] = []
  @State divisions: ForumDivision[] = []
  @State selectedTags: ForumTag[] = []
  @State previewDraft: boolean = false
  @State showStickers: boolean = false
  @State fullscreen: boolean = false
  @State uploading: boolean = false
  @State editorError: string = ''
  @State tip: string = ''
  @State divisionId: number = 0
  @State divisionName: string = ''
  @State isLoadingTags: boolean = true
  @State isPublishing: boolean = false
  @State tagQuery: string = ''
  @State tagPage: number = 0
  @State tagError: string = ''
  @State divisionError: string = ''
  @State refreshing: boolean = false
  @State private pullOffset: number = 0
  private allTags: ForumTag[] = []
  private active: boolean = true

  source: ForumComposerSource = ForumRepository.getInstance()
  initialDivisionId: number = 0
  initialDivisionName: string = ''
  draftScope: string = ''
  onPublished: () => void = () => { router.back() }
  onClose: () => void = () => { router.back() }
  private owner: string = ''
  private controller: TextAreaController = new TextAreaController()
  private selectionStart: number = 0
  private selectionEnd: number = 0
  private caretTimer: number = -1
  private stopWords: string[] = []
  private confirmation: boolean = false
  private optionsFlight: Promise<void> | null = null

  aboutToAppear(): void {
    this.active = true
    this.owner = this.draftScope || String(AppStorage.get<number>(ForumPreferences.USER_ID) ?? 0) + ':' + AppState.getPerson().getStudentId()
    const draft = ForumComposer.restore(this.owner)
    if (draft !== undefined) {
      this.content = draft.content; this.selectedTags = draft.tags; this.divisionId = draft.divisionId; this.divisionName = draft.divisionName
    } else { this.divisionId = this.initialDivisionId; this.divisionName = this.initialDivisionName }
    this.selectionStart = this.content.length; this.selectionEnd = this.content.length
    this.refreshOptions(); this.loadHints()
  }
  aboutToDisappear(): void {
    this.saveDraft(); this.active = false
    if (this.caretTimer >= 0) clearTimeout(this.caretTimer)
    this.caretTimer = -1
  }

  private updateTags(): void {
    this.tags = ForumPresentation.tagSuggestions(this.allTags, this.tagQuery, this.tagPage)
  }

  private async loadTags(): Promise<void> {
    await this.source.getTags().then((data: ForumTag[]) => {
      if (!this.active) return
      this.allTags = data
      this.tagError = ''
      this.updateTags()
      this.isLoadingTags = false
    }).catch((e: Object) => {
      if (!this.active) return
      // Tags are optional — posting works without one.
      this.isLoadingTags = false
      this.tagError = ForumRepository.describeError(e)
    })
  }

  private async loadDivisions(): Promise<void> {
    await this.source.getDivisions().then((data: ForumDivision[]) => {
      if (!this.active) return
      this.divisions = data
      this.divisionError = ''
      if (!data.some(row => row.divisionId === this.divisionId) && data.length > 0) {
        this.divisionId = data[0].divisionId; this.divisionName = data[0].name
      }
    }).catch((e: Object) => {
      if (this.active) this.divisionError = ForumRepository.describeError(e)
    })
  }

  private refreshOptions(): Promise<void> {
    if (this.optionsFlight !== null) return this.optionsFlight
    const task = Promise.all([this.loadTags(), this.loadDivisions()]).then(() => {})
    this.optionsFlight = task
    task.finally(() => { if (this.optionsFlight === task) { this.optionsFlight = null; this.refreshing = false } })
    return task
  }

  private publish(): void {
    if (this.isPublishing || this.uploading) return
    const text: string = this.content.trim()
    if (text.length === 0) {
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_enter_some_content'), this.languageRevision) })
      return
    }
    if (text.length > MAX_LENGTH) { this.editorError = AppLanguage.text($r('app.string.detail_content_limit')); return }
    if (this.divisionId <= 0) {
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_choose_a_section'), this.languageRevision) })
      return
    }
    const chosen: ForumTag[] = this.selectedTags.slice()
    const submittedContent: string = this.content
    const submittedDivision: number = this.divisionId
    const sent = this.snapshot(); const owner = this.owner
    this.saveDraft()
    this.isPublishing = true
    this.source.createHole(submittedDivision, text, chosen).then(() => {
      // ForumPage stays mounted inside Tabs, so router.back() alone would not
      // re-run its aboutToAppear and the new hole would not show up.
      AppStorage.setOrCreate<number>('forum_feed_refresh', Date.now())
      ForumComposer.clearIf(owner, sent)
      if (!this.active) return
      this.isPublishing = false
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_post_published'), this.languageRevision) })
      // Keep any text or selection the user changed while the request ran.
      // The sent snapshot is already posted; new input belongs to a new draft.
      if (this.content === submittedContent && this.divisionId === submittedDivision &&
        JSON.stringify(this.selectedTags) === JSON.stringify(sent.tags)) {
        this.content = ''; this.selectedTags = []; this.saveDraft(); ForumComposer.clearIf(owner, this.snapshot()); this.onPublished()
      }
    }).catch((e: Object) => {
      if (!this.active) return
      this.isPublishing = false
      this.editorError = ForumRepository.describeError(e)
    })
  }


  private snapshot(): ForumComposerDraft {
    const draft = new ForumComposerDraft(); draft.content = this.content; draft.divisionId = this.divisionId
    draft.divisionName = this.divisionName; draft.tags = this.selectedTags.slice(); return draft
  }
  private saveDraft(): void { ForumComposer.save(this.owner, this.snapshot()) }
  private async loadHints(): Promise<void> {
    try {
      const resources = this.getUIContext().getHostContext()!.resourceManager
      const words = await resources.getRawFileContent('forum_stop_words.dat')
      if (!this.active) return
      this.stopWords = util.TextDecoder.create('utf-8').decodeWithStream(words).split(/\r?\n/)
      const data = await resources.getRawFileContent('forum_tips.dat')
      if (!this.active) return
      const tips = util.TextDecoder.create('utf-8').decodeWithStream(data).split(/\r?\n/).filter(value => !!value.trim())
      this.tip = tips[Math.floor(Math.random() * tips.length)] ?? ''
    } catch (e) {}
  }
  private toggleTag(tag: ForumTag): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.selectedTags = this.selectedTags.some(item => item.name === tag.name) ? this.selectedTags.filter(item => item.name !== tag.name) : this.selectedTags.concat([tag])
    })
    this.saveDraft()
  }
  private panel(kind: string): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
      if (kind === 'preview') this.previewDraft = !this.previewDraft
      if (kind === 'stickers') this.showStickers = !this.showStickers
      if (kind === 'focus') this.fullscreen = !this.fullscreen
    })
  }
  private addTag(): void {
    const tag = ForumComposer.customTag(this.tagQuery)
    if (tag === undefined) return
    if (!this.selectedTags.some(item => item.name === tag.name)) this.selectedTags = this.selectedTags.concat([this.allTags.find(item => item.name === tag.name) ?? tag])
    this.tagQuery = ''; this.tagPage = 0; this.updateTags(); this.saveDraft()
  }
  private suggest(enabled: boolean): void {
    this.suggestionsEnabled = enabled
    PreferencesUtil.getInstance().putBoolean(ForumPreferences.TAG_SUGGESTIONS, enabled).catch((e: Object) => {
      if (this.active) this.editorError = ForumRepository.describeError(e)
    })
  }
  private insert(before: string, after: string = ''): void {
    const edit = ForumComposer.insert(this.content, this.selectionStart, this.selectionEnd, before, after)
    if (edit === undefined) { this.editorError = AppLanguage.text($r('app.string.detail_content_limit')); return }
    this.content = edit.content; this.selectionStart = edit.start; this.selectionEnd = edit.end; this.saveDraft()
    if (this.caretTimer >= 0) clearTimeout(this.caretTimer)
    this.caretTimer = setTimeout(() => {
      this.caretTimer = -1
      if (!this.active || this.previewDraft) return
      if (this.selectionEnd > this.selectionStart) this.controller.setTextSelection(this.selectionStart, this.selectionEnd)
      else this.controller.caretPosition(this.selectionStart)
    }, 0)
  }
  private async image(): Promise<void> {
    if (!this.active || this.uploading || this.isPublishing) return
    this.uploading = true; this.editorError = ''
    let cache: string = ''
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 1; options.fileSuffixFilters = ['.jpg,.jpeg,.png,.gif,.webp,.heic,.heif,.avif,.bmp']
      const selected = await new picker.DocumentViewPicker(context).select(options)
      if (!this.active || selected.length === 0) return
      const filename = ForumImage.filename(selected[0])
      cache = context.cacheDir + '/danxi-compose-' + Date.now() + '-' + filename
      const file = await fs.open(selected[0], fs.OpenMode.READ_ONLY)
      try { if (!this.active) return; await fs.copyFile(file.fd, cache) } finally { await fs.close(file) }
      if (!this.active) return
      const source = await this.source.uploadImage(cache, filename)
      if (!this.active) return
      const appended = (this.content ? '\n' : '') + '![](' + source + ')\n'
      if (this.content.length + appended.length > MAX_LENGTH) { this.editorError = AppLanguage.text($r('app.string.detail_image_too_long')); return }
      this.content += appended; this.selectionStart = this.content.length; this.selectionEnd = this.content.length; this.saveDraft()
    } catch (e) { if (this.active) this.editorError = ForumRepository.describeError(e as Object) }
    finally { if (cache) { try { await fs.unlink(cache) } catch (e) {} }; if (this.active) this.uploading = false }
  }
  private async requestPublish(): Promise<void> {
    if (this.isPublishing || this.uploading || this.confirmation) return
    const warning = ForumComposer.warning(this.content, this.stopWords)
    if (warning) {
      this.confirmation = true; const snapshot = JSON.stringify(this.snapshot())
      try {
        const result = await promptAction.showDialog({ title: AppLanguage.text($r('app.string.composer_warning_title')),
          message: AppLanguage.text($r('app.string.composer_warning')).replace('{word}', warning),
          buttons: [{ text: AppLanguage.text($r('app.string.forum_cancel')), color: '#808080' },
            { text: AppLanguage.text($r('app.string.composer_send_anyway')), color: '#D83232' }] })
        if (!this.active || result.index !== 1 || JSON.stringify(this.snapshot()) !== snapshot) return
      } finally { this.confirmation = false }
    }
    this.publish()
  }
  private help(): void {
    promptAction.showDialog({ title: AppLanguage.text($r('app.string.composer_help')), message: AppLanguage.text($r('app.string.composer_help_note')),
      buttons: [{ text: AppLanguage.text($r('app.string.ui_close')), color: '#458ED1' }] })
  }
  private community(): void {
    BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, 'https://www.fduhole.com/doc')
      .catch((e: Object) => { if (this.active) this.editorError = ForumRepository.describeError(e) })
  }
  @Builder
  Tool(icon: Resource, label: Resource, action: () => void, selected: boolean = false, name: string = '') {
    Button({ type: ButtonType.Circle }) { SymbolGlyph(icon).fontSize(21)
      .fontColor([selected ? ThemeColors.primary : ThemeColors.textSecondary]) }
      .width(42).height(42).padding(0).backgroundColor(Color.Transparent).stateEffect(false).enabled(!this.isPublishing)
      .id(name ? 'composer-' + name : '').accessibilityText(label).onClick(action)
  }
  @Builder
  EditorTools() {
    Row() {
      this.Tool($r('sys.symbol.bold'), $r('app.string.composer_bold'), () => { this.insert('**', '**') })
      this.Tool($r('sys.symbol.italic'), $r('app.string.composer_italic'), () => { this.insert('*', '*') })
      Button({ type: ButtonType.Circle }) { Text('∑').fontSize(24).fontColor(ThemeColors.textSecondary) }
        .width(42).height(42).padding(0).backgroundColor(Color.Transparent).stateEffect(false)
        .accessibilityText($r('app.string.composer_formula')).onClick(() => { this.insert('$', '$') })
      this.Tool(getSymbolIcon('image'), $r('app.string.detail_image_add'), () => { this.image() }, false, 'image')
      this.Tool($r('sys.symbol.face_smiling'), $r('app.string.composer_stickers'), () => { this.panel('stickers') }, this.showStickers, 'stickers')
      this.Tool($r('sys.symbol.eye'), $r('app.string.detail_preview'), () => { this.panel('preview') }, this.previewDraft, 'preview')
    }.width('100%').justifyContent(FlexAlign.SpaceBetween)
    if (this.uploading) Text($r('app.string.detail_image_uploading')).fontSize(12).fontColor(ThemeColors.primary)
    if (this.showStickers) {
      Grid() {
        ForEach(ForumStickers.ids(), (id: string) => {
          GridItem() { Image(ForumStickers.resource(id)).width(42).height(42).objectFit(ImageFit.Contain) }
            .onClick(() => { this.insert('![](' + id + ')') })
        }, (id: string) => id)
      }.columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr').rowsGap(10).height(224).width('100%')
    }
    if (ForumComposer.images(this.content).length > 0) {
      Text(ReadableText.resource($r('app.string.composer_images_note'))).fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
      ForEach(ForumComposer.images(this.content), (source: string, index: number) => {
        Row({ space: 8 }) {
          SymbolGlyph(getSymbolIcon('image')).fontSize(16).fontColor([ThemeColors.primary])
          Text(AppLanguage.text($r('app.string.composer_image_number')).replace('{index}', String(index + 1))).fontSize(13).layoutWeight(1)
          this.Tool($r('sys.symbol.xmark'), $r('app.string.composer_remove_image'), () => { this.content = ForumComposer.removeImage(this.content, source); this.saveDraft() })
        }.width('100%')
      }, (source: string) => source)
    }
  }

  @Builder
  TagChip(tag: ForumTag) {
    Button() {
      Row({ space: 5 }) {
        Text(ForumPresentation.tagLabel(tag.name)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.selectedTags.some(item => item.name === tag.name)) { SymbolGlyph($r('sys.symbol.xmark')).fontSize(10) }
      }.constraintSize({ maxWidth: 240 })
    }
      .fontSize(ThemeDimens.textSizeBody)
      .fontColor(ForumPresentation.featured(tag.name) ? Color.White : this.selectedTags.some(item => item.name === tag.name) ? (this.darkMode ? '#1C1C1E' : '#FFFFFF') : ForumPresentation.tagColor(tag.name, this.darkMode))
      .backgroundColor(this.selectedTags.some(item => item.name === tag.name) ? ForumPresentation.tagColor(tag.name, this.darkMode) : ForumPresentation.tagBackground(tag.name, this.darkMode))
      .linearGradient({ direction: GradientDirection.Right, colors: ForumPresentation.featured(tag.name) ? [['#007AFF', 0], ['#009AD8', 1]] : [[Color.Transparent, 0], [Color.Transparent, 1]] })
      .borderRadius(8).clip(true)
      .height(32).padding({ left: 12, right: 12 }).stateEffect(false)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.toggleTag(tag)
      })
  }

  @Builder
  DivisionChip(division: ForumDivision) {
    Text(division.name)
      .fontSize(ThemeDimens.textSizeBody)
      .fontColor(this.divisionId === division.divisionId ? '#FFFFFF' : ThemeColors.textSecondary)
      .backgroundColor(this.divisionId === division.divisionId ? ThemeColors.primary : $r('app.color.input_surface'))
      .borderRadius(16)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .margin({ right: 8 })
      .onClick(() => {
        this.divisionId = division.divisionId
        this.divisionName = division.name; this.saveDraft()
      })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column()
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .linearGradient({
          angle: 135,
          colors: [[ThemeColors.bgStart, 0], [ThemeColors.bgEnd, 1]],
          repeating: false,
        })

        Refresh({ refreshing: $$this.refreshing, builder: EmptyRefreshIndicator }) {
        Scroll() {
          Column() {
            // ── division ──
            if (!this.fullscreen) {
            if (this.divisions.length > 0) {
              Column() {
                Text(AppLanguage.text($r('app.string.ui_choose_section'), this.languageRevision))
                  .fontSize(ThemeDimens.textSizeSmall)
                  .fontColor(ThemeColors.textSecondary)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                Scroll() {
                  Row() {
                    ForEach(this.divisions, (division: ForumDivision) => {
                      this.DivisionChip(division)
                    }, (division: ForumDivision) => String(division.divisionId))
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
                .margin({ top: 10 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 12, right: 12 })
            } else if (this.divisionName.length > 0) {
              Row() {
                Text(AppLanguage.text($r('app.string.ui_section'), this.languageRevision))
                  .fontSize(ThemeDimens.textSizeSmall)
                  .fontColor(ThemeColors.textHint)
                Text(this.divisionName)
                  .fontSize(ThemeDimens.textSizeSmall)
                  .fontColor(ThemeColors.primary)
                  .margin({ left: 8 })
                Blank()
              }
              .width('100%')
              .padding({ left: 12, right: 12 })
            }
            if (this.divisionError.length > 0) {
              ErrorNotice({ message: this.divisionError, controlId: 'forumcomposerview-diagnostics', textSize: 12, textColor: ThemeColors.error }).padding(12)
            }

            }
            // ── body ──
            Column() {
              if (this.previewDraft && this.content) {
                ForumContentView({ content: this.content, preview: true })
              } else {
              TextArea({ text: this.content, placeholder: AppLanguage.text($r('app.string.ui_say_something'), this.languageRevision), controller: this.controller })
                .width('100%')
                .id('composer-body').height(this.fullscreen ? 400 : 180)
                .backgroundColor(Color.Transparent)
                .padding({ left: 8, right: 8, top: 10, bottom: 10 })
                .fontSize(ThemeDimens.textSizeTitle)
                .fontColor(ThemeColors.textPrimary)
                .placeholderColor(ThemeColors.textHint)
                .maxLength(MAX_LENGTH)
                .onChange((value: string) => {
                  this.content = value; this.saveDraft()
                })
                .onTextSelectionChange((start: number, end: number) => { this.selectionStart = start; this.selectionEnd = end })
              }
              Row() {
                Text(ReadableText.resource($r('app.string.composer_draft_note'))).fontSize(11).lineHeight(19).fontColor(ThemeColors.textHint).layoutWeight(1).lineBreakStrategy(LineBreakStrategy.GREEDY)
                Text(this.content.length + ' / ' + MAX_LENGTH)
                  .fontSize(ThemeDimens.textSizeSmall)
                  .fontColor(ThemeColors.textHint)
              }
              .width('100%')
              this.EditorTools()
              if (this.editorError) ErrorNotice({ message: this.editorError, controlId: 'forumcomposerview-diagnostics', textSize: 13, textColor: ThemeColors.error }).width('100%')
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
            .borderRadius(ThemeDimens.radiusLarge)
            .margin({ top: 16 })

            if (!this.fullscreen) {
            // ── tags ──
            Column() {
              Row({ space: 8 }) {
                Text(AppLanguage.text($r('app.string.ui_tags'), this.languageRevision))
                  .fontSize(ThemeDimens.textSizeSmall)
                  .fontColor(ThemeColors.textSecondary)
                Text(AppLanguage.text($r('app.string.composer_tags_note'), this.languageRevision))
                  .fontSize(ThemeDimens.textSizeSmall)
                  .fontColor(ThemeColors.textHint)
                Blank()
              }
              .width('100%')

              if (this.selectedTags.length > 0) {
                Flex({ wrap: FlexWrap.Wrap }) { ForEach(this.selectedTags, (tag: ForumTag) => { this.TagChip(tag) }, (tag: ForumTag) => tag.name) }
                  .width('100%').margin({ top: 12, bottom: 4 }).id('composer-selected-tags')
              }
              Row({ space: 8 }) {
                Text($r('app.string.composer_recommend')).fontSize(14).fontColor(ThemeColors.textSecondary).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.suggestionsEnabled }).onChange((enabled: boolean) => { this.suggest(enabled) })
              }.width('100%').margin({ top: 8 })
              if (this.suggestionsEnabled) {
                Text(ReadableText.resource($r('app.string.composer_recommend_note'))).fontSize(11).lineHeight(19).fontColor(ThemeColors.textHint).width('100%').lineBreakStrategy(LineBreakStrategy.GREEDY)
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(ForumComposer.recommendations(this.allTags, this.content).filter(tag => !this.selectedTags.some(item => item.name === tag.name)),
                    (tag: ForumTag) => { this.TagChip(tag) }, (tag: ForumTag) => tag.name)
                }.width('100%')
              }
              Row({ space: 8 }) {
              TextInput({ text: this.tagQuery, placeholder: AppLanguage.text($r('app.string.composer_search_custom_tag'), this.languageRevision) })
                .height(40).layoutWeight(1).maxLength(128).cancelButton({ style: CancelButtonStyle.INVISIBLE }).onSubmit(() => { this.addTag() })
                .onChange((value: string) => {
                  this.tagQuery = value
                  this.tagPage = 0
                  this.updateTags()
                })

              if (this.tagQuery.length > 0) {
                SearchClearButton({ controlId: 'composer-tag-clear', onClear: () => { this.tagQuery = ''; this.tagPage = 0; this.updateTags() } })
              }
              Button($r('app.string.composer_add_tag')).height(36).fontSize(13).enabled(!!ForumComposer.customTag(this.tagQuery)).onClick(() => { this.addTag() })
              }.width('100%').margin({ top: 12 })
              if (this.isLoadingTags) {
                LoadingProgress().width(22).height(22).color(ThemeColors.primary).margin({ top: 12 })
              } else if (this.tags.length === 0) {
                if (this.tagError) { ErrorNotice({ message: this.tagError, controlId: 'composer-tags-diagnostics' }).margin({ top: 10 }) }
                else Text(AppLanguage.text($r('app.string.ui_no_matching_tags_you_can_publish_without_one'), this.languageRevision))
                  .fontSize(ThemeDimens.textSizeSmall)
                  .fontColor(ThemeColors.textHint)
                  .margin({ top: 10 })
              } else {
                Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.tags.filter(tag => !this.selectedTags.some(item => item.name === tag.name)), (tag: ForumTag) => {
                      this.TagChip(tag)
                    }, (tag: ForumTag) => String(tag.tagId) + ':' + tag.name)
                }
                .width('100%')
                .margin({ top: 10 })
              }
              if (this.tagPage > 0 || ForumPresentation.tagSuggestions(this.allTags, this.tagQuery, this.tagPage + 1).length > 0) {
              Row({ space: 12 }) {
                Button(AppLanguage.text($r('app.string.ui_previous'), this.languageRevision)).enabled(this.tagPage > 0).onClick(() => {
                  this.tagPage--
                  this.updateTags()
                })
                Button(AppLanguage.text($r('app.string.ui_next'), this.languageRevision))
                  .enabled(ForumPresentation.tagSuggestions(this.allTags, this.tagQuery, this.tagPage + 1).length > 0)
                  .onClick(() => {
                    this.tagPage++
                    this.updateTags()
                  })
              }.margin({ top: 8 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12 })
            .margin({ top: 20, bottom: 16 })
            Text(this.tip).width('100%').fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).id('composer-civil-tip')
            Row({ space: 12 }) {
              Button($r('app.string.composer_help')).height(36).fontSize(13).onClick(() => { this.help() })
              Button($r('app.string.composer_community')).height(36).fontSize(13).onClick(() => { this.community() })
            }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 16, bottom: 8 }).id('composer-help-links')
            }
          }
          .width('100%')
          // Keep initial header clearance inside the scrolling content.
          .padding({ left: 12, right: 12, top: px2vp(this.topPx) + 76,
            bottom: Math.max(16, px2vp(this.bottomPx)) + 12 })
        }
        .height('100%')
        .width('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
        }.height('100%').width('100%').onOffsetChange((offset: number) => { this.pullOffset = offset }).onRefreshing(() => { this.refreshOptions() })
      TopFade({ extent: px2vp(this.topPx) + 56 })
      FeedRefreshProgress({ topInset: px2vp(this.topPx) + 88, pullOffset: this.pullOffset, refreshing: this.refreshing })
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          Text($r('app.string.forum_compose')).fontSize(ThemeDimens.textSizeTitle).fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary).textAlign(TextAlign.Center).constraintSize({ maxWidth: 160 })
        Row({ space: 8 }) {
          FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48, actionEnabled: !this.isPublishing,
            onAction: this.onClose }).width(48)
          Blank()
          FloatingSurface({ radius: 22, acceptsInput: true, content: () => {
            this.Tool($r('sys.symbol.arrow_up_left_and_arrow_down_right'), $r('app.string.composer_fullscreen'), () => { this.panel('focus') }, this.fullscreen, 'focus')
          } }).width(44).height(44)
          FloatingActionButton({ label: this.isPublishing ? $r('app.string.forum_publishing') : $r('app.string.forum_publish'),
            actionEnabled: !this.isPublishing && !this.uploading, emphasized: true, onAction: () => { this.requestPublish() } }).width(72)
        }.width('100%').height(56).padding({ left: 12, right: 12 })
        }.width('100%').height(56)
      }.width('100%').padding({ top: px2vp(this.topPx) }).hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
