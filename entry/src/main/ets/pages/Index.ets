import { HapticFeedback } from '../common/HapticFeedback'
import { AppLanguage } from '../common/AppLanguage'
import { floatingMaterial, nativeFloatingBackground } from '../common/AdaptiveMaterial'
/**
 * Main Index Page - Campus, Timetable, Forum, Reviews and Settings navigation.
 * Full-height Tabs with the native floating TabBar and system-managed material.
 * Background and scrolling content extend beneath the bottom controls.
 * Ported from lib/page/home_page.dart
 */

import { router, SymbolGlyphModifier } from '@kit.ArkUI'
import { AppState } from '../common/AppState'
import { Constant } from '../common/Constant'
import { ThemeColors } from '../common/Theme'
import { getSymbolIcon } from '../common/DanXiIcons'
import { DashboardPage } from './DashboardPage'
import { ForumPage } from './ForumPage'
import { SettingsPage } from './SettingsPage'
import { TimetablePage } from './TimetablePage'
import { CampusUtilityPage } from './CampusUtilityPage'
import { containsMaterialPoint, MaterialBounds, MaterialTouchGuard, nativeTabBarBounds } from '../common/MaterialTouchBounds'

@Entry
@Component
struct Index {
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink('campus_layout_editing') campusLayoutEditing: boolean = false
  @StorageLink('main_tab_request') @Watch('requestedTab') requested: number = 0
  @StorageLink('desktop_feature_request') @Watch('desktopRequested') desktopRequest: string = ''
  private tabsController: TabsController = new TabsController()
  private refreshTimer: number = -1
  @StorageLink(Constant.KEY_BOTTOM_BAR_INSET_PX) bottomBarInsetPx: number = 0
  @State private pointFeedback: boolean = true
  private touchGuard: MaterialTouchGuard = new MaterialTouchGuard()
  private materialBounds: MaterialBounds | null = null

  aboutToAppear(): void {
    AppStorage.setOrCreate<number>('main_active_tab', 0)
    // AppState is restored by EntryAbility before this page loads, so these
    // reads are reliable.
    // clear()+pushUrl, not replaceUrl: the ArkUI-X cross-platform plugin
    // rejects replaceUrl outright (error 11706007 "can't support crossplatform
    // application"), and it is deprecated in this SDK anyway.
    if (!AppState.isLoggedIn() && !AppState.isGuest()) {
      router.clear()
      router.pushUrl({ url: 'pages/LoginPage' })
    }
  }

  requestedTab(): void {
    const index: number = this.requested
    if (index < 0 || index > 4) return
    // Consume this command. A later tap on the same destination must be a new
    // StorageLink change even after the user has returned through the tab bar.
    this.requested = -1
    this.tabsController.changeIndex(index)
  }

  onBackPress(): boolean {
    if (AppStorage.get<number>('main_active_tab') !== 3 || !AppStorage.get<boolean>('evaluation_detail_open')) return false
    AppStorage.setOrCreate<number>('evaluation_back_request', (AppStorage.get<number>('evaluation_back_request') ?? 0) + 1)
    return true
  }

  aboutToDisappear(): void { if (this.refreshTimer >= 0) clearTimeout(this.refreshTimer) }
  onPageShow(): void { AppStorage.setOrCreate<boolean>('main_route_visible', true); this.desktopRequested() }
  onPageHide(): void { AppStorage.setOrCreate<boolean>('main_route_visible', false) }

  private desktopRequested(): void {
    if (!this.desktopRequest || (!AppState.isLoggedIn() && !AppState.isGuest())) return
    if (AppStorage.get<boolean>('main_route_visible') === false) {
      router.back({ url: 'pages/Index' }); return
    }
    const feature = this.desktopRequest; this.desktopRequest = ''
    AppStorage.setOrCreate<number>('main_tab_request', feature === 'timetable' ? 1 : 0)
    if (feature !== 'timetable') AppStorage.setOrCreate<string>('campus_feature_request', feature)
  }

  private activateTab(index: number): void {
    if (AppStorage.get<number>('main_active_tab') !== index) HapticFeedback.selection()
    AppStorage.setOrCreate<number>('main_active_tab', index)
  }

