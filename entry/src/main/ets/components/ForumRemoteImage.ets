import { DiagnosticLink } from './ErrorNotice'
import { common } from '@kit.AbilityKit'
import { ForumImageCache } from '../util/ForumImageCache'
import { AppLanguage } from '../common/AppLanguage'
import { ThemeColors } from '../common/Theme'
import { ForumImage } from '../model/ForumImage'
import { HttpError } from '../util/HttpUtil'
import { promptAction } from '@kit.ArkUI'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { ImageOpening } from '../common/RouteParams'
import { ForumImageTransition } from '../common/ForumImageTransition'

/** Non-sticker floor image: finite network state, cached preview, explicit retry. */
@Component
export struct ForumRemoteImage {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @Prop @Watch('reload') source: string = ''
  @Prop label: string = ''
  @Prop preview: boolean = false
  @Prop coordinatedPreview: boolean = false
  onPrepared: () => void = () => {}
  @Prop allowOpen: boolean = true
  onOpen: (opening: ImageOpening | undefined) => void = () => {}
  @State private displayed: string = ''
  @State private failed: boolean = false
  @State private errorDetails: string = ''
  @State private loading: boolean = true
  @State private previewOpacity: number = 0
  private active: boolean = false
  @State private version: number = 0
  private load: ForumImageCache | null = null
  private displayedSource: string = ''
  private requestedSource: string = ''
  private transitionId: string = ForumImageTransition.nextId()
  @State private nativeWidth: number = 0
  @State private nativeHeight: number = 0
  @State private availableWidth: number = 0

  aboutToAppear(): void { this.active = true; this.reload() }
  aboutToDisappear(): void {
    this.active = false; this.version++; this.load?.cancel(); this.load = null
    ForumImageTransition.forget(this.transitionId)
  }

  private async reload(): Promise<void> {
    if (this.active && this.load !== null && this.requestedSource === this.source) return
    this.load?.cancel()
    if (!this.active) return
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    ForumImageCache.restore(context.cacheDir)
    const preview: string = ForumImage.preview(this.source)
    this.displayed = ForumImageCache.cached(preview)
    this.displayedSource = preview
    if (!this.displayed && preview !== this.source) {
      this.displayed = ForumImageCache.cached(this.source)
      this.displayedSource = this.source
    }
    this.failed = false
    this.previewOpacity = 0
    this.nativeWidth = 0; this.nativeHeight = 0
    this.errorDetails = ''
    this.loading = !this.displayed
    const version: number = ++this.version
    if (!this.active || this.displayed) return
    const job = new ForumImageCache()
    this.requestedSource = this.source
    this.load = job
    try {
      let used: string = preview
      let displayed: string = ''
      try { displayed = await job.load(preview, context.cacheDir) }
      catch (e) {
        // A guessed preview can be absent on older images. Fall back only for
        // a missing rendition, never replay rejected TLS/auth/server errors.
        if (preview === this.source || !(e instanceof HttpError) || e.statusCode !== 404 ||
          !this.active || version !== this.version) throw e as Error
        const original = new ForumImageCache()
        this.load = original
        displayed = await original.load(this.source, context.cacheDir)
        used = this.source
      }
      if (this.active && version === this.version) { this.displayed = displayed; this.displayedSource = used }
    } catch (e) {
      if (this.active && version === this.version) {
        this.failed = true; this.errorDetails = ErrorDiagnostics.detail(e as Object); this.onPrepared()
      }
    } finally {
      if (this.active && version === this.version) { this.loading = false; this.load = null }
    }
  }

  private imageWidth(): number | string {
    return this.nativeWidth > 1 && this.nativeHeight > 1 && this.availableWidth > 0 ?
      Math.min(this.availableWidth, 220 * this.nativeWidth / this.nativeHeight) : '100%'
  }
  private imageHeight(): number | string {
    return this.nativeWidth > 1 && this.nativeHeight > 1 && this.availableWidth > 0 ?
      Math.min(220, this.availableWidth * this.nativeHeight / this.nativeWidth) : '100%'
  }

  build() {
    Stack() {
      if (this.displayed) {
        ForEach([this.version], (version: number) => {
        ForEach([this.displayed], (address: string) => {
          Image(address).width(this.imageWidth()).height(this.imageHeight()).objectFit(ImageFit.Contain).autoResize(false)
            .opacity(this.preview ? this.previewOpacity : 1)
            .sharedTransition(this.transitionId, { duration: 360, curve: Curve.Friction, zIndex: 10 })
            .accessibilityText(this.label)
            .onComplete((event) => {
              if (!event || event.loadingStatus !== 1 || !this.active || version !== this.version || this.displayed !== address) return
              this.nativeWidth = event.width; this.nativeHeight = event.height
              if (this.preview && this.coordinatedPreview) this.previewOpacity = 1
              else if (this.preview) this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.previewOpacity = 1 })
              this.onPrepared()
              ForumImageTransition.remember(this.source,
                new ImageOpening(this.transitionId, address, event.width, event.height))
            })
            .onError((error: ImageError) => {
              if (!this.active || version !== this.version || this.displayed !== address) return
              ForumImageCache.forget(this.displayedSource, address)
              this.displayed = ''
              this.failed = true
              this.errorDetails = ErrorDiagnostics.detail(error?.error ?? new Error(error?.message || 'Image decode failed'))
              this.loading = false
              this.onPrepared()
            })
            .hitTestBehavior(this.allowOpen ? HitTestMode.Default : HitTestMode.None)
        }, (address: string) => address)
        }, (version: number) => String(version))
      }
      if (this.failed) {
        Column({ space: 10 }) {
          Text(AppLanguage.text($r('app.string.ui_could_not_load_image'), this.languageRevision))
            .fontSize(13).fontColor(ThemeColors.textSecondary)
            .hitTestBehavior(HitTestMode.None)
          Button(AppLanguage.text($r('app.string.ui_retry'), this.languageRevision))
            .fontSize(13).fontColor(ThemeColors.primary).backgroundColor(Color.Transparent)
            .onTouch((event: TouchEvent) => { event.stopPropagation() })
            .stateEffect(false).hoverEffect(HoverEffect.None).onClick(() => { this.reload() })
          DiagnosticLink({ message: this.errorDetails, summary: AppLanguage.text($r('app.string.ui_could_not_load_image'), this.languageRevision), color: ThemeColors.primary, controlId: 'remote-image-diagnostics' })
        }.padding(16)
      } else if (this.loading || (this.preview && this.previewOpacity < 1)) {
        LoadingProgress().width(28).height(28).color(ThemeColors.primary)
          .hitTestBehavior(HitTestMode.None)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }.width('100%').height(220).borderRadius(12).clip(true)
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => {
        const width: number = Number(size.width)
        if (Number.isFinite(width) && width > 0 && width !== this.availableWidth) this.availableWidth = width
      })
      .backgroundColor($r('app.color.surface_fallback'))
      .hitTestBehavior(this.allowOpen ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (!this.allowOpen) return
        const opening: ImageOpening | undefined = this.displayed && this.nativeWidth > 1 && this.nativeHeight > 1 ?
          new ImageOpening(this.transitionId, this.displayed, this.nativeWidth, this.nativeHeight) : undefined
        this.onOpen(opening)
      })
  }
}
