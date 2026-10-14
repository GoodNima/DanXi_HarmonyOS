import { floatingMaterial, containerFloatingMaterial, nativeFloatingBackground } from '../common/AdaptiveMaterial'
import { common } from '@kit.AbilityKit'
import { getSymbolIcon } from '../common/DanXiIcons'
import { ThemeColors } from '../common/Theme'
import { AppLanguage } from '../common/AppLanguage'
import { containsMaterialPoint, MaterialBounds, MaterialTouchGuard } from '../common/MaterialTouchBounds'

/** Native bottom TabBar is a supported material host. Keeping the controls in
 * its builder lets the system receive their touch events for material pressure
 * and light feedback. Backdrop-only callers remain transparent to hit testing.
 */
@Component
export struct FloatingSurface {
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink('app_dark_mode') darkMode: boolean = false
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @Prop radius: number = 28
  @Prop acceptsInput: boolean = false
  @Prop zeroContentPadding: boolean = false
  @Prop fallbackColor: ResourceColor | undefined = undefined
  @Prop iconName: string = ''
  @Prop iconResource: Resource | undefined = undefined
  @Prop iconResourceIsMedia: boolean = false
  @Prop onCard: boolean = false
  @Prop iconId: string = ''
  @Prop iconLabel: ResourceStr = ''
  @Prop iconColor: ResourceColor = ThemeColors.textPrimary
  @Prop iconSize: number = 22
  @Prop iconEnabled: boolean = true
  onIconAction: () => void = () => {}
  @BuilderParam content: () => void = this.EmptyBar
  @State private surfaceWidth: number = 0
  @State private surfaceHeight: number = 0
  private touchGuard: MaterialTouchGuard = new MaterialTouchGuard()
  @State private pointFeedback: boolean = true
  @State private flatPressed: boolean = false
  private sizeTimer: number = -1
  private active: boolean = false
  private iconActionPending: boolean = false
  private iconActionRevision: number = 0

  aboutToAppear(): void { this.active = true }
  aboutToDisappear(): void {
    this.active = false
    this.iconActionRevision++
    this.iconActionPending = false
    if (this.sizeTimer >= 0) clearTimeout(this.sizeTimer)
    this.sizeTimer = -1
    this.touchGuard.cancel()
    this.flatPressed = false
  }

  private activateIcon(): void {
    if (!this.active || !this.acceptsInput || !this.iconName || !this.iconEnabled || this.iconActionPending) return
    this.iconActionPending = true
    const revision: number = ++this.iconActionRevision
    // Commit after the input frame, preserving native light/pressure feedback.
    // Pointer input has one Tap owner; semantic/key callbacks share the same
    // reentrancy guard without delaying the next independent activation.
    this.getUIContext().postFrameCallback({ onFrame: () => {
      if (revision !== this.iconActionRevision) return
      try {
        if (this.active && this.acceptsInput && this.iconName && this.iconEnabled) this.onIconAction()
      } finally {
        this.iconActionPending = false
      }
    }, onIdle: () => {} })
  }

  private updateSurfaceSize(size: SizeOptions): void {
    const width: number = Number(size.width)
    const height: number = Number(size.height)
    // Inactive/preloaded pages can be measured at zero. Do not give the native
    // TabBar a placeholder 1vp/0vp width or erase the last valid dimensions.
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return
    if (this.sizeTimer >= 0) clearTimeout(this.sizeTimer)
    this.sizeTimer = -1
    if (width === this.surfaceWidth && height === this.surfaceHeight) return
    // onSizeChange is synchronous during layout; commit outside that layout's
    // animation transaction and coalesce intermediate measurements.
    this.sizeTimer = setTimeout(() => {
      this.sizeTimer = -1
      if (!this.active) return
      this.pointFeedback = this.touchGuard.cancel()
      this.surfaceHeight = height
      this.surfaceWidth = width
    }, 0)
  }

  private materialTouch(event: TouchEvent): void {
    if (!this.acceptsInput) return
    if (event.type === TouchType.Cancel || event.touches.length > 1) {
      this.pointFeedback = this.touchGuard.cancel()
      return
    }
    const bounds: MaterialBounds = { x: 0, y: 0, width: this.surfaceWidth,
      height: this.surfaceHeight, radius: this.radius }
    for (const point of event.changedTouches) {
      const inside: boolean = containsMaterialPoint(bounds, point.x, point.y)
      if (event.type === TouchType.Down) this.pointFeedback = this.touchGuard.down(point.id, inside)
      else if (event.type === TouchType.Move) this.pointFeedback = this.touchGuard.move(point.id, inside)
      else if (event.type === TouchType.Up) this.pointFeedback = this.touchGuard.up(point.id)
    }
  }

