import { router } from '@kit.ArkUI'
import { EditorRouteParams } from '../common/RouteParams'
import { ForumComposerView } from '../components/ForumComposerView'

@Entry
@Component
struct ForumEditorPage {
  private params: EditorRouteParams = router.getParams() as EditorRouteParams
  build() {
    Stack() {
      ForumComposerView({ initialDivisionId: this.params?.divisionId ?? 0, initialDivisionName: this.params?.divisionName ?? '' })
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
