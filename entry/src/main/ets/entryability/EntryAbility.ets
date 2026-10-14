import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferencesUtil } from '../util/PreferencesUtil';
import { Appearance } from '../common/Appearance';
import { AppState } from '../common/AppState';
import { Constant } from '../common/Constant';
import { AppLanguage } from '../common/AppLanguage';
import { CalendarRepository } from '../repository/CalendarRepository';
import { AcademicCalendar } from '../common/AcademicCalendar';
import { ForumLocalState } from '../common/ForumLocalState';
import { NetworkProxy } from '../common/NetworkProxy';
import { HapticFeedback } from '../common/HapticFeedback';
import { ClassroomPreference } from '../common/ClassroomPreference';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private updateInsets = (): void => {
    if (this.mainWindow === null) return;
    let top: number = 0;
    let bottom: number = 0;
    try {
      const system = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      top = system.topRect.height;
      bottom = system.bottomRect.height;
    } catch (e) {
      hilog.warn(DOMAIN, 'testTag', 'Could not read system insets');
    }
    try {
      const navigation = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      bottom = Math.max(bottom, navigation.bottomRect.height);
    } catch (e) {
      // Some cross-platform windows expose only TYPE_SYSTEM.
    }
    try {
      const cutout = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      top = Math.max(top, cutout.topRect.height);
    } catch (e) {
      // Retain system insets when cutout information is unavailable.
    }
    AppStorage.setOrCreate<number>(Constant.KEY_STATUS_BAR_INSET_PX, top);
    AppStorage.setOrCreate<number>(Constant.KEY_BOTTOM_BAR_INSET_PX, bottom);
  };
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate<number>('app_font_scale', this.context.config.fontSizeScale ?? 1);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Everything below must finish BEFORE pages/Index loads:
    //  - the avoid-area read, because Index sizes its top inset from it and a
    //    late value renders one frame with the header under the status bar;
    //  - AppState, because Index's aboutToAppear reads isLoggedIn()/isGuest()
    //    synchronously, and an un-awaited init let those reads race the
    //    preferences I/O so a returning user was bounced to the login page.
    this.applyImmersiveLayout(windowStage)
      .then(() => this.initAppState())
      .then(() => {
        this.loadMainPage(windowStage);
      })
      .catch((e: BusinessError) => {
        // Show the UI anyway — Index degrades to the login page.
        hilog.error(DOMAIN, 'testTag', 'Startup preparation failed: %{public}s', e.message);
        this.loadMainPage(windowStage);
      });
  }

  /**
   * Full-screen layout with transparent system bars, plus the status-bar inset.
   *
   * setWindowLayoutFullScreen(true) takes the app OUT of the system's safe-area
   * layout. Nothing keeps content clear of the status bar after that, and the
   * campus page header duly drew inside the bar: '校园' rendered at y≈45px
   * while the status bar occupied y 0..131, landing on top of the clock.
   *
   * So the top avoid-area height is published to AppStorage here and applied as
   * padding by the page shell. It is stored in PX because getWindowAvoidArea
   * returns px; consumers convert with px2vp().
   */
  private applyImmersiveLayout(windowStage: window.WindowStage): Promise<void> {
    return windowStage.getMainWindow()
      .then(async (win: window.Window) => {
        this.mainWindow = win;
        await win.setWindowLayoutFullScreen(true);
        this.updateInsets();
        win.on('avoidAreaChange', this.updateInsets);
        return win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: '#FF000000',
          navigationBarContentColor: '#FF000000',
        });
      })
      .catch((e: BusinessError) => {
        hilog.warn(DOMAIN, 'testTag', 'Failed to apply immersive layout: %{public}s', e.message);
      });
  }

  private loadMainPage(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err && err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'Succeeded in loading the content.');
      AppLanguage.onWindowReady();
      Appearance.onWindowReady().catch((e: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to apply the saved appearance: %{public}s', e.message);
      });
    });
  }

  private async initAppState(): Promise<void> {
    // Restore local post visibility before any forum feed is constructed.
    await PreferencesUtil.getInstance().init(this.context);
    await NetworkProxy.init();
    await HapticFeedback.init();
    await ClassroomPreference.init();
    await ForumLocalState.restore();
    CalendarRepository.init(this.context.cacheDir);
    await AppState.init();
    await AppLanguage.init(this.context);
    if (this.mainWindow !== null) await Appearance.init(this.context, this.mainWindow);
    hilog.info(DOMAIN, 'testTag', 'App state initialized (prefs ready: %{public}s)',
      String(PreferencesUtil.getInstance().isReady()));
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageDestroy(): void {
    AppLanguage.onWindowDestroyed();
    Appearance.onWindowDestroyed();
    if (this.mainWindow !== null) {
      try { this.mainWindow.off('avoidAreaChange', this.updateInsets); } catch (e) {}
      this.mainWindow = null;
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onConfigurationUpdate(): void {
    AppStorage.setOrCreate<number>('app_font_scale', this.context.config.fontSizeScale ?? 1);
    AppLanguage.syncSystem();
    Appearance.updateBars().catch(() => {});
  }

  onForeground(): void {
    AppStorage.setOrCreate<boolean>('app_foreground', true);
    if (PreferencesUtil.getInstance().isReady()) AcademicCalendar.publish();
    AppLanguage.syncSystem();
    Appearance.updateBars().catch(() => {});
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    AppStorage.setOrCreate<boolean>('app_foreground', false);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
