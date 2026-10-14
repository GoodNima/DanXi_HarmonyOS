import { ClassroomPreference } from '../common/ClassroomPreference'
import { ForumPresentation } from '../common/ForumPresentation'
import { ThemeDimens } from '../common/Theme'

/** Native buttons arbitrate their tap with the surrounding card recognizers.
 * Keep raw touch delivery intact so a gesture beginning on a tag can still
 * become a list scroll rather than being intercepted by a Text handler. */
@Component
export struct ForumTagChip {
  @Prop name: string = ''
  @StorageLink(ClassroomPreference.KEY_HIGH_CONTRAST) highContrast: boolean = false
  @StorageLink('app_dark_mode') darkMode: boolean = false
  onSelect: (name: string) => void = () => {}

  build() {
    Button(ForumPresentation.tagLabel(this.name), { type: ButtonType.Normal })
      .fontSize(ThemeDimens.textSizeSmall)
      .fontColor(ForumPresentation.featured(this.name) ? Color.White : ForumPresentation.tagColor(this.name, this.darkMode, this.highContrast))
      .backgroundColor(ForumPresentation.tagBackground(this.name, this.darkMode, this.highContrast))
      .linearGradient({ direction: GradientDirection.Right, colors: ForumPresentation.featured(this.name) ?
        [['#007AFF', 0], ['#009AD8', 1]] : [[Color.Transparent, 0], [Color.Transparent, 1]] })
      .border({ width: this.highContrast ? 1 : 0, color: ForumPresentation.tagColor(this.name, this.darkMode, this.highContrast), radius: 8 })
      .borderRadius(8).clip(true)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .height(26)
      .responseRegion({ x: 0, y: -5, width: '100%', height: 36 })
      .stateEffect(false)
      .hoverEffect(HoverEffect.None)
      .accessibilityText(ForumPresentation.tagLabel(this.name))
      .onClick(() => { this.onSelect(this.name) })
  }
}
