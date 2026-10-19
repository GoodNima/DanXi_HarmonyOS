import { DiagnosticNavigation } from '../common/DiagnosticNavigation'
import { DiagnosticLink } from '../components/ErrorNotice'
import { AppLanguage } from '../common/AppLanguage'
import { Appearance } from '../common/Appearance'
import { router, promptAction, AnimatorResult, matrix4 } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { ImageRouteParams, ImageOpening, ImageReturnTarget } from '../common/RouteParams'
import { ForumImageTransition, ForumImageController } from '../common/ForumImageTransition'
import { Constant } from '../common/Constant'
import { ForumImage, ForumImagePose, ForumImageFrame } from '../model/ForumImage'
import { OriginalImageDownload } from '../util/OriginalImageDownload'
import { GalleryImageSave } from '../util/GalleryImageSave'
import { BrowserLink } from '../common/BrowserLink'
import { FloatingSurface } from '../components/FloatingSurface'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { GallerySaveControl } from '../components/GallerySaveControl'
import { ForumImageCache } from '../util/ForumImageCache'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'

/** Gallery ordering and gesture rules are independent of the image loader. */
export class ForumImageGallery {
  sources: string[] = []
  previews: string[] = []
  selected: number = 0

  constructor(source: string, sources: string[] = []) {
    const selected: string = ForumImageGallery.normalize(source)
    for (const candidate of sources) {
      const normalized: string = ForumImageGallery.normalize(candidate)
      const preview: string = typeof candidate === 'string' ? ForumImage.preview(BrowserLink.normalize(candidate)) : ''
      const existing: number = this.sources.indexOf(normalized)
      if (normalized && existing < 0) { this.sources.push(normalized); this.previews.push(preview) }
      else if (normalized && preview !== normalized && this.previews[existing] === normalized) this.previews[existing] = preview
    }
    if (selected && !this.sources.includes(selected)) {
      this.sources.unshift(selected)
      this.previews.unshift(ForumImage.preview(BrowserLink.normalize(source)))
    }
    this.selected = Math.max(0, this.sources.indexOf(selected))
    if (selected && typeof source === 'string') this.previews[this.selected] = ForumImage.preview(BrowserLink.normalize(source))
  }

  static normalize(source: string): string {
    if (typeof source !== 'string') return ''
    const address: string = BrowserLink.normalize(source)
    return address ? ForumImage.original(address) : ''
  }

  static canSwitch(zoom: number, saving: boolean, index: number, count: number): boolean {
    return Number.isFinite(zoom) && !saving && Number.isInteger(index) && index >= 0 && index < count
  }
}

@Component
export struct ForumImageView {
  controller: ForumImageController | undefined = undefined
  @Prop initialSource: string = ''
  @Prop initialSources: string[] = []
  @Prop initialPreviews: string[] = []
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @State source: string = ''
  @State gallery: string[] = []
  private previews: string[] = []
  @State imageIndex: number = 0
  @State failed: boolean = false
  @State private errorDetails: string = ''
  @State imageLoading: boolean = true
  @State saving: boolean = false
  private zoomScale: number = 1
  private offsetX: number = 0
  private offsetY: number = 0
  @State private pose: ForumImagePose = new ForumImagePose()
  @State retryVersion: number = 0
  @State displayed: string = ''
  // Two image layers retain the visible frame. A changed URI creates a fresh
  // hidden decoder, so its old bitmap and callbacks cannot reveal stale pixels.
  @State private frameA: string = ''
  @State private frameB: string = ''
  @State private alphaA: number = 0
  @State private alphaB: number = 0
  @State private frontSlot: number = -1
  @State private stageSlot: number = 0
  private readyA: string = ''
  private readyB: string = ''
  @State private widthA: number = 1
  @State private heightA: number = 1
  @State private widthB: number = 1
  @State private heightB: number = 1
  @State private ownerA: number = -1
  @State private ownerB: number = -1
  @State private frozenScaleA: number = 1
  @State private frozenScaleB: number = 1
  @State private frozenXA: number = 0
  @State private frozenYA: number = 0
  @State private frozenXB: number = 0
  @State private frozenYB: number = 0
  @State private frozenPoseA: ForumImagePose = new ForumImagePose()
  @State private frozenPoseB: ForumImagePose = new ForumImagePose()
  private transitioning: boolean = false
  private animationEpoch: number = 0
  private queuedAddress: string = ''
  private queuedOriginal: boolean = false
  private readyTimer: number = -1
  @State originalLoading: boolean = false
  @State originalFailed: boolean = false
  private displayedOriginal: boolean = false
  private previewPending: boolean = false
  private originalLoad: ForumImageCache | null = null
  private previewLoad: ForumImageCache | null = null
  @State private viewWidth: number = 1
  @State private viewHeight: number = 1
  private imageWidth: number = 1
  private imageHeight: number = 1
  private startScale: number = 1
  private startX: number = 0
  private startY: number = 0
  private pinchInProgress: boolean = false
  @State private controlsVisible: boolean = false
  @State private controlsOpacity: number = 0
  private controlsTopPx: number = 0
  private motion: AnimatorResult | null = null
  private zooming: boolean = false
  private motionEpoch: number = 0
  private pinchAnchorX: number = 0
  private pinchAnchorY: number = 0
  private panSuppressed: boolean = false
  private panInProgress: boolean = false
  private touchSequence: number = 0
  private lastZoomSequence: number = -1
  private lastZoomTimestamp: number = -1
  private active: boolean = true
  private framingStarted: boolean = false
  private opening: ImageOpening | undefined = undefined
  private openingSource: string = ''
  private returnTargets: ImageReturnTarget[] = []
  private openingHeld: boolean = false
  @State private sharedEntryActive: boolean = false
  private unsharedId: string = 'gallery-unpaired-' + ForumImageTransition.nextId()
  @State private returnFrame: ForumImageFrame | undefined = undefined
  private leaving: boolean = false
  private download: OriginalImageDownload = new OriginalImageDownload()

