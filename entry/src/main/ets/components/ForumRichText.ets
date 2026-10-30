import { util } from '@kit.ArkTS'
import { ForumStickers } from '../common/ForumStickers'
import { ForumContentPart } from '../model/ForumContent'
import { webview } from '@kit.ArkWeb'
import { common } from '@kit.AbilityKit'
import { BrowserLink } from '../common/BrowserLink'
import { ThemeColors } from '../common/Theme'
import { ForumContentParser } from '../model/ForumContent'
import { ForumPreviewWork } from '../common/ForumPreviewWork'

class RichPayload {
  content: string = ''
  stickers: Record<string, string> = {}
  fontSize: number = 16
  dark: boolean = false
  preview: boolean = false
}

/** The only native bridge capabilities are measuring text and opening public links. */
class ForumRichBridge {
  onLayout: (height: number) => void = () => {}
  onLink: (url: string) => void = () => {}
  onOverflow: () => void = () => {}
  layout(value: string): void {
    const height: number = Number(value)
    if (!Number.isFinite(height) || height <= 0) return
    if (height > 32000) this.onOverflow()
    else this.onLayout(height)
  }
  link(value: string): void { if (BrowserLink.normalize(value)) this.onLink(value) }
}

@Component
export struct ForumRichText {
  previewWork: ForumPreviewWork | undefined = undefined
  @Prop coordinatedPreview: boolean = false
  onPrepared: () => void = () => {}
  @Prop @Watch('render') content: string = ''
  @Prop @Watch('render') textSize: number = 16
  @Prop @Watch('render') preview: boolean = false
  @StorageLink('app_dark_mode') @Watch('render') dark: boolean = false
  @StorageLink('app_font_scale') @Watch('render') fontScale: number = 1
  @State measuredHeight: number = 32
  @State failed: boolean = false
  @State private firstLayoutReceived: boolean = false
  @State private richOpacity: number = 0
  @State private hostEnabled: boolean = true
  private visible: boolean = false
  private previewJob: number = -1
  private ready: boolean = false
  private active: boolean = false
  private layoutVersion: number = 0
  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: ForumRichBridge = new ForumRichBridge()

