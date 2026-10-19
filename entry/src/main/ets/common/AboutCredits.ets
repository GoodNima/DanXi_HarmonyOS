export class AcknowledgementRun {
  text: string
  url: string
  link: boolean
  constructor(text: string, url: string = '', link: boolean = false) {
    this.text = text; this.url = url; this.link = link
  }
}

export class DeveloperCredit {
  name: string
  avatar: Resource
  url: string
  constructor(name: string, avatar: Resource, url: string) {
    this.name = name; this.avatar = avatar; this.url = url
  }
}

export class ContributorCredit {
  identity: string
  name: string
  avatar: Resource | null
  url: string
  flutter: boolean
  ios: boolean
  harmony: boolean
  design: string
  constructor(developer: DeveloperCredit, flutter: boolean, ios: boolean, harmony: boolean = false) {
    this.identity = AboutCredits.identity(developer.name)
    this.name = developer.name; this.avatar = developer.avatar; this.url = developer.url
    this.flutter = flutter; this.ios = ios; this.harmony = harmony; this.design = ''
  }
}

export class LibraryCredit {
  name: string
  url: string
  license: string
  flutter: boolean
  ios: boolean
  constructor(name: string, url: string, license: string, flutter: boolean, ios: boolean) {
    this.name = name; this.url = url; this.license = license; this.flutter = flutter; this.ios = ios
  }
}

