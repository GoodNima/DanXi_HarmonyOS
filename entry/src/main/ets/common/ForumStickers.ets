/** Original sticker assets, checksum-verified against upstream's published manifest. */
export class ForumStickers {
  static ids(): string[] {
    return ['dx_murderous', 'dx_roll', 'dx_call', 'dx_rush', 'dx_guilty', 'dx_kiss', 'dx_sleep', 'dx_confused',
      'dx_dying', 'dx_roped', 'dx_onfire', 'dx_onlooker', 'dx_fright', 'dx_egg', 'dx_eatnow', 'dx_caught',
      'dx_swim', 'dx_cry', 'dx_heart', 'dx_mokyu', 'dx_craving', 'dx_angry', 'dx_elderphone', 'dx_handsup',
      'dx_overwhelm', 'dx_ehe', 'dx_worn', 'dx_hug', 'dx_ok', 'dx_thrill', 'dx_twin', 'dx_emperor',
      'dx_broke', 'dx_lgtm', 'dx_covermouth', 'dx_like', 'dx_speechless', 'dx_strong', 'dx_touch_fish', 'dx_cate']
  }
  static resource(id: string): Resource | undefined {
    const resources: Record<string, Resource> = {
      'dx_murderous': $r('app.media.dx_murderous'),
      'dx_roll': $r('app.media.dx_roll'),
      'dx_call': $r('app.media.dx_call'),
      'dx_rush': $r('app.media.dx_rush'),
      'dx_guilty': $r('app.media.dx_guilty'),
      'dx_kiss': $r('app.media.dx_kiss'),
      'dx_sleep': $r('app.media.dx_sleep'),
      'dx_confused': $r('app.media.dx_confused'),
      'dx_dying': $r('app.media.dx_dying'),
      'dx_roped': $r('app.media.dx_roped'),
      'dx_onfire': $r('app.media.dx_onfire'),
      'dx_onlooker': $r('app.media.dx_onlooker'),
      'dx_fright': $r('app.media.dx_fright'),
      'dx_egg': $r('app.media.dx_egg'),
      'dx_eatnow': $r('app.media.dx_eatnow'),
      'dx_caught': $r('app.media.dx_caught'),
      'dx_swim': $r('app.media.dx_swim'),
      'dx_cry': $r('app.media.dx_cry'),
      'dx_heart': $r('app.media.dx_heart'),
      'dx_mokyu': $r('app.media.dx_mokyu'),
      'dx_craving': $r('app.media.dx_craving'),
      'dx_angry': $r('app.media.dx_angry'),
      'dx_elderphone': $r('app.media.dx_elderphone'),
      'dx_handsup': $r('app.media.dx_handsup'),
      'dx_overwhelm': $r('app.media.dx_overwhelm'),
      'dx_ehe': $r('app.media.dx_ehe'),
      'dx_worn': $r('app.media.dx_worn'),
      'dx_hug': $r('app.media.dx_hug'),
      'dx_ok': $r('app.media.dx_ok'),
      'dx_thrill': $r('app.media.dx_thrill'),
      'dx_twin': $r('app.media.dx_twin'),
      'dx_emperor': $r('app.media.dx_emperor'),
      'dx_broke': $r('app.media.dx_broke'),
      'dx_lgtm': $r('app.media.dx_lgtm'),
      'dx_covermouth': $r('app.media.dx_covermouth'),
      'dx_like': $r('app.media.dx_like'),
      'dx_speechless': $r('app.media.dx_speechless'),
      'dx_strong': $r('app.media.dx_strong'),
      'dx_touch_fish': $r('app.media.dx_touch_fish'),
      'dx_cate': $r('app.media.dx_cate')
    }
    return resources[id]
  }
}
