import { ForumHole, ForumFloor } from '../model/Forum'
import { ForumContentParser } from '../model/ForumContent'

/** Feed response already includes last_floor. Never fetch on card render. */
export class ForumLatestReply {
  static floor(hole: ForumHole): ForumFloor | null {
    const last = hole.lastFloor
    return last !== null && last.floorId > 0 && last.floorId !== hole.firstFloor?.floorId ? last : null
  }
  static summary(floor: ForumFloor, deleted: string, image: string, sticker: string, quote: string): string {
    if (floor.deleted) return deleted
    if (floor.getFoldReason()) return floor.getFoldReason()
    return ForumContentParser.summary(floor.content.substring(0, 8192), false).replace(/\[图片\]/g, image)
      .replace(/\[表情\]/g, sticker).replace(/\[引用 /g, '[' + quote + ' ').replace(/\s+/g, ' ').trim()
  }
}
