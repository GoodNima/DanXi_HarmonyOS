import { ReadableText } from '../common/ReadableText'
import { ErrorNotice } from '../components/ErrorNotice'
import { settleScrollTouch } from '../common/ScrollTouch'
import { util } from '@kit.ArkTS'
import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { AppLanguage } from '../common/AppLanguage'
import { Constant } from '../common/Constant'
import { SettingsRouteParams } from '../common/RouteParams'
import { NetworkProxy } from '../common/NetworkProxy'
import { HapticFeedback } from '../common/HapticFeedback'
import { BrowserLink } from '../common/BrowserLink'
import { ForumContentParser } from '../model/ForumContent'
import { FloatingActionButton } from '../components/FloatingActionButton'
import { TopFade } from '../components/TopFade'
import { getSymbolIcon } from '../common/DanXiIcons'
import { AboutCredits, ContributorCredit, LibraryCredit } from '../common/AboutCredits'
import { SheetTransitionGuard } from '../common/SheetTransitionGuard'
import { adaptiveMaterial, nativeFloatingBackground } from '../common/AdaptiveMaterial'

class LicenseItem {
  name: string
  file: string
  constructor(name: string, file: string) { this.name = name; this.file = file }
}

@Entry
@Component
export struct SettingsUtilitiesPage {
  private touchScroller: Scroller = new Scroller()
  private contributorsScroller: Scroller = new Scroller()
  private contributorsTransition: SheetTransitionGuard = new SheetTransitionGuard()
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(Constant.KEY_STATUS_BAR_INSET_PX) topPx: number = 0
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomPx: number = 0
  @StorageLink(NetworkProxy.KEY_ACTIVE) activeProxy: string = ''
  @StorageLink(NetworkProxy.KEY_SAVED) savedProxies: string = '[]'
  @State section: string = 'about'
  @State input: string = ''
  @State adding: boolean = false
  @State busy: boolean = false
  @State error: string = ''
  @State licenseName: string = ''
  @State licenseText: string[] = []
  @State contributorsSheet: boolean = false
  private licenseRequest: number = 0
  private readonly contributors: ContributorCredit[] = AboutCredits.contributors()
  private readonly originalLibraries: LibraryCredit[] = AboutCredits.libraries()
  private readonly licenses: LicenseItem[] = [new LicenseItem('DanXi · GNU GPL v3', 'DanXi-GPL-3.0.txt'),
    new LicenseItem('DanXi Swift · GNU AGPL v3', 'DanXiSwift-AGPL-3.0.txt'),
    new LicenseItem('Cupertino Icons · MIT', 'CupertinoIcons-LICENSE.txt'),
    new LicenseItem('Material Design Icons · Apache 2.0', 'MaterialIcons-LICENSE.txt'),
    new LicenseItem('KaTeX · MIT', 'forum-rich/licenses/katex-LICENSE.txt'),
    new LicenseItem('Marked · MIT', 'forum-rich/licenses/marked-LICENSE.txt'),
    new LicenseItem('DOMPurify · Apache 2.0 / MPL 2.0', 'forum-rich/licenses/dompurify-LICENSE.txt'),
    new LicenseItem('PrismJS · MIT', 'forum-rich/licenses/prismjs-LICENSE.txt')]