  aboutToAppear(): void {
    this.active = true
    this.controller?.bind(() => { this.closeGallery() }, () => { this.finishOpening() })
    this.controlsTopPx = this.topPx
    Appearance.setBarAppearance('dark')
    this.controlsVisible = false; this.controlsOpacity = 0
    Appearance.setStatusBarVisible(false).catch(() => {})
    const params = this.initialSource ? new ImageRouteParams(this.initialSource, this.initialSources) :
      router.getParams() as ImageRouteParams
    const gallery = new ForumImageGallery(params?.source ?? '', Array.isArray(params?.sources) ? params.sources : [])
    this.opening = ImageOpening.valid(params?.opening) ? params.opening : undefined
    this.openingSource = ForumImageGallery.normalize(params?.source ?? '')
    this.returnTargets = Array.isArray(params?.targets) ? params.targets.slice() : []
    if (this.opening !== undefined) this.returnTargets.unshift(new ImageReturnTarget(this.openingSource, this.opening))
    const size: SizeOptions = Appearance.windowSize()
    if (Number(size.width) > 0 && Number(size.height) > 0) {
      this.viewWidth = px2vp(Number(size.width)); this.viewHeight = px2vp(Number(size.height))
    }
    this.gallery = gallery.sources
    this.previews = gallery.previews.map((preview: string, index: number): string =>
      BrowserLink.normalize(this.initialPreviews[index] ?? '') || preview)
    this.openImage(gallery.selected)
  }

