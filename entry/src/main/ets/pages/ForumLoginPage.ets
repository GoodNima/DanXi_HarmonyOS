import { ErrorNotice } from '../components/ErrorNotice'
import { AppLanguage } from '../common/AppLanguage'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
/**
 * Tree Hole login page.
 *
 * fduhole.com accounts are SEPARATE from the Fudan UIS account: the forum
 * authenticates against https://auth.fduhole.com/api/login with an
 * email + password pair and returns a JWT, not a UIS session.
 * Ported from lib/page/forum/hole_login.dart
 */

import { router, promptAction } from '@kit.ArkUI'
import { ForumRepository } from '../repository/ForumRepository'
import { FduRepository } from '../repository/FduRepository'
import { HttpError } from '../util/HttpUtil'
import { ForumRoute } from '../common/ForumRoute'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { ThemeColors, ThemeDimens } from '../common/Theme'

@Entry
@Component
struct ForumLoginPage {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @State email: string = ''
  @State password: string = ''
  @State isLoading: boolean = false
  @State showPassword: boolean = false
  @State campusLoginRequired: boolean = false
  @State verificationRequired: boolean = false
  @State error: string = ''

  private forumRepo: ForumRepository = ForumRepository.getInstance()

  handleLogin(): void {
    if (this.isLoading) return
    if (this.email.length === 0) {
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_enter_your_forum_email'), this.languageRevision) })
      return
    }
    if (this.password.length === 0) {
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_enter_your_password'), this.languageRevision) })
      return
    }
    this.isLoading = true
    this.campusLoginRequired = false
    this.verificationRequired = false
    this.error = ''
    this.forumRepo.login(this.email, this.password).then(() => {
      this.isLoading = false
      // Tell the forum tab to reload. A plain router.back() would not re-run
      // ForumPage.aboutToAppear, so the list would stay on the login prompt.
      AppStorage.setOrCreate<boolean>('forum_logged_in', true)
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_logged_in'), this.languageRevision) })
      router.back()
    }).catch((e: Object) => {
      this.isLoading = false
      this.verificationRequired = e instanceof HttpError && e.statusCode === -2
      this.campusLoginRequired = this.verificationRequired && !FduRepository.getInstance().canLoginOnDemand()
      this.error = ErrorDiagnostics.message(e, this.verificationRequired ? AppLanguage.text($r('app.string.forum_webvpn_verification_hint'), this.languageRevision) :
        e instanceof HttpError && e.code === 2300028 ? AppLanguage.text($r('app.string.forum_login_timeout_hint'), this.languageRevision) : '')
      })
  }

  private async continueVerification(): Promise<void> {
    if (this.isLoading) return
    if (this.campusLoginRequired) { router.pushUrl({ url: 'pages/LoginPage' }); return }
    this.isLoading = true
    try {
      await FduRepository.getInstance().verifyService(ForumRoute.LOGIN_URL)
      this.isLoading = false
      // The forum password is submitted again only after this explicit user action.
      this.handleLogin()
    } catch (e) {
      this.error = ForumRepository.describeError(e)
      this.isLoading = false
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .linearGradient({
          angle: 135,
          colors: [[ThemeColors.bgStart, 0], [ThemeColors.bgEnd, 1]],
          repeating: false,
        })

      Column() {
        Row() {
          FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48,
            onAction: () => { router.back() } }).width(48)
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })

        Column() {
          Text(AppLanguage.text($r('app.string.ui_log_in_to_forum'), this.languageRevision))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary)
          Text(AppLanguage.text($r('app.string.ui_use_your_danxi_forum_account_separate_from_uis'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeSmall)
            .fontColor(ThemeColors.textSecondary)
            .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 4, right: 4 })
        .margin({ top: 48, bottom: 32 })

        Column() {
          TextInput({ text: this.email, placeholder: AppLanguage.text($r('app.string.ui_email'), this.languageRevision) })
            .type(InputType.Email)
            .height(52)
            .borderRadius(ThemeDimens.radiusMedium)
            .backgroundColor(ThemeColors.cardBg)
            .padding({ left: 16, right: 16 })
            .fontSize(ThemeDimens.textSizeBody)
            .fontColor(ThemeColors.textPrimary)
            .placeholderColor(ThemeColors.textHint)
            .onChange((value: string) => {
              this.email = value
            })

          Row() {
            TextInput({ text: this.password, placeholder: AppLanguage.text($r('app.string.ui_password'), this.languageRevision) })
              .type(this.showPassword ? InputType.Normal : InputType.Password)
              .height(52)
              .backgroundColor(Color.Transparent)
              .padding({ left: 16, right: 8 })
              .fontSize(ThemeDimens.textSizeBody)
              .fontColor(ThemeColors.textPrimary)
              .placeholderColor(ThemeColors.textHint)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.password = value
              })

            Text(this.showPassword ? AppLanguage.text($r('app.string.caution_hide'), this.languageRevision) : AppLanguage.text($r('app.string.caution_show'), this.languageRevision))
              .fontSize(ThemeDimens.textSizeSmall)
              .fontColor(ThemeColors.primary)
              .margin({ right: 16 })
              .onClick(() => {
                this.showPassword = !this.showPassword
              })
          }
          .height(52)
          .borderRadius(ThemeDimens.radiusMedium)
          .backgroundColor(ThemeColors.cardBg)
          .margin({ top: 12 })

          Button(this.isLoading ? AppLanguage.text($r('app.string.ui_logging_in'), this.languageRevision) : AppLanguage.text($r('app.string.ui_log_in'), this.languageRevision))
            .type(ButtonType.Normal)
            .width('100%')
            .height(52)
            .borderRadius(ThemeDimens.radiusMedium)
            .linearGradient({
              angle: 135,
              colors: [['#4A90D9', 0], ['#6BA3E0', 1]],
              repeating: false,
            })
            .fontColor('#FFFFFF')
            .fontSize(ThemeDimens.textSizeTitle)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 28 })
            .enabled(!this.isLoading)
            .onClick(() => this.handleLogin())

          if (this.error) {
            ErrorNotice({ message: this.error, controlId: 'forumloginpage-diagnostics', textSize: 13, textColor: ThemeColors.error })
              .margin({ top: 16 }).width('100%')
          }
          if (this.verificationRequired) {
            FloatingActionButton({ label: this.campusLoginRequired ? $r('app.string.ui_log_in_to_campus_account') :
              $r('app.string.campus_verify_continue'), actionEnabled: !this.isLoading,
              onAction: () => { this.continueVerification() } }).width('100%').margin({ top: 12 })
          }
          Text(AppLanguage.text($r('app.string.ui_register_on_the_forum_website_this_is_separate_f'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeSmall)
            .fontColor(ThemeColors.textHint)
            .margin({ top: 16 })
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .padding(24)
        .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
        .borderRadius(ThemeDimens.radiusLarge)
      }
      .width('100%')
      .padding({ left: 28, right: 28 })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
