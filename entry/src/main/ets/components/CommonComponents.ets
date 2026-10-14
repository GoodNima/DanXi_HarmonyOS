import { AppLanguage } from '../common/AppLanguage'
/**
 * Reusable UI components for DanXi HarmonyOS app.
 * Immersive light sense design.
 */

import { ThemeColors, ThemeDimens } from '../common/Theme'

@Component
export struct LoadingIndicator {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @Prop message: string = AppLanguage.text($r('app.string.ui_loading_168'), this.languageRevision)

  build() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(ThemeColors.primary)
      Text(this.message)
        .fontSize(ThemeDimens.textSizeBody)
        .fontColor(ThemeColors.textSecondary)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct EmptyState {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @Prop icon: string = '📭'
  @Prop message: string = AppLanguage.text($r('app.string.ui_no_data'), this.languageRevision)

  build() {
    Column() {
      Text(this.icon)
        .fontSize(48)
      Text(this.message)
        .fontSize(ThemeDimens.textSizeBody)
        .fontColor(ThemeColors.textHint)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
