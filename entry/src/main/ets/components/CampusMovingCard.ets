import { AttributeUpdater } from '@kit.ArkUI'
import { CampusCardMotion, CampusDragPosition, CampusDragPainter } from '../model/CampusCardMotion'
import { ThemeColors } from '../common/Theme'

@Component
export struct CampusMovingCard {
  @ObjectLink motion: CampusCardMotion
  cardId: string = ''
  radius: number = 24
  @BuilderParam content: () => void = this.Empty
  @Builder Empty() {}

  build() {
    Stack() { this.content() }
      .width('100%').height('100%').id('campus-layout-card-' + this.cardId)
      // Preserve the grid slot but never paint a second copy beneath the drag layer.
      .visibility(this.motion.held ? Visibility.Hidden : Visibility.Visible)
      .border({ width: this.motion.target ? 1.5 : 0, color: ThemeColors.primary }).borderRadius(this.radius)
  }
}

/** Render-only updates skip the component's observable rebuild path. */
class CampusDragTransform extends AttributeUpdater<StackAttribute> implements CampusDragPainter {
  private x: number = 0
  private y: number = 0
  initializeModifier(instance: StackAttribute): void {
    instance.translate({ x: this.x, y: this.y }).renderGroup(true)
  }
  move(x: number, y: number): void {
    this.x = x; this.y = y
    this.attribute?.translate({ x: x, y: y })
  }
}

@Component
export struct CampusDragCard {
  // Position is intentionally not observed: dimensions are fixed at mount,
  // and the native attribute updater exclusively owns pointer translation.
  dragPosition: CampusDragPosition = new CampusDragPosition()
  cardId: string = ''
  @BuilderParam content: () => void = this.Empty
  private dragAttributes: CampusDragTransform = new CampusDragTransform()
  aboutToAppear(): void { this.dragPosition.attach(this.dragAttributes) }
  aboutToDisappear(): void { this.dragPosition.detach(this.dragAttributes) }
  @Builder Empty() {}
  build() {
    Stack() { this.content() }
      .width(this.dragPosition.width).height(this.dragPosition.height)
      .position({ x: 0, y: 0 }).attributeModifier(this.dragAttributes).opacity(0.68)
      .id('campus-drag-card-' + this.cardId).hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }
}
