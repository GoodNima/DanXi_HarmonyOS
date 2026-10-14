import { ForumPresentation } from '../common/ForumPresentation'

/** Administrative identity is metadata, not a selectable topic tag. */
@Component
export struct ForumSpecialTag {
  @Prop name: string = ''
  build() {
    Text(ForumPresentation.tagLabel(this.name)).fontSize(11).fontWeight(FontWeight.Bold)
      .fontColor(Color.White).lineHeight(16).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 7, right: 7, top: 3, bottom: 3 }).borderRadius(6)
      .linearGradient({ direction: GradientDirection.Bottom, colors: [['#E93036', 0], ['#C71924', 1]] })
      .hitTestBehavior(HitTestMode.None)
  }
}
