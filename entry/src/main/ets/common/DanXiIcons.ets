/**
 * DanXi Icon - HarmonyOS SymbolGlyph wrapper.
 * Maps feature icon names to system symbols (equivalent to original Material Icons).
 */

/** An explicit floppy outline; the system save icon renders a download tray. */
export function getSaveIcon(): Resource { return $r('app.media.save_floppy') }

export function getSymbolIcon(name: string): Resource {
  const map: Record<string, Resource> = {
    // Tab bar
    'home': $r('sys.symbol.house'),
    'forum': $r('sys.symbol.message'),
    'person': $r('sys.symbol.person'),

    // Dashboard features
    'announcement': $r('sys.symbol.bell'),
    'bus': $r('sys.symbol.car'),
    'empty_classroom': $r('sys.symbol.doors_and_windows_open'),
    'exam': $r('sys.symbol.square_and_pencil'),
    'gpa': $r('sys.symbol.graduationcap'),
    'timetable': $r('sys.symbol.calendar'),
    'card': $r('sys.symbol.bank_card'),
    'academic': $r('sys.symbol.graduationcap'),
    'evaluation': $r('sys.symbol.star'),
    'developer_notice': $r('sys.symbol.bell'),
    'campus_access': $r('sys.symbol.checkmark_shield'),
    'dining': $r('sys.symbol.fork_knife_fill'),
    'library': $r('sys.symbol.book_closed_right_left'),
    'electricity': $r('sys.symbol.bolt'),
    'sports': $r('sys.symbol.figure_running'),
    'life_code': $r('sys.symbol.qrcode'),

    // Settings
    'proxy': $r('sys.symbol.link'),
    'haptics': $r('sys.symbol.waveform'),
    'contrast': $r('sys.symbol.contrast'),
    'mail': $r('sys.symbol.envelope'),
    'copy': $r('sys.symbol.doc_text_on_doc_text'),
    'theme': $r('sys.symbol.paintpalette'),
    'language': $r('sys.symbol.translate'),
    'notification_setting': $r('sys.symbol.bell'),
    'dashboard_order': $r('sys.symbol.list_bullet'),
    'about': $r('sys.symbol.exclamationmark_circle'),
    'license': $r('sys.symbol.doc_text'),
    'diagnostics': $r('sys.symbol.gearshape'),
    'logout': $r('sys.symbol.power'),
    'guest': $r('sys.symbol.person'),
    'location': $r('sys.symbol.map'),
    'image': $r('sys.symbol.picture'),
    'tag': $r('sys.symbol.label'),
    'star': $r('sys.symbol.star'),
    'history': $r('sys.symbol.clock'),
    'sort': $r('sys.symbol.arrow_up_and_down_square_portrait'),

    // Actions
    'back': $r('sys.symbol.arrow_left'),
    'previous': $r('sys.symbol.chevron_left'),
    'forward': $r('sys.symbol.chevron_right'),
    'more': $r('sys.symbol.ellipsis_circle'),
    'edit': $r('sys.symbol.square_and_pencil'),
    'reply': $r('sys.symbol.arrowshape_turn_up_left'),
    'replies': $r('sys.symbol.ellipsis_bubble'),
    'share': $r('sys.symbol.share'),
    'download': $r('sys.symbol.arrow_down_to_line'),
    'delete': $r('sys.symbol.trash'),
    'pin': $r('sys.symbol.pin_fill'),
    'lock': $r('sys.symbol.lock'),
    'up': $r('sys.symbol.arrow_up'),
    'down': $r('sys.symbol.arrow_down'),
    'check': $r('sys.symbol.checkmark'),
    'eye': $r('sys.symbol.eye'),
    'eye_slash': $r('sys.symbol.eye_slash'),
    'search': $r('sys.symbol.magnifyingglass'),
    'refresh': $r('sys.symbol.arrow_counterclockwise'),
    'expand': $r('sys.symbol.chevron_down'),

    // Common
    'empty': $r('sys.symbol.doc'),
  }

  return map[name] ?? $r('sys.symbol.exclamationmark_circle')
}
