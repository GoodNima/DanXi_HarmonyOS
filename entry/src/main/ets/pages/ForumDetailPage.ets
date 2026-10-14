import { router } from '@kit.ArkUI'
import { HoleRouteParams } from '../common/RouteParams'
import { ForumDetailView } from '../components/ForumDetailView'
import { ForumThreadHistory, ForumThreadRoute } from '../model/ForumThreadHistory'
import { ForumReadingPosition } from '../common/ForumReadingProgress'
import { ForumImageTransition } from '../common/ForumImageTransition'

@Entry
@Component
struct ForumDetailPage {
  @State route: ForumThreadRoute = new ForumThreadRoute(-1)
  private visits: ForumThreadHistory = new ForumThreadHistory()
  private sourceIndex: number = 0

  private navigate(holeId: number, floorId: number, position: ForumReadingPosition | null): void {
    this.visits.push(this.route.holeId, this.route.floorId, position)
    this.route = new ForumThreadRoute(holeId, floorId)
  }

  private back(): void {
    const previous: ForumThreadRoute | undefined = this.visits.pop()
    if (previous === undefined) { router.back(); return }
    this.route = previous
  }

  onBackPress(): boolean {
    if (!this.visits.hasPrevious()) return false
    this.back()
    return true
  }
  aboutToAppear(): void {
    this.sourceIndex = router.getState().index
    const params = router.getParams() as HoleRouteParams
    if (params !== null && params !== undefined && typeof params.holeId === 'number') {
      this.route = new ForumThreadRoute(params.holeId, params.floorId || 0)
    }
  }
  aboutToDisappear(): void { ForumImageTransition.finishSource(this.sourceIndex) }
  pageTransition() {
    // Ordinary post navigation has no matching override and keeps the native
    // 0.107 transition. An image flight must not also move/dim its source page.
    if (ForumImageTransition.holdsSource(this.sourceIndex)) {
      PageTransitionExit({ type: RouteType.Push, duration: 360, curve: Curve.Friction })
        .translate({ x: 0, y: 0 }).scale({ x: 1, y: 1 }).opacity(1)
      PageTransitionEnter({ type: RouteType.Pop, duration: 360, curve: Curve.Friction })
        .translate({ x: 0, y: 0 }).scale({ x: 1, y: 1 }).opacity(1)
        .onEnter((_type: RouteType, progress: number) => {
          if (progress >= 1) ForumImageTransition.finishSource(this.sourceIndex)
        })
    }
  }
  build() {
    Stack() {
      ForumDetailView({ initialRoute: this.route,
          onNavigate: (holeId: number, floorId: number, position: ForumReadingPosition | null) => { this.navigate(holeId, floorId, position) },
          onBack: () => { this.back() } })
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
