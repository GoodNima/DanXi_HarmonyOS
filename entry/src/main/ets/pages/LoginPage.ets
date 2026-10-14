import { ErrorNotice } from '../components/ErrorNotice'
import { AppLanguage } from '../common/AppLanguage'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
/**
 * Login Page - Fudan University UIS login.
 * Immersive light sense design.
 * Ported from lib/page/login_page.dart
 */

import { router, promptAction } from '@kit.ArkUI'
import { FduRepository, LoginResult } from '../repository/FduRepository'
import { AppState } from '../common/AppState'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { Constant } from '../common/Constant'
import { getSymbolIcon } from '../common/DanXiIcons'
import { Person } from '../model/Person'
import { ErrorDiagnostics } from '../model/ErrorDiagnostics'

@Entry
@Component
struct LoginPage {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @State academicGroup: string = 'undergraduate'
  @State studentId: string = ''
  @State password: string = ''
  @State isLoading: boolean = false
  @State showPassword: boolean = false
  @State error: string = ''

  private fduRepo: FduRepository = FduRepository.getInstance()

  async handleLogin(): Promise<void> {
    if (this.isLoading) return
    if (this.studentId.length === 0) {
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_enter_your_student_id'), this.languageRevision) })
      return
    }
    if (this.password.length === 0) {
      promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_enter_your_password'), this.languageRevision) })
      return
    }

    this.isLoading = true
    this.error = ''
    try {
      const result: LoginResult = await this.fduRepo.login(this.studentId, this.password)
      if (result.success && result.person) {
        const person: Person = result.person
        person.academicGroup = this.academicGroup
        await AppState.clearGuest()
        await AppState.setPerson(person)
        this.password = ''
        promptAction.showToast({ message: AppLanguage.text($r('app.string.ui_logged_in'), this.languageRevision) })
        router.clear()
        await router.pushUrl({ url: 'pages/Index' })
      } else {
        this.error = ErrorDiagnostics.message(new Error(result.error || 'Login failed'))
        }
    } catch (e) {
      this.error = ErrorDiagnostics.message(e as Object)
      } finally {
      this.isLoading = false
    }
  }

  /** Enter the app without an account. */
  handleGuestEntry(): void {
    if (this.isLoading) return
    AppState.setGuest().then(() => {
      router.clear()
      router.pushUrl({ url: 'pages/Index' })
    })
  }

  build() {
    Stack() {
      // ── Gradient background (extends behind system bars) ──
      Column()
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .linearGradient({
          angle: 135,
          colors: [[ThemeColors.bgStart, 0], [ThemeColors.bgEnd, 1]],
          repeating: false,
        })

      // ── Main content ──
      Column() {
        // Logo area – clean transparent logo text
        Column() {
          Text(AppLanguage.text($r('app.string.EntryAbility_desc'), this.languageRevision))
            .fontSize(56)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.primary)
          Text(AppLanguage.text($r('app.string.ui_fudan_campus_assistant'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeBody)
            .fontColor(ThemeColors.textSecondary)
            .margin({ top: 8 })
            .letterSpacing(2)
        }
        .margin({ top: 120, bottom: 48 })

        // ── Glass login form ──
        Column() {
          Select([{ value: $r('app.string.account_undergraduate') }, { value: $r('app.string.account_postgraduate') }])
            .selected(this.academicGroup === 'postgraduate' ? 1 : 0)
            .value(this.academicGroup === 'postgraduate' ? $r('app.string.account_postgraduate') : $r('app.string.account_undergraduate'))
            .onSelect((index: number) => { this.academicGroup = index === 1 ? 'postgraduate' : 'undergraduate' })
            .margin({ bottom: 12 })
          // Student ID input
          TextInput({ text: this.studentId, placeholder: AppLanguage.text($r('app.string.ui_student_id'), this.languageRevision) })
            .type(InputType.Normal)
            .height(52)
            .borderRadius(ThemeDimens.radiusMedium)
            .backgroundColor(ThemeColors.cardBg)
            .padding({ left: 16, right: 16 })
            .fontSize(ThemeDimens.textSizeBody)
            .fontColor(ThemeColors.textPrimary)
            .placeholderColor(ThemeColors.textHint)
            .onChange((value: string) => {
              this.studentId = value
            })

          // Password input
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

            // Toggle password visibility.
            // SymbolGlyph, not an emoji: the project bans emoji as functional icons.
            SymbolGlyph(getSymbolIcon(this.showPassword ? 'eye_slash' : 'eye'))
              .fontSize(20)
              .fontColor([ThemeColors.textSecondary])
              .margin({ right: 12 })
              .onClick(() => {
                this.showPassword = !this.showPassword
              })
          }
          .height(52)
          .borderRadius(ThemeDimens.radiusMedium)
          .backgroundColor(ThemeColors.cardBg)
          .margin({ top: 12 })

          // Login button
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
            .shadow({
              radius: 12,
              color: 'rgba(74, 144, 217, 0.3)',
              offsetX: 0,
              offsetY: 4,
            })
            .onClick(() => this.handleLogin())

          if (this.error) {
            ErrorNotice({ message: this.error, controlId: 'loginpage-diagnostics', textSize: 13, textColor: ThemeColors.error }).width('100%').margin({ top: 12 })
          }

          // Help text
          Text(AppLanguage.text($r('app.string.ui_log_in_with_your_fudan_id_official_verification_'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeSmall)
            .fontColor(ThemeColors.textHint)
            .margin({ top: 16 })
            .textAlign(TextAlign.Center)

          // Guest entry
          Text(AppLanguage.text($r('app.string.ui_continue_as_guest'), this.languageRevision))
            .fontSize(ThemeDimens.textSizeBody)
            .fontColor(ThemeColors.primary)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 24 })
            .onClick(() => this.handleGuestEntry())
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 24 })
        .backgroundColor($r('app.color.surface_fallback'))
      .systemMaterial(adaptiveMaterial(this.materialRevision))
      
        .borderRadius(ThemeDimens.radiusLarge)
      }
      .width('100%')
      .padding({ left: 28, right: 28 })

      // Footer
      Column() {
        Text('DanXi HarmonyOS Edition')
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textHint)
        Text('v' + Constant.APP_DISPLAY_VERSION)
          .fontSize(ThemeDimens.textSizeSmall)
          .fontColor(ThemeColors.textHint)
          .margin({ top: 4 })
      }
      .position({ x: '50%', y: '93%' })
      .translate({ x: '-50%' })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