  aboutToAppear(): void {
    const params = router.getParams() as SettingsRouteParams
    this.section = params?.section === 'proxy' || params?.section === 'licenses' || params?.section === 'credits' ? params.section : 'about'
    if (this.section === 'proxy') NetworkProxy.init().catch((e: Error) => { this.error = String(e) })
  }
  aboutToDisappear(): void { this.licenseRequest++ }
  onBackPress(): boolean {
    if (this.contributorsSheet) { this.contributorsSheet = false; return true }
    if (!this.licenseName) return false
    this.closeLicense(); return true
  }
  private closeLicense(): void { this.licenseRequest++; this.licenseName = ''; this.licenseText = []; this.error = '' }
  private openContributors(): void {
    this.contributorsTransition.open(() => { this.contributorsSheet = true }, () => this.getUIContext())
  }
  private title(): ResourceStr {
    return this.licenseName || (this.section === 'proxy' ? $r('app.string.settings_proxy') :
      this.section === 'licenses' ? $r('app.string.settings_licenses') :
      this.section === 'credits' ? $r('app.string.settings_original_libraries') : $r('app.string.ui_about_danxi'))
  }
  private async change(action: () => Promise<void>): Promise<void> {
    if (this.busy) return
    this.busy = true; this.error = ''
    try { await action(); HapticFeedback.selection() }
    catch (e) { this.error = AppLanguage.text($r('app.string.settings_save_failed'), this.languageRevision) + '\nDetails\n' + String(e) }
    finally { this.busy = false }
  }
  private async add(): Promise<void> {
    if (!this.input.trim()) {
      await this.change(async () => { await NetworkProxy.select(''); this.adding = false }); return
    }
    const parsed = NetworkProxy.parse(this.input)
    if (parsed === null) {
      this.error = AppLanguage.text($r('app.string.settings_proxy_invalid'), this.languageRevision); return
    }
    await this.change(async () => {
      if (!NetworkProxy.saved().includes(parsed.address)) await NetworkProxy.add(parsed.address)
      await NetworkProxy.select(parsed.address)
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.adding = false })
      this.input = ''
    })
  }
  private async open(address: string): Promise<void> {
    try { await BrowserLink.open(this.getUIContext().getHostContext() as common.UIAbilityContext, address) }
    catch (e) { this.error = AppLanguage.text($r('app.string.settings_open_failed'), this.languageRevision) + '\nDetails\n' + String(e) }
  }
  private async copyEmail(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, 'dev@danta.tech'))
      promptAction.showToast({ message: AppLanguage.text($r('app.string.settings_email_copied'), this.languageRevision) })
    } catch (e) { this.error = String(e) }
  }
  private async contact(): Promise<void> {
    try {
      await (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({
        action: 'ohos.want.action.sendToData', uri: 'mailto:dev@danta.tech?subject=DanXi%20HarmonyOS%20' + Constant.APP_VERSION })
    } catch (e) {
      this.error = AppLanguage.text($r('app.string.settings_email_unavailable'), this.languageRevision) + '\nDetails\n' + String(e)
    }
  }
  private async license(item: LicenseItem): Promise<void> {
    const request = ++this.licenseRequest
    this.error = ''; this.licenseName = item.name; this.licenseText = []
    try {
      const data = await this.getUIContext().getHostContext()!.resourceManager.getRawFileContent(item.file)
      const decoder = util.TextDecoder.create('utf-8')
      if (request === this.licenseRequest) this.licenseText = ForumContentParser.textBlocks(decoder.decodeWithStream(data))
    } catch (e) { if (request === this.licenseRequest) this.error = String(e) }
  }
  @Builder
  Heading(title: ResourceStr) {
    Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).width('100%')
  }
  @Builder
  Paragraph(text: ResourceStr) {
    Text(ReadableText.resource(text)).fontSize(14).lineHeight(22).lineBreakStrategy(LineBreakStrategy.GREEDY).fontColor(ThemeColors.textSecondary).width('100%')
  }
  @Builder
  Link(label: ResourceStr, action: () => void, icon: string = 'license') {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        SymbolGlyph(getSymbolIcon(icon)).fontSize(22).fontColor([ThemeColors.primary])
        Text(label).fontSize(15).fontColor(ThemeColors.primary).layoutWeight(1).textAlign(TextAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([ThemeColors.textHint])
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 44 }).padding({ top: 10, bottom: 10 })
      .backgroundColor(Color.Transparent).stateEffect(false).onClick(() => { HapticFeedback.selection(); action() })
  }
  @Builder
  ProxyChoice(address: string) {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 10 }) {
          Radio({ value: address || 'direct', group: 'http-proxy' }).checked(this.activeProxy === address)
            .hitTestBehavior(HitTestMode.None).width(22).height(22)
          Text(address || $r('app.string.settings_proxy_none')).fontSize(15).fontColor(ThemeColors.textPrimary)
            .layoutWeight(1).textAlign(TextAlign.Start).maxLines(2).wordBreak(WordBreak.BREAK_ALL)
        }.width('100%')
      }.layoutWeight(1).constraintSize({ minHeight: 52 }).padding({ left: 12, right: 8, top: 10, bottom: 10 })
        .backgroundColor(Color.Transparent).stateEffect(false).enabled(!this.busy)
        .onClick(() => { this.change(() => NetworkProxy.select(address)) })
      if (address) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([ThemeColors.error])
        }.width(40).height(40).margin({ right: 8 }).backgroundColor(Color.Transparent).enabled(!this.busy)
          .accessibilityText($r('app.string.settings_proxy_remove')).onClick(() => { this.change(() => NetworkProxy.remove(address)) })
      }
    }.width('100%')
  }
  @Builder
  ProxyContent() {
    this.Paragraph($r('app.string.settings_proxy_hint'))
    Column() {
      this.ProxyChoice('')
      ForEach(NetworkProxy.saved(this.savedProxies), (address: string) => {
        Divider().color(ThemeColors.divider).margin({ left: 16, right: 16 })
        this.ProxyChoice(address)
      }, (address: string) => address)
    }.width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
      
    if (this.adding) {
      Column({ space: 12 }) {
        TextInput({ text: this.input, placeholder: $r('app.string.settings_proxy_input') }).height(48).maxLength(255)
          .onChange((value: string) => { this.input = value }).onSubmit(() => { this.add() })
        Row({ space: 12 }) {
          FloatingActionButton({ label: $r('app.string.settings_cancel'), onAction: () => { this.adding = false; this.error = '' } }).layoutWeight(1)
          FloatingActionButton({ label: $r('app.string.settings_proxy_save'), actionEnabled: !this.busy,
            emphasized: true, onAction: () => { this.add() } }).layoutWeight(1)
        }
      }.padding(16).width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
        .transition(TransitionEffect.OPACITY)
    } else {
      FloatingActionButton({ label: $r('app.string.settings_proxy_add'), actionEnabled: !this.busy,
        onAction: () => { this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.adding = true }) } }).width('100%')
    }
    this.Paragraph($r('app.string.settings_proxy_scope'))
  }
  @Builder
  ContributorIdentity(person: ContributorCredit) {
    Row({ space: 8 }) {
      if (person.avatar !== null) {
        Image(person.avatar).width(34).height(34).borderRadius(17).clip(true).objectFit(ImageFit.Cover)
          .accessibilityLevel('no')
      } else {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(getSymbolIcon('person')).fontSize(20).fontColor([ThemeColors.textHint]).accessibilityLevel('no')
        }.width(34).height(34).borderRadius(17).backgroundColor($r('app.color.theme_bg_start'))
      }
      Column({ space: 2 }) {
        Text(person.name).fontSize(14).lineHeight(20).fontColor(ThemeColors.textPrimary)
          .width('100%').textAlign(TextAlign.Start).wordBreak(WordBreak.BREAK_ALL)
        Text(this.platforms(person.flutter, person.ios, person.harmony)).fontSize(11).lineHeight(16).fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.primary).width('100%').id('about-platform-' + person.identity)
        if (person.design) {
          Text(person.design === 'icon' ? $r('app.string.settings_credit_icon_design') : $r('app.string.settings_credit_art_design'))
            .fontSize(11).lineHeight(16).fontColor(ThemeColors.textSecondary).width('100%')
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Center)
  }
  private platforms(flutter: boolean, ios: boolean, harmony: boolean = false): string {
    const platforms: string[] = []
    if (flutter) platforms.push('Android')
    if (ios) platforms.push('iOS')
    if (harmony) platforms.push('HarmonyOS')
    return platforms.join(' · ')
  }
  @Builder
  Credits() {
    Column({ space: 10 }) {
      this.Heading($r('app.string.settings_thanks'))
      this.Paragraph($r('app.string.settings_thanks_merged'))
      this.Link($r('app.string.settings_original_libraries'), () => {
        router.pushUrl({ url: 'pages/SettingsUtilitiesPage', params: new SettingsRouteParams('credits') })
      })
      Divider().color(ThemeColors.divider).margin({ top: 2, bottom: 2 })
      this.Link($r('app.string.settings_app_developers'), () => { this.openContributors() }, 'person')
    }.padding(16).width('100%').alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
  }
  @Builder
  ContributorsContent() {
    Scroll(this.contributorsScroller) {
      Column({ space: 12 }) {
        Text(ReadableText.keepWords(AppLanguage.text($r('app.string.settings_contributors_merged'), this.languageRevision))).fontSize(13).lineHeight(20)
          .lineBreakStrategy(LineBreakStrategy.GREEDY).fontColor(ThemeColors.textSecondary).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.contributors, (person: ContributorCredit) => {
            if (person.url) {
              Button({ type: ButtonType.Normal }) { this.ContributorIdentity(person) }
                .width('50%').constraintSize({ minHeight: 80 }).padding({ top: 6, bottom: 6, left: 4, right: 4 })
                .id('about-contributor-' + person.identity).backgroundColor(Color.Transparent).stateEffect(false)
                .accessibilityText(person.name + ', ' + this.platforms(person.flutter, person.ios, person.harmony))
                .onClick(() => { HapticFeedback.selection(); this.open(person.url) })
            } else {
              Column() { this.ContributorIdentity(person) }
                .width('50%').constraintSize({ minHeight: 80 }).padding({ top: 6, bottom: 6, left: 4, right: 4 })
                .justifyContent(FlexAlign.Center).id('about-contributor-' + person.identity)
            }
          }, (person: ContributorCredit) => person.identity)
        }.width('100%').id('about-developers')
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 12, bottom: Math.max(20, px2vp(this.bottomPx)) + 12 })
    }.width('100%').height('100%').scrollBar(BarState.Off)
      .onTouch((event: TouchEvent) => { settleScrollTouch(this.contributorsScroller, event) })
  }
  @Builder
  HarmonyNotes() {
    Column({ space: 10 }) {
      this.Heading($r('app.string.settings_harmony_platform'))
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(Constant.APP_VERSION).fontSize(16).lineHeight(22).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary).maxLines(1).copyOption(CopyOptions.LocalDevice).id('about-harmony-version')
          Text(Constant.APP_RELEASE_STAGE).fontSize(11).lineHeight(16).fontColor(ThemeColors.textSecondary).maxLines(1)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(6)
            .backgroundColor($r('app.color.input_surface')).id('about-harmony-stage')
        }.width('100%').alignItems(VerticalAlign.Center)
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text($r('app.string.settings_harmony_build', Constant.APP_BUILD_VERSION)).fontSize(12).lineHeight(20)
            .fontColor(ThemeColors.textSecondary).margin({ right: 16 }).id('about-harmony-build')
          Text($r('app.string.settings_harmony_upgrade', Constant.APP_VERSION_CODE)).fontSize(12).lineHeight(20)
            .fontColor(ThemeColors.textSecondary).id('about-harmony-upgrade')
        }.width('100%')
        Text($r('app.string.settings_harmony_note')).fontSize(12).lineHeight(18)
          .fontColor(ThemeColors.textSecondary).width('100%').id('about-harmony-note')
      }.width('100%').alignItems(HorizontalAlign.Start).id('about-harmony-footer')
      Divider().color(ThemeColors.divider).margin({ top: 2 })
      this.Link($r('app.string.settings_harmony_project'), () => { this.open(AboutCredits.HARMONY_PROJECT_URL) }, 'proxy')
      this.Link($r('app.string.settings_harmony_contributors'), () => { this.open(AboutCredits.HARMONY_CONTRIBUTORS_URL) }, 'person')
    }.padding(16).width('100%').alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
  }
  @Builder
  OriginalLibraryContent() {
    this.Paragraph($r('app.string.settings_original_libraries_hint'))
    Column() {
      ForEach(this.originalLibraries, (library: LibraryCredit, index: number) => {
        if (index > 0) Divider().color(ThemeColors.divider)
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(library.name).fontSize(15).lineHeight(21).fontColor(ThemeColors.textPrimary).width('100%')
              Text(library.license + ' · ' + this.platforms(library.flutter, library.ios)).fontSize(12).lineHeight(18)
                .fontColor(ThemeColors.textSecondary).width('100%')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph(getSymbolIcon('proxy')).fontSize(20).fontColor([ThemeColors.primary])
          }.width('100%').alignItems(VerticalAlign.Center)
        }.padding({ top: 12, bottom: 12 }).width('100%').backgroundColor(Color.Transparent).stateEffect(false)
          .id('about-library-' + library.name).onClick(() => { HapticFeedback.selection(); this.open(library.url) })
      }, (library: LibraryCredit) => library.name)
    }.padding({ left: 16, right: 16 }).width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
  }
  @Builder
  AboutContent() {
    Column({ space: 12 }) {
      Row({ space: 14 }) {
        Image($r('app.media.foreground')).width(64).height(64).objectFit(ImageFit.Contain)
        Column({ space: 6 }) {
          Text(Constant.APP_NAME).fontSize(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Text('HarmonyOS · ' + Constant.APP_DISPLAY_VERSION).fontSize(13).fontColor(ThemeColors.textSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      this.Heading($r('app.string.settings_intro'))
      this.Paragraph($r('app.string.settings_description'))
      this.Paragraph($r('app.string.settings_harmony_intro'))
    }.padding(16).width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
    this.HarmonyNotes()
    this.Credits()
    Column({ space: 8 }) {
      this.Heading($r('app.string.settings_legal'))
      this.Paragraph($r('app.string.settings_legal_text'))
      this.Link($r('app.string.settings_privacy'), () => { this.open('https://danxi.fduhole.com/privacy') })
      Divider().color(ThemeColors.divider)
      this.Link($r('app.string.settings_licenses'), () => { router.pushUrl({ url: 'pages/SettingsUtilitiesPage', params: new SettingsRouteParams('licenses') }) })
    }.padding(16).width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
    Column({ space: 8 }) {
      this.Heading($r('app.string.settings_contact'))
      Text('dev@danta.tech').fontSize(16).fontColor(ThemeColors.primary).copyOption(CopyOptions.LocalDevice).width('100%')
      Text(ReadableText.keepWords(AppLanguage.text($r('app.string.settings_contact_hint'), this.languageRevision)))
        .fontSize(14).lineHeight(23).fontColor(ThemeColors.textSecondary).width('100%')
        .lineBreakStrategy(LineBreakStrategy.GREEDY)
      this.Link($r('app.string.settings_email'), () => { this.contact() }, 'mail')
      this.Link($r('app.string.settings_copy_email'), () => { this.copyEmail() }, 'copy')
      Divider().color(ThemeColors.divider)
      this.Link($r('app.string.settings_project'), () => { this.open('https://danxi.fduhole.com') }, 'proxy')
      this.Link($r('app.string.settings_source'), () => { this.open(AboutCredits.PROJECT_URL) }, 'proxy')
    }.padding(16).width('100%').backgroundColor($r('app.color.surface_fallback')).borderRadius(20)
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll(this.touchScroller) {
        Column({ space: 14 }) {
          if (this.section === 'proxy') this.ProxyContent()
          else if (this.section === 'about') this.AboutContent()
          else if (this.section === 'credits') this.OriginalLibraryContent()
          else if (this.licenseName) {
            ForEach(this.licenseText, (text: string, index: number) => {
              Text(text).fontSize(13).lineHeight(20).fontColor(ThemeColors.textPrimary).width('100%').copyOption(CopyOptions.LocalDevice)
            }, (text: string, index: number) => String(index))
          } else {
            this.Paragraph($r('app.string.settings_license_hint'))
            Column() {
              ForEach(this.licenses, (item: LicenseItem) => {
                this.Link(item.name, () => { this.license(item) })
                Divider().color(ThemeColors.divider)
              }, (item: LicenseItem) => item.file)
            }.padding(16).backgroundColor($r('app.color.surface_fallback')).borderRadius(20).width('100%')
          }
          if (this.error) {
            ErrorNotice({ message: this.error, controlId: 'settingsutilitiespage-diagnostics', textSize: 13, textColor: ThemeColors.error }).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: ThemeDimens.cardGutter, right: ThemeDimens.cardGutter, top: px2vp(this.topPx) + 72, bottom: px2vp(this.bottomPx) + 24 })
      }.width('100%').height('100%').scrollBar(BarState.Off).onTouch((event: TouchEvent) => { settleScrollTouch(this.touchScroller, event) }).align(Alignment.Top)
      TopFade({ extent: px2vp(this.topPx) + 56 })
      Row({ space: 18 }) {
        FloatingActionButton({ label: $r('app.string.settings_back'), icon: 'back', controlHeight: 48, onAction: () => { if (this.licenseName) this.closeLicense(); else router.back() }  }).width(48)
        Text(this.title()).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%').height(56).padding({ left: 16, right: 16 }).margin({ top: px2vp(this.topPx) })
    }.width('100%').height('100%').backgroundColor($r('app.color.theme_bg_start'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.contributorsSheet, this.ContributorsContent(), this.contributorsTransition.options(this.contributorsSheet, {
        height: '85%', title: { title: $r('app.string.settings_app_developers') }, showClose: true, dragBar: true,
        backgroundColor: nativeFloatingBackground(this.materialRevision), systemMaterial: adaptiveMaterial(this.materialRevision) }))
  }
}
