import { FloatingActionButton } from './FloatingActionButton'

/** Authorization is handled by the system save dialog. This icon keeps the
 * same native material, light and input feedback as the adjacent controls. */
@Component
export struct GallerySaveControl {
  @Prop actionEnabled: boolean = false
  onSave: () => void = () => {}

  build() {
    FloatingActionButton({ label: $r('app.string.ui_download_original'), icon: 'download',
      iconSize: 22, controlHeight: 48, controlId: 'gallery-save',
      labelColor: $r('app.color.gallery_foreground'), fallbackColor: $r('app.color.gallery_control_tint'),
      actionEnabled: this.actionEnabled, onAction: () => { this.onSave() } })
      .width(48).height(48)
  }
}
