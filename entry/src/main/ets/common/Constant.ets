/**
 * Application constants for DanXi HarmonyOS port.
 * Ported from the original Flutter DanXi project.
 */

export class Constant {
  // App info
  static readonly APP_NAME: string = '旦夕'
  static readonly APP_VERSION: string = '0.1.33.30'
  static readonly APP_VERSION_CODE: number = 1000124
  static readonly APP_BUILD_VERSION: string = '125'
  static readonly APP_RELEASE_STAGE: string = 'Alpha'
  static readonly APP_DISPLAY_VERSION: string = Constant.APP_VERSION + ' ' + Constant.APP_RELEASE_STAGE
  static readonly APP_DIAGNOSTIC_HEADER: string = 'DanXi HarmonyOS ' + Constant.APP_DISPLAY_VERSION +
    ' build ' + Constant.APP_BUILD_VERSION + ' (versionCode ' + Constant.APP_VERSION_CODE + ')'

  // ── Backend endpoints ──
  // Mirrors lib/common/constant.dart:87-96 of the upstream Flutter project.
  // NOTE: the forum/tree-hole service is fduhole.com (Fudan), NOT treehole.pku.edu.cn.
  static readonly UIS_URL: string = 'https://uis.fudan.edu.cn/authserver/login'
  static readonly UIS_HOST: string = 'uis.fudan.edu.cn'
  static readonly FDU_UMS_URL: string = 'https://ums.fudan.edu.cn'
  static readonly FDU_AAO_URL: string = 'https://jwc.fudan.edu.cn'
  static readonly FDU_ELE_URL: string = 'https://ecard.fudan.edu.cn'

  // Forum (Tree Hole) API
  static readonly FORUM_BASE_URL: string = 'https://forum.fduhole.com/api'
  static readonly FORUM_BASE_URL_LEGACY: string = 'https://www.fduhole.com/api'
  static readonly FORUM_API_VERSION: string = 'v1'

  // Auth API (forum account login / refresh / register)
  static readonly AUTH_BASE_URL: string = 'https://auth.fduhole.com/api'

  // Image CDN
  static readonly IMAGE_BASE_URL: string = 'https://image.fduhole.com'

  // DanKe (Course Review) API
  static readonly DANKE_BASE_URL: string = 'https://danke.fduhole.com/api'

  // Client identity sent as User-Agent, matching upstream constant.dart:118
  static readonly USER_AGENT: string =
    'Danta/' + Constant.APP_VERSION + 'b' + Constant.APP_VERSION_CODE + ' (HarmonyOS; ' + Constant.APP_VERSION + ')'

  // Forum paging
  static readonly POST_COUNT_PER_PAGE: number = 10
  static readonly SPECIAL_DIVISION_FOR_CURRICULUM: string = '课评'

  // Storage keys
  static readonly KEY_USER_INFO: string = 'user_info'
  static readonly KEY_LOGIN_TOKEN: string = 'login_token'
  static readonly KEY_FORUM_TOKEN: string = 'forum_token'
  static readonly KEY_THEME_MODE: string = 'theme_mode'
  static readonly KEY_LANGUAGE: string = 'preferred_language'
  static readonly KEY_USE_WEBVPN: string = 'use_webvpn'
  static readonly KEY_DASHBOARD_ORDER: string = 'dashboard_order'
  static readonly KEY_LAST_LOGIN_TIME: string = 'last_login_time'
  static readonly KEY_IS_GUEST: string = 'is_guest'
  /** AppStorage flag the tree-hole pages watch to re-run their loaders. */
  static readonly KEY_FORUM_LOGGED_IN: string = 'forum_logged_in'
  /**
   * Status-bar height in px, published by EntryAbility once
   * setWindowLayoutFullScreen(true) has been applied.
   *
   * That call removes the app from the system's safe-area layout, so nothing
   * keeps page content clear of the status bar any more. Consumers convert it
   * with px2vp() and pad their top edge by it.
   */
  static readonly KEY_STATUS_BAR_INSET_PX: string = 'status_bar_inset_px'
  static readonly KEY_BOTTOM_BAR_INSET_PX: string = 'bottom_bar_inset_px'
  static readonly KEY_FORUM_FOLD_BEHAVIOR: string = 'forum_fold_behavior'

  // Dashboard feature IDs
  static readonly FEATURE_ANNOUNCEMENT: string = 'announcement'
  static readonly FEATURE_BUS: string = 'bus'
  static readonly FEATURE_EMPTY_CLASSROOM: string = 'empty_classroom'
  static readonly FEATURE_EXAM: string = 'exam'
  static readonly FEATURE_GPA: string = 'gpa'
  static readonly FEATURE_ACADEMIC: string = 'academic'
  static readonly FEATURE_COURSE_REVIEW: string = 'course_review'
  static readonly FEATURE_FORUM: string = 'forum'
  static readonly FEATURE_TIMETABLE: string = 'timetable'
  static readonly FEATURE_CELEBRATION: string = 'celebration'
  static readonly FEATURE_CARD: string = 'card'
  static readonly FEATURE_EVALUATION: string = 'evaluation'
  static readonly FEATURE_CAMPUS_ACCESS: string = 'campus_access'
  static readonly FEATURE_SPORTS: string = 'sports'
  static readonly FEATURE_LIFE_CODE: string = 'life_code'
  static readonly FEATURE_DEVELOPER_NOTICE: string = 'developer_notice'
  static readonly FEATURE_DINING: string = 'dining'
  static readonly FEATURE_LIBRARY: string = 'library'
  static readonly FEATURE_LIBRARY_BOOKS: string = 'library_books'
  static readonly FEATURE_ELECTRICITY: string = 'electricity'

  // Learning/academic information first, then daily living and mobility.
  // Each group uses balanced mixed sizes; low-frequency project news is last.
  static readonly DEFAULT_DASHBOARD_ORDER: string[] = [
    Constant.FEATURE_TIMETABLE,
    Constant.FEATURE_ACADEMIC,
    Constant.FEATURE_EMPTY_CLASSROOM,
    Constant.FEATURE_LIBRARY,
    Constant.FEATURE_LIBRARY_BOOKS,
    Constant.FEATURE_ANNOUNCEMENT,
    Constant.FEATURE_CARD,
    Constant.FEATURE_ELECTRICITY,
    Constant.FEATURE_DINING,
    Constant.FEATURE_SPORTS,
    Constant.FEATURE_BUS,
    Constant.FEATURE_CAMPUS_ACCESS,
    Constant.FEATURE_LIFE_CODE,
    Constant.FEATURE_DEVELOPER_NOTICE,
  ]

  // Bus lines
  static readonly BUS_LINES: string[] = [
    '邯郸校区 → 枫林校区',
    '枫林校区 → 邯郸校区',
    '邯郸校区 → 张江校区',
    '张江校区 → 邯郸校区',
    '邯郸校区 → 江湾校区',
    '江湾校区 → 邯郸校区',
  ]

  // Campus locations
  static readonly CAMPUS_NAMES: string[] = ['邯郸', '江湾', '枫林', '张江']

  // Colors
  static readonly PRIMARY_COLOR: string = '#4A90D9'
  static readonly ACCENT_COLOR: string = '#FF6B6B'
  static readonly BACKGROUND_COLOR: string = '#F5F5F5'
  static readonly CARD_BACKGROUND: string = '#FFFFFF'
  static readonly TEXT_PRIMARY: string = '#333333'
  static readonly TEXT_SECONDARY: string = '#666666'
  static readonly TEXT_HINT: string = '#999999'
  static readonly DIVIDER_COLOR: string = '#E0E0E0'
}
