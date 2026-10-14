import { HoleRouteParams } from '../common/RouteParams'
import { ForumReadingPosition } from '../common/ForumReadingProgress'

/** One atomic navigation value prevents a hole watcher reading the previous floor. */
export class ForumThreadRoute extends HoleRouteParams {
  position: ForumReadingPosition | null = null
  constructor(holeId: number, floorId: number = 0, position: ForumReadingPosition | null = null) {
    super(holeId, floorId)
    this.position = position !== null && position.holeId === holeId ? position : null
  }
}

/** A bounded trail of identifiers, never retained component trees or Web hosts. */
export class ForumThreadHistory {
  private frames: ForumThreadRoute[] = []
  push(holeId: number, floorId: number, position: ForumReadingPosition | null = null): void {
    this.frames.push(new ForumThreadRoute(holeId, position === null ? floorId : 0, position))
    if (this.frames.length > 16) this.frames.shift()
  }
  pop(): ForumThreadRoute | undefined { return this.frames.pop() }
  hasPrevious(): boolean { return this.frames.length > 0 }
}
