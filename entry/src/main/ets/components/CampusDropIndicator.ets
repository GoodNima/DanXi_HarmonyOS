import { CampusDropPosition } from '../model/CampusCardMotion'
import { ThemeColors } from '../common/Theme'

@Component
export struct CampusDropIndicator {
  @ObjectLink dropModel: CampusDropPosition
  build() {
    Column().width(this.dropModel.width).height(this.dropModel.height)
      .border({ width: 1.5, color: ThemeColors.primary, style: BorderStyle.Dashed }).borderRadius(20)
      .position({ x: this.dropModel.x, y: this.dropModel.y }).opacity(this.dropModel.visible ? 1 : 0)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
