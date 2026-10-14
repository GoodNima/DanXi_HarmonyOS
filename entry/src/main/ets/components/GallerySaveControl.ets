import { FloatingSurface } from './FloatingSurface'
import { AppLanguage } from '../common/AppLanguage'

/** Floating TabBar has mandatory item insets. Keep the security component in
 * a full-size sibling, so both its icon and authorization bounds stay intact.
 * Transparent hit testing also lets the native host receive light/pressure
 * input; the host stops that tap reaching the image underneath. */
@Component
export struct GallerySaveControl {
  @Prop actionEnabled: boolean = false
  onResult: (result: SaveButtonOnClickResult) => void = () => {}

  build() {
    Stack() {
      FloatingSurface({ radius: 24, acceptsInput: true,
        iconEnabled: this.actionEnabled, fallbackColor: $r('app.color.gallery_control_tint') })
        .width(48).height(48)
        .accessibilityLevel('no-hide-descendants')
      Row() {
        SaveButton({ icon: SaveIconStyle.LINES, buttonType: ButtonType.Circle })
          .iconSize(22).iconColor($r('app.color.gallery_foreground'))
          // Native authorization requires background alpha >= 0x1a. Use only
          // that minimum uniform circle over the material, with no image backing.
          .backgroundColor('#1AFFFFFF')
          .width(48).height(48).padding(13).stateEffect(false)
          .id('gallery-save').enabled(this.actionEnabled).userCancelEvent(true)
          .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => { this.onResult(result) })
      }
        .width(48).height(48)
        .hitTestBehavior(HitTestMode.Transparent)
    }
      .width(48).height(48)
      .accessibilityText(AppLanguage.text($r('app.string.ui_download_original')))
  }
}