  aboutToAppear(): void {
    this.active = true
    const version: number = ++this.layoutVersion
    this.firstLayoutReceived = false
    this.richOpacity = 0
    this.hostEnabled = !this.preview || this.previewWork === undefined
    // Keep each native Web host's proxy independent. A late layout from a
    // disposed host must not dismiss the next host's initial loading hint.
    this.bridge = new ForumRichBridge()
    this.bridge.onLayout = (height: number): void => {
      if (this.active && version === this.layoutVersion) {
        const first: boolean = !this.firstLayoutReceived
        this.measuredHeight = height
        this.firstLayoutReceived = true
        if (first && this.preview) this.revealPreview(version)
        this.releasePreview()
      }
    }
    this.bridge.onLink = (address: string): void => {
      if (!this.active || version !== this.layoutVersion) return
      BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, address).catch(() => {})
    }
    this.bridge.onOverflow = (): void => {
      if (this.active && version === this.layoutVersion) { this.failed = true; this.releasePreview() }
    }
    if (this.content.length > 100000) this.failed = true
  }
  aboutToDisappear(): void { this.active = false; this.ready = false; this.layoutVersion++; this.releasePreview() }

  private releasePreview(): void {
    if (this.previewJob >= 0) this.previewWork?.finish(this.previewJob)
    this.previewJob = -1
  }

  private visibilityChanged(visible: boolean): void {
    this.visible = visible
    if (!visible) { if (!this.hostEnabled) this.releasePreview(); return }
    if (!this.active || this.hostEnabled || this.previewJob >= 0 || this.previewWork === undefined) return
    this.previewJob = this.previewWork.request(this.getUIContext(), (): boolean => {
      if (!this.active || !this.visible) { this.previewJob = -1; return false }
      this.hostEnabled = true
      return true
    })
  }

  render(): void {
    if (!this.ready || !this.active) return
    const version: number = this.layoutVersion
    const payload = new RichPayload()
    payload.content = this.content
    payload.stickers = this.stickerImages()
    payload.fontSize = this.textSize * this.fontScale
    payload.dark = this.dark
    payload.preview = this.preview
    try {
      this.controller.runJavaScript('ForumRich.setContent(' + JSON.stringify(payload) + ')')
        .catch(() => { if (this.active && version === this.layoutVersion) { this.failed = true; this.releasePreview() } })
    } catch (e) { if (this.active && version === this.layoutVersion) { this.failed = true; this.releasePreview() } }
  }

  private stickerImages(): Record<string, string> {
    const result: Record<string, string> = {}
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const encoder: util.Base64Helper = new util.Base64Helper()
      for (const part of ForumContentParser.parse(this.content)) {
        if (part.kind !== 'sticker' || result[part.source]) continue
        const resource: Resource | undefined = ForumStickers.resource(part.source)
        if (resource !== undefined) {
          const bytes: Uint8Array = context.resourceManager.getMediaContentSync(resource.id)
          result[part.source] = 'data:image/webp;base64,' + encoder.encodeToStringSync(bytes)
        }
      }
    } catch (e) {}
    return result
  }

  private pageEnded(): void {
    if (!this.active) return
    this.ready = true
    this.render()
  }

  private receiveError(mainFrame: boolean): void {
    if (this.active && mainFrame) { this.failed = true; this.releasePreview() }
  }

  private revealPreview(version: number): void {
    // The DOM measurement precedes the asynchronous Web surface's first paint.
    // Keep readable native text through that handoff; no blank/loading-ball phase.
    this.getUIContext().postFrameCallback({ onFrame: () => {
      if (!this.active || version !== this.layoutVersion) return
      this.getUIContext().postFrameCallback({ onFrame: () => {
        if (!this.active || version !== this.layoutVersion) return
        if (this.coordinatedPreview) this.richOpacity = 1
        else this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.richOpacity = 1 })
        this.onPrepared()
      }, onIdle: () => {} })
    }, onIdle: () => {} })
  }

  build() {
    if (this.failed) {
      Column() {
        ForEach(ForumContentParser.textBlocks(this.content), (block: string) => {
          Text(block).fontSize(this.textSize).lineHeight(this.textSize + (this.preview ? 7 : 10)).fontColor(ThemeColors.textPrimary).width('100%')
        })
      }.width('100%').alignItems(HorizontalAlign.Start).onAppear(() => { this.onPrepared() })
    } else if (!this.hostEnabled) {
      // Immediate native content keeps the card readable and gives List its
      // real text height while scrolling. Rich styling is completed at rest.
      Text(ForumContentParser.summary(this.content)).fontSize(this.textSize).lineHeight(this.textSize + 7)
        .fontColor(ThemeColors.textPrimary).width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => { this.measuredHeight = Math.max(32, Number(size.height)) })
        .onVisibleAreaChange([0.01], (visible: boolean) => { this.visibilityChanged(visible) })
        .hitTestBehavior(HitTestMode.None)
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        // The Web stays visible and sized throughout startup so ArkWeb can
        // paint and report real DOM/font geometry; only the hint overlays it.
        // Short, clamped previews use the platform's asynchronous surface.
        // Long full floors retain synchronous tiling: API 26 asynchronous Web
        // surfaces cannot exceed 7680 physical pixels in either dimension.
        Web({ src: $rawfile('forum-rich/index.html'), controller: this.controller,
          renderMode: this.preview ? RenderMode.ASYNC_RENDER : RenderMode.SYNC_RENDER })
          .javaScriptAccess(true).domStorageAccess(false)
          // ArkWeb's image gate also affects bundled data images. The page
          // CSP allows only data: images and disallows every network request.
          .fileAccess(false).onlineImageAccess(true).zoomAccess(false)
          .backgroundColor(Color.Transparent)
          .javaScriptProxy({ object: this.bridge, name: 'ForumBridge', methodList: ['layout', 'link'], controller: this.controller })
          .onPageEnd(() => { this.pageEnded() })
          .onLoadIntercept((event) => {
            const address: string = event.data.getRequestUrl()
            return event.data.isMainFrame() && !address.startsWith('resource://') && !address.startsWith('file:///data/storage/')
          })
          .onErrorReceive((event) => { this.receiveError(event.request.isMainFrame()) })
          // Feed/quote thumbnails are display content inside a native card.
          // A starting Web host must not take the next pan (or keyboard focus)
          // from List; the card still opens the complete post on a native tap.
          // Full floor content keeps its links and nested-scroll interaction.
          .hitTestBehavior(this.preview ? HitTestMode.None : HitTestMode.Default)
          .focusable(!this.preview)
          .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.PARENT_FIRST })
          .width('100%').height(this.measuredHeight)
          .opacity(this.preview ? this.richOpacity : 1)
        if (this.preview) {
          Text(ForumContentParser.summary(this.content)).fontSize(this.textSize).lineHeight(this.textSize + 7)
            .fontColor(ThemeColors.textPrimary).width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
            .opacity(1 - this.richOpacity)
            .hitTestBehavior(HitTestMode.None).accessibilityLevel(this.firstLayoutReceived ? 'no-hide-descendants' : 'auto')
        } else if (!this.firstLayoutReceived) {
          // Full Markdown/TeX must remain readable even if ArkWeb has not
          // completed its first layout. Plain URL prose uses native spans and
          // never enters this host in the first place.
          Column() {
            ForEach(ForumContentParser.textBlocks(ForumContentParser.summary(this.content)), (block: string) => {
              Text(block).fontSize(this.textSize).lineHeight(this.textSize + 10).fontColor(ThemeColors.textPrimary).width('100%')
            })
          }.width('100%').alignItems(HorizontalAlign.Start).hitTestBehavior(HitTestMode.None)
            .accessibilityLevel('auto')
        }
      }.width('100%').height(this.firstLayoutReceived ? this.measuredHeight : undefined)
    }
  }
}