  @Builder
  EmptyBar() {
    Row().width('100%').height('100%')
  }

  private contentThemeKey(revision: number): string {
    // Native custom tabBar builders can retain their old resource colors while
    // an inactive page receives a new theme. Recreate that host only when its
    // resolved palette/language changes, never for foreground/material events.
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const manager = context.resourceManager
      return String(manager.getColorSync($r('app.color.theme_text_primary').id)) + '/' +
        String(manager.getColorSync($r('app.color.theme_primary').id)) + '/' +
        String(manager.getColorSync($r('app.color.floating_fallback').id)) + '/' + this.languageRevision
    } catch (e) {
      return String(this.darkMode) + '/' + this.languageRevision
    }
  }

  @Builder
  NativeSurface() {
    Tabs({ barPosition: BarPosition.End }) {
      if (this.iconName) {
        TabContent() { Column() }.tabBar(this.EmptyBar)
      } else {
        TabContent() { Column() }.tabBar(this.content)
      }
    }
      .barHeight(this.radius * 2).barOverlap(true).scrollable(false)
      .barBackgroundColor(nativeFloatingBackground(this.materialRevision, this.fallbackColor))
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barWidth: { smallBarWidth: this.surfaceWidth, mediumBarWidth: this.surfaceWidth,
          largeBarWidth: this.surfaceWidth },
        barSideMargin: 0, barBottomMargin: 0, maskHeight: 0, maskColor: Color.Transparent,
        systemMaterial: floatingMaterial(this.materialRevision, this.pointFeedback, this.onCard)
      })
      .width('100%').height('100%').backgroundColor(Color.Transparent)
      .enabled(this.iconEnabled)
      .id(this.iconId).accessibilityText(typeof this.iconLabel === 'string' ? this.iconLabel : AppLanguage.text(this.iconLabel, this.languageRevision))
      .accessibilityGroup(this.iconName.length > 0)
      // TabBar consumes common pointer clicks in its centre. One parallel
      // tap recognizer covers both the centre and the capsule edge without
      // adding a second native tab callback or suppressing material feedback.
      .parallelGesture(TapGesture().onAction(() => { this.activateIcon() }))
      // Keep semantic/keyboard activation; pointer input belongs only to Tap.
      .onClick((event: ClickEvent) => {
        if (event.source !== SourceType.TouchScreen && event.source !== SourceType.Mouse) this.activateIcon()
      })
      // Clip only this capsule-sized native host, never the surrounding feed.
      // An unclipped host lets its point-light footprint escape into neighbours.
      .borderRadius(this.radius).clip(true)
      .onAppear(() => {
        // A newly themed native host must not inherit an unfinished pointer
        // from the replaced host. Old onDisappear callbacks never write State.
        this.touchGuard.cancel()
        this.pointFeedback = true
      })
      // The material host owns elastic deformation and the touch highlight.
      // Scaling the enclosing Tabs also scales its sampled surface and clips
      // the native effect during a press.
      .onTouch((event: TouchEvent) => { this.materialTouch(event) })
      .hitTestBehavior(this.acceptsInput ? HitTestMode.Default : HitTestMode.None)
      .focusable(this.acceptsInput)
      .accessibilityLevel(this.acceptsInput ? 'auto' : 'no-hide-descendants')
  }

  private fittedIconSize(): number {
    const requested: number = Number.isFinite(this.iconSize) && this.iconSize > 0 ? this.iconSize : 22
    return Math.min(requested, Math.max(1, Math.min(this.surfaceWidth, this.surfaceHeight) - 8))
  }

  @Builder
  IconOverlay() {
    // The floating TabBar reserves 12vp side / 4vp vertical insets even for a
    // custom builder. A 28vp control consequently clips its icon to about 4vp.
    // Draw the icon in the measured outer capsule; the native host beneath it
    // alone owns material feedback, accessibility and action delivery.
    Row() { this.FullContent() }
      .width(this.surfaceWidth).height(this.surfaceHeight)
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }

  @Builder
  FullContent() {
      if ((this.iconResourceIsMedia && this.iconResource !== undefined) || this.iconName === 'summary' || this.iconName === 'more') {
        Image(this.iconResource ?? (this.iconName === 'summary' ? $r('app.media.ai_summary') : $r('app.media.more_dots')))
          .width(this.fittedIconSize()).height(this.fittedIconSize())
          .objectFit(ImageFit.Contain).fillColor(this.iconColor)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      } else if (this.iconName) {
        // A fixed control's icon is in vp. Scaling an fp glyph inside the vp
        // frame would reintroduce clipping when accessibility text is enlarged.
        SymbolGlyph(this.iconResource ?? getSymbolIcon(this.iconName)).fontSize(String(this.fittedIconSize()) + 'vp')
          .width(this.fittedIconSize() + 2).height(this.fittedIconSize() + 2)
          // SymbolGlyph aligns its font cell at the content's leading edge.
          // Split the safety frame equally around that cell so its centre,
          // not only the enclosing node's centre, matches the capsule centre.
          .padding(1)
          .fontColor([this.iconColor]).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      } else {
        this.content()
      }
  }

  @Styles
  FullHost() {
    .width('100%').height('100%')
      .borderRadius(this.radius).clip(true)
      .id(this.iconId).enabled(this.iconEnabled)
      .accessibilityText(typeof this.iconLabel === 'string' ? this.iconLabel : AppLanguage.text(this.iconLabel, this.languageRevision))
      .accessibilityGroup(this.iconName.length > 0)
      .onClick(() => { this.activateIcon() })
      .onTouch((event: TouchEvent) => { this.materialTouch(event) })
      .hitTestBehavior(this.acceptsInput ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  FullSurface() {
    // Security components must not be clipped by a floating TabBar's item
    // insets. SDK 26 exposes the same material on an ordinary container.
    // Never apply backgroundColor to the enabled native material node: that
    // attribute competes with the material's own backing on low-tier devices.
    if (containerFloatingMaterial(this.materialRevision, this.pointFeedback) !== undefined) {
      Row() { this.FullContent() }.FullHost().justifyContent(FlexAlign.Center)
        .systemMaterial(containerFloatingMaterial(this.materialRevision, this.pointFeedback))
    } else {
      Row() { this.FullContent() }.FullHost().justifyContent(FlexAlign.Center)
        .backgroundColor(this.fallbackColor ?? $r('app.color.floating_fallback'))
    }
  }

  private flatTouch(event: TouchEvent): void {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel || event.touches.length > 1) {
      this.flatPressed = false
      return
    }
    const bounds: MaterialBounds = { x: 0, y: 0, width: this.surfaceWidth,
      height: this.surfaceHeight, radius: this.radius }
    for (const point of event.changedTouches) {
      if (event.type === TouchType.Down) this.flatPressed = containsMaterialPoint(bounds, point.x, point.y)
      else if (event.type === TouchType.Move && !containsMaterialPoint(bounds, point.x, point.y)) this.flatPressed = false
    }
  }

  @Builder
  FlatSurface() {
    // On-card actions have a flat backing in both themes. They are separate
    // from floating toolbars: no native glass host, shadow or color inversion.
    Button({ type: ButtonType.Capsule }) {
      Row() { this.FullContent() }.width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    }.width('100%').height('100%').padding(0).borderRadius(this.radius)
      .backgroundColor($r('app.color.card_control_background'))
      .stateEffect(false).hoverEffect(HoverEffect.None).enabled(this.iconEnabled)
      .id(this.iconId).accessibilityText(typeof this.iconLabel === 'string' ? this.iconLabel : AppLanguage.text(this.iconLabel, this.languageRevision))
      .scale({ x: this.flatPressed ? 0.94 : 1, y: this.flatPressed ? 0.94 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => { this.flatTouch(event) })
      .onClick(() => { this.activateIcon() })
      .hitTestBehavior(this.acceptsInput ? HitTestMode.Default : HitTestMode.None)
  }

  build() {
    Stack() {
      // Measure the stable outer box before creating its native material host.
      // The first TabBar layout therefore already receives its real width.
      if (this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        if (this.onCard) this.FlatSurface()
        else {
        ForEach([this.contentThemeKey(this.materialRevision)], (_key: string) => {
          // Standalone icon controls use the supported native floating TabBar
          // host in every material state. FullSurface is reserved for builders
          // such as SaveButton that genuinely require zero content insets.
          if (this.zeroContentPadding && !this.iconName) this.FullSurface()
          else {
            Stack() {
              this.NativeSurface()
              if (this.iconName) this.IconOverlay()
            }.width('100%').height('100%')
          }
        }, (key: string) => key)
        }
      }
    }.width('100%').height('100%')
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => { this.updateSurfaceSize(size) })
      .hitTestBehavior(this.acceptsInput ? HitTestMode.Transparent : HitTestMode.None)
  }
}