  private materialTouch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel || event.touches.length > 1) {
      this.pointFeedback = this.touchGuard.cancel()
      return
    }
    if (event.type === TouchType.Down) {
      this.materialBounds = nativeTabBarBounds(this.getUIContext(), 'danxi-main-tabs')
      if (this.materialBounds !== null) {
        console.info('[DanXiMaterialTouch] tabBar vp=' + this.materialBounds.x + ',' + this.materialBounds.y + ',' +
          this.materialBounds.width + ',' + this.materialBounds.height)
      }
    }
    const previous: boolean = this.pointFeedback
    for (const point of event.changedTouches) {
      const inside: boolean = this.materialBounds !== null &&
        containsMaterialPoint(this.materialBounds, point.x, point.y)
      if (event.type === TouchType.Down) this.pointFeedback = this.touchGuard.down(point.id, inside)
      else if (event.type === TouchType.Move) this.pointFeedback = this.touchGuard.move(point.id, inside)
      else if (event.type === TouchType.Up) this.pointFeedback = this.touchGuard.up(point.id)
    }
    if (previous !== this.pointFeedback) console.info('[DanXiMaterialTouch] tabBar pointFeedback=' + this.pointFeedback)
  }

  private tabStyle(icon: string, label: Resource): BottomTabBarStyle {
    const symbol: TabBarSymbol = {
      normal: new SymbolGlyphModifier(getSymbolIcon(icon)).fontSize(22)
        .fontColor([ThemeColors.textPrimary]),
      selected: new SymbolGlyphModifier(getSymbolIcon(icon)).fontSize(22)
        .fontColor([ThemeColors.tabActive])
    }
    // Native items receive the floating bar's selection, light and pressure
    // feedback. A custom click handler would switch twice and interrupt it.
    return BottomTabBarStyle.of(symbol, AppLanguage.text(label, this.languageRevision))
      .labelStyle({ font: { size: 11 }, selectedColor: ThemeColors.tabActive,
        unselectedColor: ThemeColors.textPrimary })
      .padding({ top: 6, bottom: 6, left: 4, right: 4 })
  }

  build() {
    Stack() {
      Column().width('100%').height('100%')
        .linearGradient({ angle: 135, colors: [[ThemeColors.bgStart, 0], [ThemeColors.bgEnd, 1]] })
      Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
        TabContent() { DashboardPage() }.tabBar(this.tabStyle('home', $r('app.string.ui_campus')))
        TabContent() { TimetablePage() }.tabBar(this.tabStyle('timetable', $r('app.string.ui_timetable')))
        TabContent() { ForumPage() }.tabBar(this.tabStyle('forum', $r('app.string.ui_forum')))
        TabContent() { CampusUtilityPage({ initialFeature: 'evaluation', mainTab: true }) }.tabBar(this.tabStyle('evaluation', $r('app.string.feature_evaluation')))
        TabContent() { SettingsPage() }.tabBar(this.tabStyle('person', $r('app.string.ui_me')))
      }
      // Native floating mode provides a real material host and keeps content full-screen.
      .barHeight(60).barOverlap(true)
      .scrollable(!this.campusLayoutEditing)
      .barBackgroundColor(nativeFloatingBackground(this.materialRevision))
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle({
        barWidth: { smallBarWidth: 340, mediumBarWidth: 360, largeBarWidth: 400 },
        barBottomMargin: Math.max(16, px2vp(this.bottomBarInsetPx)) + 12,
        // Fade only below the capsule. Darkening its sampled backdrop makes
        // even the system's transparent material look like a black plate.
        maskHeight: Math.max(16, px2vp(this.bottomBarInsetPx)) + 12,
        maskColor: $r('app.color.bottom_fade_edge'),
        systemMaterial: floatingMaterial(this.materialRevision, this.pointFeedback)
      })
      .id('danxi-main-tabs')
      .onTouch((event: TouchEvent): void => { this.materialTouch(event) })
      .onSizeChange((_oldSize: SizeOptions, _size: SizeOptions): void => {
        this.materialBounds = null
        this.pointFeedback = this.touchGuard.cancel()
      })
      .animationDuration(420).animationCurve(Curve.Friction)
      .animationMode(AnimationMode.CONTENT_FIRST)
      .onChange((index: number): void => {
        // Keep data-driven page rebuilds out of the native transition. The
        // timer is a fallback for devices with reduced/disabled animations.
        if (this.refreshTimer >= 0) clearTimeout(this.refreshTimer)
        this.refreshTimer = setTimeout(() => { this.activateTab(index) }, 460)
      })
      .onAnimationStart((from: number, to: number): void => {
        console.info('[DanXiTabs] animationStart ' + from + '>' + to)
      })
      .onAnimationEnd((index: number): void => {
        console.info('[DanXiTabs] animationEnd ' + index)
        if (this.refreshTimer >= 0) clearTimeout(this.refreshTimer)
        this.activateTab(index)
      })
      .width('100%').height('100%').backgroundColor(Color.Transparent)
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
