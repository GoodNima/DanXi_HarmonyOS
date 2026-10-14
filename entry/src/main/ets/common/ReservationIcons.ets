/** Category semantics follow the Swift categoryIcon map. The SDK has no
 * complete matching sport symbol set; keep consistent transparent SVG outlines. */
export class ReservationIcons {
  /** Native SDK 26 symbols match the iOS venue category placeholders. Keep
   * the existing menu assets separate from the optional photograph's fallback. */
  static placeholder(name: string): Resource {
    if (name.includes('钢琴') || name.includes('琴房')) return $r('sys.symbol.music')
    if (name.includes('桌球') || name.includes('台球')) return $r('sys.symbol.figure_billiard')
    if (name.includes('篮球')) return $r('sys.symbol.basketball_fill')
    if (name.includes('羽毛球')) return $r('sys.symbol.figure_badminton')
    if (name.includes('足球')) return $r('sys.symbol.figure_football')
    if (name.includes('排球')) return $r('sys.symbol.volleyball_fill')
    if (name.includes('网球')) return $r('sys.symbol.figure_tennis')
    if (name.includes('舞蹈')) return $r('sys.symbol.figure_dance')
    if (name.includes('体能房') || name.includes('健身')) return $r('sys.symbol.dumbbell')
    if (name.includes('乒乓球')) return $r('sys.symbol.figure_table_tennis')
    return $r('sys.symbol.building')
  }
  static category(name: string): Resource {
    if (name.includes('钢琴') || name.includes('琴房')) return $r('app.media.reservation_piano')
    if (name.includes('桌球') || name.includes('台球')) return $r('app.media.reservation_billiards')
    if (name.includes('活动中心')) return $r('app.media.reservation_hall')
    if (name.includes('篮球')) return $r('app.media.reservation_basketball')
    if (name.includes('羽毛球')) return $r('app.media.reservation_badminton')
    if (name.includes('足球')) return $r('app.media.reservation_football')
    if (name.includes('排球')) return $r('app.media.reservation_volleyball')
    if (name.includes('网球')) return $r('app.media.reservation_tennis')
    if (name.includes('舞蹈')) return $r('app.media.reservation_dance')
    if (name.includes('体能房') || name.includes('健身')) return $r('app.media.reservation_gym')
    if (name.includes('乒乓球')) return $r('app.media.reservation_tabletennis')
    return $r('app.media.reservation_court')
  }
}
