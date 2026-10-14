import { ForumFloor, ForumHole, ForumUser, ForumDivision, ForumTag, jsonString, jsonNumber, jsonObject, jsonArray } from './Forum'
import { ForumQuoteRepository } from './ForumQuoteRepository'

export class ForumHistory {
  content: string = ''
  userId: number = 0
  timeUpdated: string = ''
  static fromJson(json: Record<string, Object>): ForumHistory {
    const result = new ForumHistory()
    result.content = jsonString(json, 'content')
    result.userId = jsonNumber(json, 'user_id')
    result.timeUpdated = jsonString(json, 'time_updated')
    return result
  }
}

export class SummaryBranch {
  id: number = 0
  color: string = ''
  label: string = ''
  content: string = ''
  floors: number[] = []
}

export class SummaryInteraction {
  fromFloor: number = 0
  toFloor: number = 0
  fromUser: string = ''
  toUser: string = ''
  kind: string = ''
  content: string = ''
}

export class ForumSummary {
  code: number = 0
  message: string = ''
  summary: string = ''
  generatedAt: string = ''
  traceId: string = ''
  keywords: string[] = []
  branches: SummaryBranch[] = []
  interactions: SummaryInteraction[] = []
  static fromJson(json: Record<string, Object>): ForumSummary {
    const result = new ForumSummary()
    result.code = jsonNumber(json, 'code')
    result.message = jsonString(json, 'message')
    const data = jsonObject(json, 'data')
    if (data === null) return result
    result.summary = jsonString(data, 'summary')
    result.generatedAt = jsonString(data, 'generated_at')
    result.traceId = jsonString(data, 'trace_id')
    result.keywords = jsonArray(data, 'keywords').filter((item: Object) => typeof item === 'string') as string[]
    for (const value of jsonArray(data, 'branches')) {
      if (value === null || typeof value !== 'object' || Array.isArray(value)) continue
      const item = value as Record<string, Object>
      const branch = new SummaryBranch()
      branch.id = jsonNumber(item, 'id')
      branch.color = jsonString(item, 'color')
      branch.label = jsonString(item, 'label')
      branch.content = jsonString(item, 'content')
      branch.floors = jsonArray(item, 'representative_floors').filter((id: Object) => typeof id === 'number' && Number.isSafeInteger(id) && Number(id) > 0) as number[]
      result.branches.push(branch)
    }
    for (const value of jsonArray(data, 'interactions')) {
      if (value === null || typeof value !== 'object' || Array.isArray(value)) continue
      const item = value as Record<string, Object>
      const interaction = new SummaryInteraction()
      interaction.fromFloor = jsonNumber(item, 'from_floor'); interaction.toFloor = jsonNumber(item, 'to_floor')
      interaction.fromUser = jsonString(item, 'from_user'); interaction.toUser = jsonString(item, 'to_user')
      interaction.kind = jsonString(item, 'interaction_type'); interaction.content = jsonString(item, 'content')
      result.interactions.push(interaction)
    }
    return result
  }
}

/** Production and offline UI tests exercise the same component through this contract. */
export interface ForumDetailSource extends ForumQuoteRepository {
  getHole(id: number): Promise<ForumHole>
  getFloor(id: number): Promise<ForumFloor>
  getFloors(id: number, offset: number, size: number): Promise<ForumFloor[]>
  getMe(): Promise<ForumUser>
  getFavoriteHoleIds(): Promise<number[]>
  getSubscribedHoleIds(): Promise<number[]>
  setFavorite(id: number, value: boolean): Promise<void>
  setSubscription(id: number, value: boolean): Promise<void>
  markHoleRead(id: number): Promise<void>
  likeFloor(id: number, value: number): Promise<ForumFloor>
  createFloor(id: number, content: string): Promise<void>
  uploadImage(filePath: string, filename: string): Promise<string>
  modifyFloor(id: number, content: string): Promise<void>
  deleteFloor(id: number, reason?: string): Promise<void>
  reportFloor(id: number, reason: string): Promise<void>
  getHistory(id: number): Promise<ForumHistory[]>
  getSummary(id: number, refresh?: boolean): Promise<ForumSummary>
  summaryFeedback(id: number, type: string, reason?: string): Promise<void>
  moderateHole(id: number, action: string, enabled: boolean): Promise<void>
  moderateFloor(id: number, action: string, value: string): Promise<void>
  getDivisions(): Promise<ForumDivision[]>
  getTags(): Promise<ForumTag[]>
  updateHoleTags(id: number, division: number, tags: ForumTag[]): Promise<void>
  setPinned(division: number, holes: number[]): Promise<void>
}

export class ForumDetailRules {
  static canReply(hole: ForumHole | null): boolean {
    return hole !== null && !hole.locked && !hole.frozen && !hole.hidden && !hole.isForceDeleted()
  }
  static canEdit(floor: ForumFloor, admin: boolean): boolean { return !floor.deleted && (floor.isMe || admin) }
  static filter(floors: ForumFloor[], openingId: number, author: string): ForumFloor[] {
    return floors.filter((floor: ForumFloor) => floor.floorId !== openingId && (!author || floor.anonyname === author))
  }
  static replyBody(content: string, floorId: number): string {
    return (floorId > 0 ? '##' + floorId + '\n' : '') + content.trim()
  }
  static timestamp(value: string): string {
    const date = new Date(value)
    if (!Number.isFinite(date.getTime())) return value
    return date.getFullYear() + '/' + String(date.getMonth() + 1).padStart(2, '0') + '/' + String(date.getDate()).padStart(2, '0') +
      ' ' + String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0') + ':' + String(date.getSeconds()).padStart(2, '0')
  }
}
