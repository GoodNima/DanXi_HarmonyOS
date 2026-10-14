import { router } from '@kit.ArkUI'
import { CampusDetailParams } from '../common/CampusPreview'
import { Constant } from '../common/Constant'
import { DashboardPage } from './DashboardPage'
import { ThemeColors } from '../common/Theme'
import { CampusDestination } from '../common/CampusDestination'

@Entry
@Component
struct CampusDetailPage {
  @State feature: string = 'announcement'
  @State private visible: boolean = true
  onPageShow(): void { this.visible = true }
  onPageHide(): void { this.visible = false }
  aboutToAppear(): void {
    const params: CampusDetailParams = router.getParams() as CampusDetailParams
    if (params && Constant.DEFAULT_DASHBOARD_ORDER.includes(params.feature)) this.feature = params.feature
    const destination: string = CampusDestination.page(this.feature)
    if (destination !== 'pages/CampusDetailPage') router.replaceUrl({ url: destination, params: new CampusDetailParams(this.feature) })
  }
  build() {
    Stack() { DashboardPage({ detailFeature: this.feature, detailVisible: this.visible }) }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgStart)
  }
}
