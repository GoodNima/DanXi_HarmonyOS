import { ForumPreviewSequence } from '../common/ForumPreviewSequence'

/** Prepare the content in its actual card layout, then reveal in feed order.
 * Slow media/quotes have a finite deadline; they never block the entire feed. */
@Component
export struct ForumPreviewCard {
  @Prop controlId: string = ''
  @BuilderParam content: (prepared: () => void) => void = this.EmptyContent
  onRevealed: () => void = () => {}
  sequence: ForumPreviewSequence | undefined = undefined
  @State private cardOpacity: number = 0
  private active: boolean = false
  private prepared: boolean = false
  private revealed: boolean = false
  private deadline: number = -1
  private generation: number = 0
  private sequenceTicket: number = -1

  aboutToAppear(): void {
    this.active = true; this.generation++
    if (this.sequence !== undefined) {
      if (this.sequence.hasRevealed(this.controlId)) {
        this.cardOpacity = 1; this.revealed = true; this.prepared = true
      }
      this.sequenceTicket = this.sequence.join(this.controlId, this.getUIContext(),
        (immediate: boolean) => { this.reveal(immediate) })
      if (this.revealed) this.sequence.ready(this.controlId, this.sequenceTicket)
    }
    // A native cached row may reappear after leaving during its layout wait.
    // Keep already drawn cards visible; resume an interrupted preparation.
    if (this.prepared && !this.revealed) { this.prepared = false; this.contentReady() }
  }
  aboutToDisappear(): void {
    this.active = false; this.generation++
    if (this.deadline >= 0) clearTimeout(this.deadline)
    this.deadline = -1
    this.sequence?.leave(this.controlId, this.sequenceTicket)
  }

  private visible(visible: boolean): void {
    if (!this.active || !visible || this.revealed || this.deadline >= 0) return
    const generation: number = this.generation
    this.deadline = setTimeout(() => {
      this.deadline = -1
      if (this.active && generation === this.generation) this.contentReady()
    }, 1800)
  }

  private contentReady(): void {
    if (!this.active || this.prepared || this.revealed) return
    this.prepared = true
    if (this.deadline >= 0) clearTimeout(this.deadline)
    this.deadline = -1
    const generation: number = this.generation
    this.getUIContext().postFrameCallback({ onFrame: () => {
      if (!this.active || generation !== this.generation) return
      this.getUIContext().postFrameCallback({ onFrame: () => {
        if (!this.active || generation !== this.generation) return
        if (this.sequence !== undefined) this.sequence.ready(this.controlId, this.sequenceTicket)
        else this.reveal()
      }, onIdle: () => {} })
    }, onIdle: () => {} })
  }

  private reveal(immediate: boolean = false): void {
    if (!this.active || this.revealed) return
    this.revealed = true
    if (this.deadline >= 0) clearTimeout(this.deadline)
    this.deadline = -1
    if (immediate) this.cardOpacity = 1
    else this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => { this.cardOpacity = 1 })
    this.onRevealed()
  }

  @Builder
  EmptyContent(_prepared: () => void) { Column() }

  build() {
    Column() { this.content(() => { this.contentReady() }) }.width('100%')
      .opacity(this.cardOpacity).renderGroup(true).id(this.controlId)
      .hitTestBehavior(this.cardOpacity > 0 ? HitTestMode.Default : HitTestMode.None)
      .onVisibleAreaChange([0.01], (visible: boolean) => { this.visible(visible) })
  }
}
