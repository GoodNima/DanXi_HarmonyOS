/** Grid-slot visibility and drop feedback; pointer motion lives in a separate layer. */
@Observed
export class CampusCardMotion {
  x: number = 0
  y: number = 0
  target: boolean = false
  held: boolean = false
  reset(): void { this.x = 0; this.y = 0 }
}

/** Screen-space drag layer: scrolling underneath never changes its transform. */
export interface CampusDragPainter { move(x: number, y: number): void }

export class CampusDragPosition {
  x: number = 0
  y: number = 0
  width: number = 0
  height: number = 0
  private painter: CampusDragPainter | undefined = undefined
  attach(painter: CampusDragPainter): void { this.painter = painter; painter.move(this.x, this.y) }
  detach(painter: CampusDragPainter): void { if (this.painter === painter) this.painter = undefined }
  move(x: number, y: number): void {
    if (Math.abs(x - this.x) <= 0.05 && Math.abs(y - this.y) <= 0.05) return
    this.x = x; this.y = y
    this.painter?.move(x, y)
  }
}

@Observed
export class CampusDropPosition {
  visible: boolean = false
  x: number = 0
  y: number = 0
  width: number = 0
  height: number = 0
}