/** Original acknowledgement links and bundled developer portraits; no network on render. */
export class AboutCredits {
  static readonly PROJECT_URL: string = 'https://github.com/DanXi-Dev/DanXi'
  static readonly CONTRIBUTORS_URL: string = 'https://github.com/DanXi-Dev/DanXi/graphs/contributors'
  static readonly IOS_PROJECT_URL: string = 'https://github.com/DanXi-Dev/DanXi-swift'
  static readonly IOS_CONTRIBUTORS_URL: string = 'https://github.com/DanXi-Dev/DanXi-swift/graphs/contributors'
  static readonly IOS_FILING_URL: string = 'https://beian.miit.gov.cn/'
  static readonly HARMONY_PROJECT_URL: string = 'https://github.com/GoodNima/DanXi_HarmonyOS'
  static readonly HARMONY_CONTRIBUTORS_URL: string = 'https://github.com/GoodNima/DanXi_HarmonyOS/graphs/contributors'
  static readonly HARMONY_PROFILE_URL: string = 'https://github.com/GoodNima'
  /** Explicit aliases verified against the original profile and iOS portrait's GitHub user ID. */
  static identity(name: string): string {
    const normalized = name.toLowerCase()
    return normalized === 'ivan fei' || normalized === 'ivanfei' ? 'ivanfei-1' : normalized
  }
  static contributors(includeHarmony: boolean = true): ContributorCredit[] {
    const merged: ContributorCredit[] = []
    for (const developer of AboutCredits.developers()) merged.push(new ContributorCredit(developer, true, false))
    for (const developer of AboutCredits.iosDevelopers()) {
      const existing = merged.find((person: ContributorCredit): boolean => person.identity === AboutCredits.identity(developer.name))
      if (existing) existing.ios = true
      else merged.push(new ContributorCredit(developer, false, true))
    }
    // Design acknowledgements share this roster so a person is never listed twice.
    const artists: AcknowledgementRun[] = [
      new AcknowledgementRun('Ivan Fei', 'https://github.com/ivanfei-1'),
      new AcknowledgementRun('MSapphire', 'https://www.xiaohongshu.com/user/profile/6575475f000000001902d794'),
      new AcknowledgementRun('Lin2510'), new AcknowledgementRun('zzz111')
    ]
    for (let index = 0; index < artists.length; index++) {
      const artist = artists[index]
      let person = merged.find((entry: ContributorCredit): boolean => entry.identity === AboutCredits.identity(artist.text))
      if (!person) {
        person = new ContributorCredit(new DeveloperCredit(artist.text, $r('sys.symbol.person'), artist.url), true, false)
        person.avatar = null
        merged.push(person)
      }
      person.flutter = true
      if (!person.url) person.url = artist.url
      person.design = index === 0 ? 'icon' : 'art'
    }
    if (includeHarmony) merged.push(new ContributorCredit(
      new DeveloperCredit('GoodNima', $r('app.media.credit_goodnima'), AboutCredits.HARMONY_PROFILE_URL), false, false, true))
    return merged.sort((a: ContributorCredit, b: ContributorCredit): number => a.identity < b.identity ? -1 : a.identity > b.identity ? 1 : 0)
  }
  static acknowledgement(markdown: string): AcknowledgementRun[] {
    const runs: AcknowledgementRun[] = []
    const links = /\[([^\]]+)\]\(([^)]*)\)/g
    let offset = 0
    let match = links.exec(markdown)
    while (match !== null) {
      if (match.index > offset) runs.push(new AcknowledgementRun(markdown.substring(offset, match.index)))
      runs.push(new AcknowledgementRun(match[1], match[2], true))
      offset = match.index + match[0].length
      match = links.exec(markdown)
    }
    if (offset < markdown.length) runs.push(new AcknowledgementRun(markdown.substring(offset)))
    return runs
  }
  static developers(): DeveloperCredit[] {
    return [
      new DeveloperCredit('w568w', $r('app.media.credit_01'), 'https://github.com/w568w'),
      new DeveloperCredit('singularity-s0', $r('app.media.credit_02'), 'https://github.com/singularity-s0'),
      new DeveloperCredit('KYLN24', $r('app.media.credit_03'), 'https://github.com/KYLN24'),
      new DeveloperCredit('hasbai', $r('app.media.credit_04'), 'https://github.com/hasbai'),
      new DeveloperCredit('Dest1n1', $r('app.media.credit_05'), 'https://github.com/dest1n1s'),
      new DeveloperCredit('Frankstein73', $r('app.media.credit_06'), 'https://github.com/Frankstein73'),
      new DeveloperCredit('Ivan Fei', $r('app.media.credit_07'), 'https://github.com/ivanfei-1'),
      new DeveloperCredit('Boreas618', $r('app.media.credit_08'), 'https://github.com/Boreas618'),
      new DeveloperCredit('JingYiJun', $r('app.media.credit_09'), 'https://github.com/JingYiJun'),
      new DeveloperCredit('fsy2001', $r('app.media.credit_10'), 'https://github.com/fsy2001'),
      new DeveloperCredit('koowz', $r('app.media.credit_11'), 'https://github.com/koowz'),
      new DeveloperCredit('HydrogenC', $r('app.media.credit_12'), 'https://github.com/HydrogenC'),
      new DeveloperCredit('sseu-buhzzi', $r('app.media.credit_13'), 'https://github.com/sseu-buhzzi')
    ]
  }
  /** Names and alphabetical order match native iOS credits; portraits are bundled locally. */
  static iosDevelopers(): DeveloperCredit[] {
    return [
      new DeveloperCredit('Boreas618', $r('app.media.ios_credit_01'), ''),
      new DeveloperCredit('Caster-L', $r('app.media.ios_credit_02'), ''),
      new DeveloperCredit('Dest1n1', $r('app.media.ios_credit_03'), ''),
      new DeveloperCredit('Frankstein73', $r('app.media.ios_credit_04'), ''),
      new DeveloperCredit('fsy2001', $r('app.media.ios_credit_05'), ''),
      new DeveloperCredit('hasbai', $r('app.media.ios_credit_06'), ''),
      new DeveloperCredit('ivanfei', $r('app.media.ios_credit_07'), ''),
      new DeveloperCredit('JingYiJun', $r('app.media.ios_credit_08'), ''),
      new DeveloperCredit('kachrel', $r('app.media.ios_credit_09'), ''),
      new DeveloperCredit('Kirisame-Official', $r('app.media.ios_credit_10'), ''),
      new DeveloperCredit('kyln24', $r('app.media.ios_credit_11'), ''),
      new DeveloperCredit('Linn3a', $r('app.media.ios_credit_12'), ''),
      new DeveloperCredit('MSapphire', $r('app.media.ios_credit_13'), ''),
      new DeveloperCredit('NanshineLoong', $r('app.media.ios_credit_14'), ''),
      new DeveloperCredit('PinappleUnderTheSea', $r('app.media.ios_credit_15'), ''),
      new DeveloperCredit('ppolariss', $r('app.media.ios_credit_16'), ''),
      new DeveloperCredit('ryanhe312', $r('app.media.ios_credit_17'), ''),
      new DeveloperCredit('Serenii02', $r('app.media.ios_credit_18'), ''),
      new DeveloperCredit('shdancer', $r('app.media.ios_credit_19'), ''),
      new DeveloperCredit('singularity-s0', $r('app.media.ios_credit_20'), ''),
      new DeveloperCredit('starain-xinxin', $r('app.media.ios_credit_21'), ''),
      new DeveloperCredit('w568w', $r('app.media.ios_credit_22'), ''),
      new DeveloperCredit('yujular', $r('app.media.ios_credit_23'), '')
    ]
  }
  /** Source-project acknowledgements, separate from this app's bundled license inventory. */
  static libraries(): LibraryCredit[] {
    return [
      new LibraryCredit('animated_text_kit', 'https://github.com/aagarwal1012/Animated-Text-Kit', 'MIT License', true, false),
      new LibraryCredit('asn1lib', 'https://github.com/wstrange/asn1lib', 'BSD License', true, false),
      new LibraryCredit('auto_size_text', 'https://github.com/leisim/auto_size_text', 'MIT License', true, false),
      new LibraryCredit('beautiful_soup_dart', 'https://github.com/mzdm/beautiful_soup', 'MIT License', true, false),
      new LibraryCredit('BetterSafariView', 'https://github.com/stleamist/BetterSafariView/tree/v2.4.2', 'MIT license', false, true),
      new LibraryCredit('build_runner', 'https://github.com/dart-lang/build/tree/master/build_runner', 'BSD License', true, false),
      new LibraryCredit('cached_network_image', 'https://github.com/Baseflow/flutter_cached_network_image', 'MIT License', true, false),
      new LibraryCredit('clipboard', 'https://github.com/samuelezedi/flutter_clipboard', 'BSD License', true, false),
      new LibraryCredit('collection', 'https://github.com/dart-lang/collection', 'BSD 3-Clause License', true, false),
      new LibraryCredit('cupertino_icons', 'https://github.com/flutter/cupertino_icons', 'MIT License', true, false),
      new LibraryCredit('desktop_window', 'https://github.com/mix1009/desktop_window', 'MIT License', true, false),
      new LibraryCredit('device_identity', 'https://github.com/50431040/device_identity', 'MIT License', true, false),
      new LibraryCredit('device_info_plus', 'https://github.com/fluttercommunity/plus_plugins/tree/main/packages/device_info_plus', 'BSD 3-Clause License', true, false),
      new LibraryCredit('dio', 'https://github.com/flutterchina/dio', 'MIT License', true, false),
      new LibraryCredit('dio_cookie_manager', 'https://github.com/flutterchina/dio', 'MIT License', true, false),
      new LibraryCredit('dio_log', 'https://github.com/flutterplugin/dio_log', 'Apache License 2.0', true, false),
      new LibraryCredit('dio_redirect_interceptor', 'https://github.com/wilinz/dio_redirect_interceptor', 'MIT License', true, false),
      new LibraryCredit('Disk', 'https://github.com/saoudrizwan/Disk', 'MIT license', false, true),
      new LibraryCredit('encrypt_shared_preferences', 'https://github.com/xaldarof/encrypted-shared-preferences', 'Apache License 2.0', true, false),
      new LibraryCredit('event_bus', 'https://github.com/marcojakob/dart-event-bus', 'MIT License', true, false),
      new LibraryCredit('file_picker', 'https://github.com/miguelpruivo/plugins_flutter_file_picker', 'MIT License', true, false),
      new LibraryCredit('flex_color_picker', 'https://github.com/rydmike/flex_color_picker', 'BSD 3-Clause License', true, false),
      new LibraryCredit('flutter', 'https://github.com/flutter/flutter', 'BSD 3-Clause License', true, false),
      new LibraryCredit('flutter_email_sender', 'https://github.com/sidlatau/flutter_email_sender', 'Apache License 2.0', true, false),
      new LibraryCredit('flutter_fgbg', 'https://github.com/ajinasokan/flutter_fgbg', 'MIT License', true, false),
      new LibraryCredit('flutter_html', 'https://github.com/Sub6Resources/flutter_html', 'MIT License', true, false),
      new LibraryCredit('flutter_inappwebview', 'https://github.com/pichillilorenzo/flutter_inappwebview', 'Apache License 2.0', true, false),
      new LibraryCredit('flutter_layout_grid', 'https://github.com/madewithfelt/flutter_layout_grid', 'MIT License', true, false),
      new LibraryCredit('flutter_linkify', 'https://github.com/Cretezy/flutter_linkify', 'MIT License', true, false),
      new LibraryCredit('flutter_localizations', 'https://api.flutter.dev/flutter/flutter_localizations/flutter_localizations-library.html', 'BSD 3-Clause License', true, false),
      new LibraryCredit('flutter_markdown_plus', 'https://github.com/w568w/flutter_markdown_plus', 'BSD 3-Clause License', true, false),
      new LibraryCredit('flutter_math_fork', 'https://github.com/simpleclub-extended/flutter_math_fork', 'Apache License 2.0', true, false),
      new LibraryCredit('flutter_phoenix', 'https://github.com/mobiten/flutter_phoenix', 'MIT License', true, false),
      new LibraryCredit('flutter_platform_widgets', 'https://github.com/stryder-dev/flutter_platform_widgets', 'MIT License', true, false),
      new LibraryCredit('flutter_progress_dialog', 'https://github.com/wuzhendev/flutter_progress_dialog', 'Apache License 2.0', true, false),
      new LibraryCredit('flutter_secure_storage', 'https://github.com/mogol/flutter_secure_storage', 'BSD 3-Clause License', true, false),
      new LibraryCredit('flutter_sfsymbols', 'https://github.com/virskor/flutter_sfsymbols', 'Apache License 2.0', true, false),
      new LibraryCredit('flutter_swiper_view', 'https://github.com/feicien/flutter_swiper_view', 'MIT License', true, false),
      new LibraryCredit('flutter_tagging', 'https://github.com/sarbagyastha/flutter_tagging', 'BSD License', true, false),
      new LibraryCredit('flutter_test', 'https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html', 'BSD 3-Clause License', true, false),
      new LibraryCredit('flutter_typeahead', 'https://github.com/AbdulRahmanAlHamali/flutter_typeahead', 'BSD 2-Clause License', true, false),
      new LibraryCredit('fluttertoast', 'https://github.com/PonnamKarthik/FlutterToast', 'MIT License', true, false),
      new LibraryCredit('gallery_saver', 'https://github.com/CarnegieTechnologies/gallery_saver', 'Apache License 2.0', true, false),
      new LibraryCredit('http', 'https://github.com/dart-lang/http', 'BSD License', true, false),
      new LibraryCredit('ical', 'https://github.com/dartclub/ical', 'BSD 3-Clause License', true, false),
      new LibraryCredit('image_picker', 'https://github.com/flutter/plugins/tree/master/packages/image_picker/image_picker', 'Apache License 2.0', true, false),
      new LibraryCredit('in_app_review', 'https://github.com/britannio/in_app_review', 'MIT License', true, false),
      new LibraryCredit('intl', 'https://github.com/dart-lang/intl', 'BSD License', true, false),
      new LibraryCredit('IQKeyboardManager', 'https://github.com/hackiftekhar/IQKeyboardManager', 'MIT license', false, true),
      new LibraryCredit('js', 'https://github.com/dart-lang/sdk', 'BSD 3-Clause License', true, false),
      new LibraryCredit('json_serializable', 'https://github.com/google/json_serializable.dart/tree/master/json_serializable', 'BSD License', true, false),
      new LibraryCredit('KeychainAccess', 'https://github.com/kishikawakatsumi/KeychainAccess', 'MIT license', false, true),
      new LibraryCredit('Kotlin Stdlib Jdk7', 'https://github.com/JetBrains/kotlin', 'Apache License 2.0', true, false),
      new LibraryCredit('lazy_load_indexed_stack', 'https://github.com/okaryo/lazy_load_indexed_stack', 'MIT License', true, false),
      new LibraryCredit('linkify', 'https://github.com/Cretezy/linkify', 'MIT License', true, false),
      new LibraryCredit('lunar', 'https://github.com/6tail/lunar-flutter', 'MIT License', true, false),
      new LibraryCredit('markdown', 'https://github.com/dart-lang/markdown', 'BSD 3-Clause License', true, false),
      new LibraryCredit('material_color_generator', 'https://github.com/berkanaslan/material-color-generator', 'BSD 2-Clause License', true, false),
      new LibraryCredit('meta', 'https://github.com/dart-lang/sdk', 'BSD 3-Clause License', true, false),
      new LibraryCredit('mutex', 'https://github.com/hoylen/dart-mutex', 'BSD 3-Clause License', true, false),
      new LibraryCredit('no_screenshot', 'https://github.com/FlutterPlaza/no_screenshot', 'BSD 3-Clause License', true, false),
      new LibraryCredit('open_file', 'https://github.com/crazecoder/open_file', 'BSD License', true, false),
      new LibraryCredit('otp', 'https://github.com/Daegalus/dart-otp', 'MIT License', true, false),
      new LibraryCredit('package_info', 'https://github.com/flutter/plugins', 'BSD License', true, false),
      new LibraryCredit('path_provider', 'https://github.com/flutter/plugins', 'BSD License', true, false),
      new LibraryCredit('permission_handler', 'https://github.com/baseflowit/flutter-permission-handler', 'MIT License', true, false),
      new LibraryCredit('photo_view', 'https://github.com/renancaraujo/photo_view', 'MIT License', true, false),
      new LibraryCredit('provider', 'https://github.com/rrousselGit/provider', 'MIT License', true, false),
      new LibraryCredit('pub_semver', 'https://github.com/dart-lang/pub_semver', 'BSD 3-Clause License', true, false),
      new LibraryCredit('pubspec_generator', 'https://github.com/PlugFox/pubspec_generator', 'MIT License', true, false),
      new LibraryCredit('qr_flutter', 'https://github.com/theyakka/qr.flutter', 'BSD License', true, false),
      new LibraryCredit('Queue', 'https://github.com/mattmassicotte/Queue', 'BSD-3-Clause license', false, true),
      new LibraryCredit('quick_actions', 'https://github.com/flutter/plugins', 'BSD License', true, false),
      new LibraryCredit('receive_intent', 'https://github.com/w568w/receive_intent', 'GNU General Public License v3.0', true, false),
      new LibraryCredit('screen', 'https://github.com/clovisnicolas/flutter_screen', 'MIT License', true, false),
      new LibraryCredit('screen_brightness', 'https://github.com/aaassseee/screen_brightness', 'MIT License', true, false),
      new LibraryCredit('share', 'https://github.com/flutter/plugins', 'BSD License', true, false),
      new LibraryCredit('shared_preferences', 'https://github.com/flutter/plugins', 'BSD License', true, false),
      new LibraryCredit('SwiftSoup', 'https://github.com/scinfu/SwiftSoup', 'MIT license', false, true),
      new LibraryCredit('SwiftUI Introspect', 'https://github.com/siteline/SwiftUI-Introspect', 'Copyright 2019 Timber Software', false, true),
      new LibraryCredit('SwiftUIX', 'https://github.com/SwiftUIX/SwiftUIX', 'MIT license', false, true),
      new LibraryCredit('SwiftyJSON', 'https://github.com/SwiftyJSON/SwiftyJSON', 'MIT license', false, true),
      new LibraryCredit('toml', 'https://github.com/just95/toml.dart', 'MIT License', true, false),
      new LibraryCredit('tutorial_coach_mark', 'https://github.com/RafaelBarbosatec/tutorial_coach_mark', 'MIT License', true, false),
      new LibraryCredit('url_launcher', 'https://github.com/flutter/plugins', 'BSD License', true, false),
      new LibraryCredit('uuid', 'https://github.com/Daegalus/dart-uuid', 'MIT License', true, false),
      new LibraryCredit('win32', 'https://github.com/timsneath/win32', 'BSD 3-Clause License', true, false),
      new LibraryCredit('WrappingHStack', 'https://github.com/dkk/WrappingHStack', 'MIT license', false, true),
      new LibraryCredit('xiao_mi_push_plugin', 'https://github.com/w568w/FlutterXiaoMiPushPlugin', 'Apache License 2.0', true, false)
    ]
  }
}
