import { AppLanguage } from '../common/AppLanguage'
import { HapticFeedback } from '../common/HapticFeedback'
import { FloatingSurface } from './FloatingSurface'
import { ThemeColors } from '../common/Theme'

/** The native material host owns input/light/pressure feedback. Standalone
 * icons use its unclipped foreground plane; text controls use its builder. */
@Component
export struct FloatingActionButton {
  @Prop label: ResourceStr = ''
  @Prop icon: string = ''
  @Prop iconResource: Resource | undefined = undefined
  @Prop iconResourceIsMedia: boolean = false
  @Prop onCard: boolean = false
  @Prop iconSize: number = 22
  @Prop controlId: string = ''
  @Prop controlHeight: number = 40
  @Prop actionEnabled: boolean = true
  @Prop emphasized: boolean = false
  @Prop labelColor: ResourceColor | undefined = undefined
  @Prop fallbackColor: ResourceColor | undefined = undefined
  @Prop zeroContentPadding: boolean = false
  onAction: () => void = () => {}

  @Builder
  Control() {
    Button({ type: ButtonType.Capsule }) {
        Text(this.label).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
          .minFontSize(11).maxFontSize(14).heightAdaptivePolicy(TextHeightAdaptivePolicy.LAYOUT_CONSTRAINT_FIRST)
          .fontColor(this.labelColor ?? (this.emphasized ? ThemeColors.primary : ThemeColors.textPrimary))
    }
      // Icons use the host's foreground plane; text controls use this builder.
      .width('100%').height('100%').padding(0)
      .fontSize(14).fontWeight(FontWeight.Medium)
      .labelStyle({ minFontSize: 11, maxFontSize: 14, maxLines: 1,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.LAYOUT_CONSTRAINT_FIRST })
      .fontColor(this.labelColor ?? (this.emphasized ? ThemeColors.primary : ThemeColors.textPrimary))
      .backgroundColor(Color.Transparent).enabled(this.actionEnabled)
      .stateEffect(false).hoverEffect(HoverEffect.None)
      .id(this.controlId || (this.icon === 'back' ? 'navigation-back' : '')).accessibilityText(typeof this.label === 'string' ? this.label : AppLanguage.text(this.label))
      .onClick(() => { HapticFeedback.selection(); this.onAction() })
  }

  build() {
    FloatingSurface({ radius: this.controlHeight / 2, acceptsInput: true,
      fallbackColor: this.fallbackColor ?? (this.onCard ? $r('app.color.floating_card_fallback') : undefined),
      onCard: this.onCard,
      zeroContentPadding: this.zeroContentPadding,
      iconName: this.icon, iconId: this.controlId || (this.icon === 'back' ? 'navigation-back' : ''),
      iconResource: this.iconResource, iconResourceIsMedia: this.iconResourceIsMedia,
      iconSize: this.iconSize,
      iconLabel: this.label, iconEnabled: this.actionEnabled,
      iconColor: this.labelColor ?? ThemeColors.textPrimary,
      onIconAction: () => { HapticFeedback.selection(); this.onAction() },
      content: () => { this.Control() } })
      .width('100%').height(this.controlHeight)
  }
}