  aboutToDisappear(): void {
    Appearance.setBarAppearance('')
    Appearance.setStatusBarVisible(true).catch(() => {})
    this.active = false
    this.controller?.release()
    this.stopMotion()
    this.retryVersion++
    this.animationEpoch++
    this.queuedAddress = ''
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer)
    this.readyTimer = -1
    this.originalLoad?.cancel()
    this.previewLoad?.cancel()
    this.download.cancel()
  }

  private constrainPan(x: number, y: number): void {
    const maxX = ForumImage.panLimit(this.viewWidth, this.viewHeight, this.imageWidth, this.imageHeight, this.zoomScale, true)
    this.offsetX = Math.max(-maxX, Math.min(maxX, x)) || 0
    this.offsetY = ForumImage.constrainY(y, this.viewWidth, this.viewHeight, this.imageWidth, this.imageHeight, this.zoomScale) || 0
    this.pose = new ForumImagePose(this.zoomScale, this.offsetX, this.offsetY)
  }

  private resetFraming(): void {
    this.constrainPan(0, ForumImage.topOffset(this.viewWidth, this.viewHeight, this.imageWidth, this.imageHeight))
  }

  private primeOpening(): void {
    const opening: ImageOpening | undefined = this.opening
    if (opening === undefined || this.source !== this.openingSource || this.frontSlot >= 0) return
    // Reuse the decoded thumbnail in the very first destination layout. Waiting
    // for a download/decode here would leave no matching shared element.
    this.imageWidth = opening.width; this.imageHeight = opening.height
    this.widthA = opening.width; this.heightA = opening.height
    this.frameA = opening.thumbnail; this.readyA = opening.thumbnail
    this.displayed = opening.thumbnail; this.alphaA = 1
    this.frontSlot = 0; this.stageSlot = 0; this.ownerA = this.imageIndex
    this.imageLoading = false
    this.resetFraming()
    this.openingHeld = true
    this.sharedEntryActive = true
    // Completion comes from the route's native animation, not a wall-clock
    // timer started before the first layout. Slow first frames cannot release
    // the thumbnail or enable gestures while the shared flight still owns it.
  }

  private finishOpening(): void {
    if (!this.active || this.leaving || !this.openingHeld) return
    this.getUIContext().postFrameCallback({ onFrame: () => {
      if (!this.active || this.leaving) return
      this.openingHeld = false; this.sharedEntryActive = false
      this.drainQueuedImage()
    }, onIdle: () => {} })
  }

  private sharedFrameId(slot: number): string {
    if (this.returnFrame !== undefined && this.returnFrame.slot === slot) return this.returnFrame.id
    if (this.sharedEntryActive && !this.leaving && this.opening !== undefined &&
      this.source === this.openingSource && slot === this.stageSlot) return this.opening.id
    // An empty shared ID is ignored by the native bridge. Detach explicitly
    // until a deliberate return pairs the visible image with its source.
    return this.unsharedId + '-' + slot
  }

  private openImage(index: number): void {
    this.stopMotion()
    this.freezeTransforms()
    this.originalLoad?.cancel()
    this.previewLoad?.cancel()
    this.clearPendingReveal()
    this.imageIndex = index
    this.source = this.gallery[index] ?? ''
    this.zoomScale = 1
    this.startScale = 1
    this.offsetX = 0
    this.offsetY = 0
    this.startX = 0
    this.startY = 0
    this.imageWidth = 1
    this.imageHeight = 1
    this.framingStarted = false
    this.pose = new ForumImagePose()
    this.pinchInProgress = false
    this.panSuppressed = false
    this.panInProgress = false
    this.failed = !this.source
    this.errorDetails = this.source ? '' : 'Error: Invalid image URL'
    this.imageLoading = !!this.source
    this.retryVersion++
    this.displayed = ''
    this.displayedOriginal = false
    this.previewPending = false
    this.originalFailed = false
    this.originalLoading = false
    this.primeOpening()
    if (this.source) this.loadImage(this.retryVersion)
  }

  private async loadImage(version: number): Promise<void> {
    const source: string = this.source
    const preview: string = this.previews[this.imageIndex] ?? source
    const original: string = ForumImageCache.cached(source)
    if (original) { this.presentImage(original, true); this.imageLoading = false; return }
    const cachedPreview: string = ForumImageCache.cached(preview)
    if (cachedPreview) { this.presentImage(cachedPreview, false); this.imageLoading = false }
    this.originalLoading = true
    if (preview !== source && !cachedPreview) {
      this.previewPending = true
      this.loadPreview(version, preview)
    }
    const job = new ForumImageCache()
    this.originalLoad = job
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const result: string = await job.load(source, context.cacheDir)
      if (!this.active || version !== this.retryVersion) return
      this.presentImage(result, true)
      this.imageLoading = false
    } catch (e) {
      if (this.active && version === this.retryVersion) { this.originalFailed = true; this.errorDetails = ErrorDiagnostics.detail(e as Object) }
    } finally {
      if (this.active && version === this.retryVersion) {
        this.originalLoading = false
        this.originalLoad = null
        this.failed = !this.displayed && !this.queuedAddress && !this.previewPending
        this.imageLoading = !this.displayed && !this.queuedAddress && this.previewPending
      }
    }
  }

  private async loadPreview(version: number, source: string): Promise<void> {
    const job = new ForumImageCache()
    this.previewLoad = job
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const result: string = await job.load(source, context.cacheDir)
      if (!this.active || version !== this.retryVersion || this.displayedOriginal) return
      this.presentImage(result, false)
      this.imageLoading = false
    } catch (e) {} finally {
      if (this.active && version === this.retryVersion) {
        this.previewPending = false
        this.previewLoad = null
        this.failed = !this.displayed && !this.queuedAddress && !this.originalLoading
        this.imageLoading = !this.displayed && !this.queuedAddress && this.originalLoading
      }
    }
  }

  private retryImage(): void {
    this.clearPendingReveal()
    this.originalLoad?.cancel()
    this.previewLoad?.cancel()
    this.failed = false
    this.imageLoading = !this.displayed
    this.originalFailed = false
    this.loadImage(++this.retryVersion)
  }

  private presentImage(address: string, original: boolean): void {
    if (this.leaving) return
    this.failed = false
    if (this.transitioning || this.openingHeld || this.motion !== null || this.pinchInProgress || this.panInProgress) {
      // A late thumbnail must not downgrade an original that is already
      // waiting for the visible transition to finish.
      if (!original && this.queuedAddress && this.queuedOriginal) return
      this.queuedAddress = address; this.queuedOriginal = original
      return
    }
    this.displayedOriginal = original
    this.displayed = address
    if (this.frontSlot >= 0 && address === this.frameAddress(this.frontSlot)) {
      this.stageSlot = this.frontSlot
      if (this.frontSlot === 0) this.ownerA = this.imageIndex; else this.ownerB = this.imageIndex
      this.imageWidth = this.frontSlot === 0 ? this.widthA : this.widthB
      this.imageHeight = this.frontSlot === 0 ? this.heightA : this.heightB
      if (!this.framingStarted) this.resetFraming()
      this.imageLoading = false
      return
    }
    this.stageSlot = this.frontSlot === 0 ? 1 : 0
    const unchanged: boolean = this.frameAddress(this.stageSlot) === address
    if (this.stageSlot === 0) { this.alphaA = 0; this.ownerA = this.imageIndex; this.frameA = address }
    else { this.alphaB = 0; this.ownerB = this.imageIndex; this.frameB = address }
    // A previously decoded, hidden slot can be reused without waiting for an
    // onComplete event which native Image does not repeat for an unchanged URI.
    if (unchanged && ((this.stageSlot === 0 && this.readyA === address) || (this.stageSlot === 1 && this.readyB === address))) {
      this.scheduleReady(address, this.retryVersion, this.stageSlot === 0 ? this.widthA : this.widthB,
        this.stageSlot === 0 ? this.heightA : this.heightB)
    }
  }

  private frameAddress(slot: number): string { return slot === 0 ? this.frameA : this.frameB }

  private scheduleReady(address: string, version: number, width: number, height: number): void {
    // Native onComplete can run before its source/opacity update has committed,
    // particularly for a memory-cache hit. Defer every reveal, not just reuse.
    const slot: number = this.stageSlot
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer)
    this.readyTimer = setTimeout(() => {
      this.readyTimer = -1
      if (slot === this.stageSlot) this.imageReady(address, version, width, height)
    }, 32)
  }

  private frameReady(slot: number, address: string, version: number, width: number, height: number): void {
    if (!this.active || this.leaving || !address || address !== this.frameAddress(slot)) return
    // The displayed decoder's geometry is immutable. Repeat notifications
    // must not reframe an image while its gesture transform is in flight.
    if (slot === this.frontSlot && address === (slot === 0 ? this.readyA : this.readyB)) return
    // A superseded decode may finish in a hidden slot. Remember its decoded
    // dimensions for reuse, but never reveal it for a different navigation.
    if (slot === 0) { this.readyA = address; this.widthA = width; this.heightA = height }
    else { this.readyB = address; this.widthB = width; this.heightB = height }
    if (slot === this.stageSlot && version === this.retryVersion && address === this.displayed &&
      !this.transitioning && slot !== this.frontSlot) this.scheduleReady(address, version, width, height)
  }

  private clearPendingReveal(): void {
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer)
    this.readyTimer = -1
    this.queuedAddress = ''
    this.queuedOriginal = false
    // Navigation invalidates pending decode/reveal work, but lets an already
    // visible fade finish. Forcing its endpoint makes rapid switching jump.
  }

  private imageReady(address: string, version: number, width: number, height: number): void {
    if (!address || !this.active || version !== this.retryVersion || address !== this.displayed || this.transitioning ||
      address !== this.frameAddress(this.stageSlot)) return
    if (this.frontSlot === this.stageSlot) return
    if (this.motion !== null || this.pinchInProgress || this.panInProgress) {
      this.queuedAddress = address; this.queuedOriginal = this.displayedOriginal
      return
    }
    if (this.stageSlot === 0) { this.readyA = address; this.widthA = width; this.heightA = height }
    else { this.readyB = address; this.widthB = width; this.heightB = height }
    this.imageLoading = false
    this.imageWidth = width; this.imageHeight = height
    if (!this.framingStarted) this.resetFraming()
    this.constrainPan(this.offsetX, this.offsetY)
    this.transitioning = true
    const epoch: number = ++this.animationEpoch
    const slot: number = this.stageSlot
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut, onFinish: () => {
      if (!this.active || this.leaving || epoch !== this.animationEpoch || !this.transitioning) return
      this.frontSlot = slot
      // The incoming plane includes the viewport backing, so different image
      // aspect ratios and transparent pixels do not expose the retired underlay.
      if (slot === 0) this.alphaB = 0; else this.alphaA = 0
      this.transitioning = false
      this.drainQueuedImage()
    } }, () => {
      if (slot === 0) this.alphaA = 1; else this.alphaB = 1
    })
  }

  private decodeFailed(address: string, version: number, error?: ImageError): void {
    if (!address || !this.active || version !== this.retryVersion || this.displayed !== address) return
    this.errorDetails = ErrorDiagnostics.detail(error?.error ?? new Error(error?.message || 'Image decode failed'))
    const url: string = this.displayedOriginal ? this.source : (this.previews[this.imageIndex] ?? this.source)
    ForumImageCache.forget(url, address)
    const preview: string = this.previews[this.imageIndex] ?? this.source
    const fallback: string = this.displayedOriginal && preview !== this.source ? ForumImageCache.cached(preview) : ''
    if (this.displayedOriginal) this.originalFailed = true
    if (this.stageSlot === 0) { this.alphaA = 0; this.readyA = ''; this.frameA = '' }
    else { this.alphaB = 0; this.readyB = ''; this.frameB = '' }
    this.displayed = ''; this.displayedOriginal = false
    if (fallback) this.presentImage(fallback, false)
    this.imageLoading = !fallback && (this.originalLoading || this.previewPending)
    this.failed = !fallback && !this.imageLoading
  }

  private switchImage(direction: number): void {
    if (direction !== 1 && direction !== -1) return
    const next: number = this.imageIndex + direction
    if (!this.active || !ForumImageGallery.canSwitch(this.zoomScale, this.saving, next, this.gallery.length)) return
    this.openImage(next)
  }

  private finishPan(event: GestureEvent): void {
    if (!this.panInProgress || this.openingHeld || this.leaving) return
    this.panInProgress = false
    if (this.pinchInProgress || this.panSuppressed || !this.active) { this.panSuppressed = false; return }
    this.stopMotion()
    const x: number = this.offsetX; const y: number = this.offsetY
    const duration: number = ForumImage.inertiaDuration(event.velocityX, event.velocityY)
    if (duration === 0) { this.drainQueuedImage(); return }
    // Animate only image transforms; layout and network stay idle.
    const epoch: number = this.motionEpoch
    const motion = this.getUIContext().createAnimator({ duration, easing: 'linear', delay: 0,
      fill: 'forwards', direction: 'normal', iterations: 1, begin: 0, end: 1 })
    this.motion = motion
    motion.onFrame = (progress: number) => {
      if (!this.active || epoch !== this.motionEpoch) return
      this.constrainPan(x + ForumImage.inertiaDistance(event.velocityX, progress, duration),
        y + ForumImage.inertiaDistance(event.velocityY, progress, duration))
    }
    motion.onFinish = () => { this.finishMotion(epoch) }
    motion.play()
  }

  private stopMotion(): void {
    this.motionEpoch++
    const motion = this.motion
    this.motion = null
    this.zooming = false
    motion?.cancel()
  }

  private finishMotion(epoch: number): void {
    if (!this.active || epoch !== this.motionEpoch) return
    this.motion = null
    this.zooming = false
    this.drainQueuedImage()
  }

  private drainQueuedImage(): void {
    if (!this.active || this.leaving || this.openingHeld || this.transitioning || this.motion !== null ||
      this.pinchInProgress || this.panInProgress) return
    const address: string = this.queuedAddress; const original: boolean = this.queuedOriginal
    this.queuedAddress = ''; this.queuedOriginal = false
    if (address) this.presentImage(address, original)
  }

  private touchImage(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.touchSequence++
      // A tap stops inertia, but must not cancel a zoom on its first contact.
      // Actual pan/pinch recognition can still take over from the current pose.
      if (!this.zooming) this.stopMotion()
    }
  }

  private toggleControls(): void {
    if (!this.active) return
    // The first safe inset may arrive after aboutToAppear on a cold launch.
    // Retain it before hiding the system bar so the fading buttons stay still.
    this.controlsTopPx = Math.max(this.controlsTopPx, this.topPx)
    this.controlsVisible = !this.controlsVisible
    Appearance.setStatusBarVisible(this.controlsVisible).catch(() => {})
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.controlsOpacity = this.controlsVisible ? 1 : 0
    })
    this.drainQueuedImage()
  }

  private zoomAt(event: GestureEvent): void {
    if (!this.active || this.leaving || this.pinchInProgress || event.fingerList.length > 1 || this.imageWidth <= 1 || this.openingHeld) return
    if ((this.touchSequence > 0 && this.lastZoomSequence === this.touchSequence) ||
      (Number.isFinite(event.timestamp) && this.lastZoomTimestamp === event.timestamp)) return
    this.lastZoomSequence = this.touchSequence
    this.lastZoomTimestamp = event.timestamp
    this.stopMotion()
    this.framingStarted = true
    const from: number = this.zoomScale; const to: number = from > 1.05 ? 1 : 3
    const x: number = this.offsetX; const y: number = this.offsetY
    const touch: FingerInfo | undefined = event.fingerList[0]
    const anchorX: number = (touch?.localX ?? this.viewWidth / 2) - this.viewWidth / 2
    const anchorY: number = (touch?.localY ?? this.viewHeight / 2) - this.viewHeight / 2
    const maxX: number = ForumImage.panLimit(this.viewWidth, this.viewHeight, this.imageWidth, this.imageHeight, to, true)
    const targetX: number = to === 1 ? 0 : Math.max(-maxX, Math.min(maxX, anchorX + (x - anchorX) * to / from))
    const targetY: number = to === 1 ? ForumImage.topOffset(this.viewWidth, this.viewHeight, this.imageWidth, this.imageHeight) :
      ForumImage.constrainY(anchorY + (y - anchorY) * to / from,
        this.viewWidth, this.viewHeight, this.imageWidth, this.imageHeight, to)
    const epoch: number = this.motionEpoch
    const motion = this.getUIContext().createAnimator({ duration: 280, easing: 'cubic-bezier(0.2,0,0.2,1)',
      delay: 0, fill: 'forwards', direction: 'normal', iterations: 1, begin: 0, end: 1 })
    this.motion = motion
    this.zooming = true
    motion.onFrame = (progress: number) => {
      if (!this.active || epoch !== this.motionEpoch) return
      this.zoomScale = from + (to - from) * progress
      // Both endpoints are bounded. Clamping each intermediate frame makes
      // short images move in two phases when they cross the viewport height.
      this.offsetX = x + (targetX - x) * progress
      this.offsetY = y + (targetY - y) * progress
      this.pose = new ForumImagePose(this.zoomScale, this.offsetX, this.offsetY)
    }
    motion.onFinish = () => { this.finishMotion(epoch) }
    motion.play()
  }

  private startPinch(event: GestureEvent): void {
    if (this.openingHeld || this.leaving) return
    this.stopMotion()
    this.framingStarted = true
    this.pinchInProgress = true
    this.panSuppressed = true
    this.startScale = this.zoomScale
    this.startX = this.offsetX; this.startY = this.offsetY
    this.pinchAnchorX = (Number.isFinite(event.pinchCenterX) ? event.pinchCenterX : this.viewWidth / 2) - this.viewWidth / 2
    this.pinchAnchorY = (Number.isFinite(event.pinchCenterY) ? event.pinchCenterY : this.viewHeight / 2) - this.viewHeight / 2
  }

  private updatePinch(event: GestureEvent): void {
    if (!this.pinchInProgress || this.leaving) return
    this.zoomScale = ForumImage.clampScale(this.startScale * event.scale)
    const ratio: number = this.zoomScale / this.startScale
    this.constrainPan(this.pinchAnchorX + (this.startX - this.pinchAnchorX) * ratio,
      this.pinchAnchorY + (this.startY - this.pinchAnchorY) * ratio)
  }

  private startPan(): void {
    if (this.openingHeld || this.leaving) return
    this.stopMotion()
    this.framingStarted = true
    this.panInProgress = true
    this.panSuppressed = this.pinchInProgress
    this.startX = this.offsetX; this.startY = this.offsetY
  }

  private updatePan(event: GestureEvent): void {
    if (this.panInProgress && !this.leaving && !this.pinchInProgress && !this.panSuppressed) this.constrainPan(this.startX + event.offsetX, this.startY + event.offsetY)
  }

  private frameHeight(slot: number): number {
    if (this.returnFrame !== undefined && this.returnFrame.slot === slot) return this.returnFrame.height
    const width: number = slot === 0 ? this.widthA : this.widthB
    const height: number = slot === 0 ? this.heightA : this.heightB
    return width > 1 && height > 1 ? this.viewWidth * height / width : this.viewHeight
  }

  private frameWidth(slot: number): Length {
    if (this.returnFrame !== undefined && this.returnFrame.slot === slot) return this.returnFrame.width
    return '100%'
  }

  private framePosition(slot: number): Position | undefined {
    if (this.returnFrame !== undefined && this.returnFrame.slot === slot) return { x: this.returnFrame.x, y: this.returnFrame.y }
    // Center short images in layout, so the entry transition ends at their
    // actual visible bounds with no corrective translation on the next frame.
    return { x: 0, y: Math.max(0, (this.viewHeight - this.frameHeight(slot)) / 2) }
  }

  private freezeTransforms(): void {
    if (this.ownerA === this.imageIndex) {
      this.frozenScaleA = this.zoomScale; this.frozenXA = this.offsetX; this.frozenYA = this.offsetY
      this.frozenPoseA = new ForumImagePose(this.zoomScale, this.offsetX, this.offsetY)
    }
    if (this.ownerB === this.imageIndex) {
      this.frozenScaleB = this.zoomScale; this.frozenXB = this.offsetX; this.frozenYB = this.offsetY
      this.frozenPoseB = new ForumImagePose(this.zoomScale, this.offsetX, this.offsetY)
    }
  }

  private frameTransform(slot: number): matrix4.Matrix4Transit {
    if (this.returnFrame !== undefined && this.returnFrame.slot === slot) return matrix4.identity()
    const owned: boolean = (slot === 0 ? this.ownerA : this.ownerB) === this.imageIndex
    const pose: ForumImagePose = owned ? this.pose : (slot === 0 ? this.frozenPoseA : this.frozenPoseB)
    const width: number = slot === 0 ? this.widthA : this.widthB
    const height: number = slot === 0 ? this.heightA : this.heightB
    // The native frame is centered for short images and top aligned for long
    // images. Both use an identity matrix at their default framing.
    const baseY: number = ForumImage.topOffset(this.viewWidth, this.viewHeight, width, height)
    return matrix4.init([pose.scale, 0, 0, 0, 0, pose.scale, 0, 0, 0, 0, 1, 0,
      vp2px(pose.x), vp2px(pose.y - baseY), 0, 1])
  }

  private closeGallery(): void {
    if (!this.active || this.leaving) return
    this.leaving = true
    this.stopMotion()
    this.retryVersion++
    this.clearPendingReveal()
    this.originalLoad?.cancel(); this.previewLoad?.cancel()
    this.sharedEntryActive = false
    const slot: number = this.frontSlot >= 0 ? this.frontSlot : this.stageSlot
    const owner: number = slot === 0 ? this.ownerA : this.ownerB
    const source: string = this.gallery[owner] ?? ''
    const target: ImageReturnTarget | undefined = this.returnTargets.find((item: ImageReturnTarget): boolean => item.source === source)
    if (target === undefined || !this.frameAddress(slot)) { router.back(); return }
    const pose: ForumImagePose = owner === this.imageIndex ? this.pose : (slot === 0 ? this.frozenPoseA : this.frozenPoseB)
    const width: number = this.viewWidth * pose.scale
    const height: number = this.frameHeight(slot) * pose.scale
    // Flatten the current child transform into equivalent parent bounds once,
    // before the native shared transition snapshots them. No reset-to-1 frame.
    this.returnFrame = new ForumImageFrame((this.viewWidth - width) / 2 + pose.x,
      (this.viewHeight - height) / 2 + pose.y, width, height, target.opening.id, slot)
    this.getUIContext().postFrameCallback({ onFrame: () => { if (this.active) router.back() }, onIdle: () => {} })
  }

  private updateViewport(size: SizeOptions): void {
    const width: number = Number(size.width); const height: number = Number(size.height)
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 ||
      (Math.abs(width - this.viewWidth) < 0.01 && Math.abs(height - this.viewHeight) < 0.01)) return
    this.stopMotion()
    this.viewWidth = width; this.viewHeight = height
    if (!this.framingStarted) this.resetFraming(); else this.constrainPan(this.offsetX, this.offsetY)
  }

  private finishPinch(): void { this.pinchInProgress = false; this.drainQueuedImage() }
  private cancelPan(): void { this.panInProgress = false; this.panSuppressed = false; this.drainQueuedImage() }

  private async saveOriginal(): Promise<void> {
    if (this.saving || !this.source) return
    // Keep the exact current image pose beneath the system permission dialog;
    // a fling/zoom must not continue behind it and jump on return.
    this.stopMotion()
    this.saving = true
    const source: string = this.source
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cache: string = context.cacheDir + '/danxi-original-' + Date.now()
    try {
      await this.download.download(source, cache)
      if (!this.active) return
      const saved: string = await GalleryImageSave.save(context, cache)
      if (!this.active || !saved) return
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_original_image_saved'), this.languageRevision) })
    } catch (e) {
      if (this.active) DiagnosticNavigation.feedback(this.getUIContext(), e as Object, AppLanguage.text($r('app.string.ui_could_not_save_check_your_connection_and_storage'), this.languageRevision))
    } finally {
      try { await fs.unlink(cache) } catch (e) {}
      if (this.active) this.saving = false
    }
  }

  @Builder
  GalleryControls() {
    Row({ space: 6 }) {
      Button(AppLanguage.text($r('app.string.detail_image_previous'), this.languageRevision))
        .id('gallery-previous')
        .fontSize(13).fontColor($r('app.color.gallery_foreground')).backgroundColor(Color.Transparent)
        .stateEffect(false).hoverEffect(HoverEffect.None).height('100%').padding({ left: 12, right: 12, top: 0, bottom: 0 })
        .enabled(ForumImageGallery.canSwitch(this.zoomScale, this.saving, this.imageIndex - 1, this.gallery.length))
        .onClick(() => { this.switchImage(-1) })
      Text(String(this.imageIndex + 1) + ' / ' + this.gallery.length).fontSize(13)
        .fontColor($r('app.color.gallery_foreground')).textAlign(TextAlign.Center).layoutWeight(1)
      Button(AppLanguage.text($r('app.string.detail_image_next'), this.languageRevision))
        .id('gallery-next')
        .fontSize(13).fontColor($r('app.color.gallery_foreground')).backgroundColor(Color.Transparent)
        .stateEffect(false).hoverEffect(HoverEffect.None).height('100%').padding({ left: 12, right: 12, top: 0, bottom: 0 })
        .enabled(ForumImageGallery.canSwitch(this.zoomScale, this.saving, this.imageIndex + 1, this.gallery.length))
        .onClick(() => { this.switchImage(1) })
    }.width('100%').height('100%').padding({ left: 4, right: 4 })
  }

  build() {
    WithTheme({ colorMode: ThemeColorMode.DARK }) {
    Stack() {
      Stack() {
        // The keyed URI is also the immutable callback address. Reading the
        // current frameA/frameB in a late completion mislabels the previous decode.
        ForEach(this.frameA ? [this.frameA] : [], (address: string) => {
        Stack({ alignContent: Alignment.Top }) {
        Stack() {
        Image(address).width('100%').height('100%').objectFit(ImageFit.Contain).autoResize(false)
          .id(this.stageSlot === 0 && this.displayed ? 'gallery-current-image' : 'gallery-retained-image')
          .renderGroup(true)
          .transform(this.frameTransform(0))
          .hitTestBehavior(HitTestMode.None)
          .onComplete((event) => { if (event?.loadingStatus === 1) this.frameReady(0, address, this.retryVersion, event.width, event.height) })
          .onError((error: ImageError) => { this.decodeFailed(address, this.retryVersion, error) })
        }.width(this.frameWidth(0)).height(this.frameHeight(0)).position(this.framePosition(0))
          .sharedTransition(this.sharedFrameId(0), { duration: 360, curve: Curve.Friction, zIndex: 10 })
          .hitTestBehavior(HitTestMode.None)
        }.width('100%').height('100%').backgroundColor($r('app.color.gallery_background'))
          .opacity(this.alphaA * (this.failed ? 0.2 : 1)).zIndex(this.stageSlot === 0 ? 1 : 0)
          .hitTestBehavior(HitTestMode.None)
        }, (address: string): string => address)
        ForEach(this.frameB ? [this.frameB] : [], (address: string) => {
        Stack({ alignContent: Alignment.Top }) {
        Stack() {
        Image(address).width('100%').height('100%').objectFit(ImageFit.Contain).autoResize(false)
          .id(this.stageSlot === 1 && this.displayed ? 'gallery-current-image' : 'gallery-retained-image')
          .renderGroup(true)
          .transform(this.frameTransform(1))
          .hitTestBehavior(HitTestMode.None)
          .onComplete((event) => { if (event?.loadingStatus === 1) this.frameReady(1, address, this.retryVersion, event.width, event.height) })
          .onError((error: ImageError) => { this.decodeFailed(address, this.retryVersion, error) })
        }.width(this.frameWidth(1)).height(this.frameHeight(1)).position(this.framePosition(1))
          .sharedTransition(this.sharedFrameId(1), { duration: 360, curve: Curve.Friction, zIndex: 10 })
          .hitTestBehavior(HitTestMode.None)
        }.width('100%').height('100%').backgroundColor($r('app.color.gallery_background'))
          .opacity(this.alphaB * (this.failed ? 0.2 : 1)).zIndex(this.stageSlot === 1 ? 1 : 0)
          .hitTestBehavior(HitTestMode.None)
        }, (address: string): string => address)
        if (this.failed) {
          Column({ space: 16 }) {
            Text(AppLanguage.text($r('app.string.ui_could_not_load_image'), this.languageRevision))
              .fontSize(15).fontColor($r('app.color.gallery_foreground')).textAlign(TextAlign.Center)
            FloatingActionButton({ label: AppLanguage.text($r('app.string.ui_retry'), this.languageRevision),
              labelColor: $r('app.color.gallery_foreground'),
              actionEnabled: this.source.length > 0, emphasized: true,
              onAction: () => { this.retryImage() } }).width(96)
            DiagnosticLink({ message: this.errorDetails, summary: AppLanguage.text($r('app.string.ui_could_not_load_image'), this.languageRevision), color: $r('app.color.gallery_accent'), controlId: 'gallery-diagnostics' })
          }.padding(24).zIndex(2)
        } else {
          if (this.imageLoading && !this.displayed) {
            LoadingProgress().width(36).height(36).color($r('app.color.gallery_accent')).hitTestBehavior(HitTestMode.None).zIndex(2)
          }
        }
      }.width('100%').height('100%').clip(true)
        .id('gallery-viewport')
        .onTouch((event: TouchEvent) => { this.touchImage(event) })
        .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => { this.updateViewport(size) })
        .gesture(GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2 }).onActionStart((event: GestureEvent) => { this.startPinch(event) })
            .onActionUpdate((event: GestureEvent) => { this.updatePinch(event) })
            .onActionEnd(() => { this.finishPinch() })
            .onActionCancel(() => { this.finishPinch() }),
          PanGesture({ fingers: 1 }).onActionStart(() => { this.startPan() })
            .onActionUpdate((event: GestureEvent) => { this.updatePan(event) })
            .onActionEnd((event: GestureEvent) => { this.finishPan(event) })
            .onActionCancel(() => { this.cancelPan() }),
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2, fingers: 1 }).onAction((event: GestureEvent) => { this.zoomAt(event) }),
            TapGesture({ count: 1, fingers: 1 }).onAction(() => { this.toggleControls() })
          )
        ))
      Stack({ alignContent: Alignment.Top }) {
        Column().width('100%').height(px2vp(Math.max(this.topPx, this.controlsTopPx)) + 120)
          .linearGradient({ direction: GradientDirection.Bottom, colors: [
            [$r('app.color.gallery_edge_shade'), 0], [$r('app.color.gallery_edge_shade'), 0.45],
            [$r('app.color.gallery_edge_fade'), 0.7], [Color.Transparent, 1]
          ] }).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }.width('100%').height('100%').hitTestBehavior(HitTestMode.None).opacity(this.controlsOpacity)
      Stack({ alignContent: Alignment.Bottom }) {
        Column().width('100%').height(px2vp(this.bottomPx) + 100)
          .linearGradient({ direction: GradientDirection.Bottom, colors: [
            [Color.Transparent, 0], [$r('app.color.gallery_edge_fade'), 0.35],
            [$r('app.color.gallery_edge_shade'), 0.65], [$r('app.color.gallery_edge_shade'), 1]
          ] }).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }.width('100%').height('100%').hitTestBehavior(HitTestMode.None).opacity(this.controlsOpacity)
      Stack({ alignContent: Alignment.Top }) {
        Column({ space: 10 }) {
          Row({ space: 12 }) {
            FloatingActionButton({ label: AppLanguage.text($r('app.string.settings_back'), this.languageRevision), icon: 'back',
              labelColor: $r('app.color.gallery_foreground'),
              fallbackColor: $r('app.color.gallery_control_tint'),
              controlHeight: 48, onAction: () => { this.closeGallery() }  }).width(48)
              .id('gallery-back')
            Blank()
            if (GalleryImageSave.supported()) {
            // saveOriginal owns single-flight input. Keep the material/outline
            // stable instead of disabling and rebuilding the native control.
            GallerySaveControl({ actionEnabled: this.source.length > 0,
              onSave: () => { this.saveOriginal() } })
              .width(48).height(48)
              .accessibilityText(AppLanguage.text($r('app.string.ui_download_original'), this.languageRevision))
            }
          }.width('100%')
          if (this.saving) {
            Text($r('app.string.ui_saving')).fontSize(12).fontColor($r('app.color.gallery_foreground'))
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
          } else if (this.originalLoading && this.displayed) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color($r('app.color.gallery_accent'))
              Text(AppLanguage.text($r('app.string.gallery_original_loading'), this.languageRevision))
                .fontSize(12).fontColor($r('app.color.gallery_foreground'))
            }.hitTestBehavior(HitTestMode.None)
          } else if (this.originalFailed && this.displayed) {
            Row({ space: 8 }) {
              Text(AppLanguage.text($r('app.string.gallery_original_failed_preview'), this.languageRevision))
                .fontSize(12).fontColor($r('app.color.gallery_foreground')).maxLines(2)
              FloatingActionButton({ label: AppLanguage.text($r('app.string.ui_retry'), this.languageRevision),
                labelColor: $r('app.color.gallery_foreground'),
                controlHeight: 36, emphasized: true, onAction: () => { this.retryImage() } }).width(64)
              DiagnosticLink({ message: this.errorDetails, summary: AppLanguage.text($r('app.string.ui_could_not_load_image'), this.languageRevision), color: $r('app.color.gallery_accent'), controlId: 'gallery-diagnostics' })
            }.padding({ left: 6, right: 6 })
          }
        }.width('100%').padding({ top: px2vp(Math.max(this.topPx, this.controlsTopPx)) + 10, left: 20, right: 20 })
          .hitTestBehavior(HitTestMode.Transparent)
      }.width('100%').height('100%').hitTestBehavior(this.controlsVisible ? HitTestMode.Transparent : HitTestMode.None)
        .enabled(this.controlsVisible).opacity(this.controlsOpacity).zIndex(2).id('gallery-top-controls')
      if (this.gallery.length > 1) {
        // Parent Stack alignment locates the capsule; align() only aligns the
        // component's own children and previously put this bar in the status bar.
        Stack({ alignContent: Alignment.Bottom }) {
          FloatingSurface({ radius: 24, acceptsInput: true,
            fallbackColor: $r('app.color.gallery_control_tint'), content: () => { this.GalleryControls() } })
            .width('78%').constraintSize({ maxWidth: 340 }).height(48)
            .margin({ bottom: Math.max(16, px2vp(this.bottomPx)) + 12 })
        }.width('100%').height('100%').hitTestBehavior(this.controlsVisible ? HitTestMode.Transparent : HitTestMode.None)
          .enabled(this.controlsVisible).opacity(this.controlsOpacity).zIndex(2).id('gallery-bottom-controls')
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.gallery_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }
}

@Entry
@Component
struct ForumImagePage {
  private controller: ForumImageController = new ForumImageController()
  onBackPress(): boolean { return this.controller.back() }
  pageTransition() {
    // These transitions belong exclusively to the image viewer. The forum,
    // post detail and other routes retain their system-default animations.
    PageTransitionEnter({ duration: 360, curve: Curve.Friction }).opacity(0)
      .onEnter((_type: RouteType, progress: number) => { if (progress >= 1) this.controller.entered() })
    PageTransitionExit({ duration: 360, curve: Curve.Friction }).opacity(0)
  }
  build() {
    Stack() { ForumImageView({ controller: this.controller }) }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
