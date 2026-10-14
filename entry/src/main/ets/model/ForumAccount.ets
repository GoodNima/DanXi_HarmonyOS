import { ForumFloor, jsonString, jsonNumber, jsonObject } from './Forum'

/** Exact OTPunishment wire fields from upstream model/forum/punishment.dart. */
export class ForumPunishment {
  id: number = 0
  reason: string = ''
  start: string = ''
  end: string = ''
  deleted: string = ''
  divisionId: number = 0
  duration: number = 0
  floorId: number = 0
  floor: ForumFloor | null = null
  static fromJson(row: Record<string, Object>): ForumPunishment {
    const value = new ForumPunishment()
    value.id = jsonNumber(row, 'id')
    value.reason = jsonString(row, 'reason')
    value.start = jsonString(row, 'start_time')
    value.end = jsonString(row, 'end_time')
    value.deleted = jsonString(row, 'deleted_at')
    value.divisionId = jsonNumber(row, 'division_id')
    value.duration = jsonNumber(row, 'duration')
    value.floorId = jsonNumber(row, 'floor_id')
    const floor = jsonObject(row, 'floor')
    if (floor !== null) value.floor = ForumFloor.fromJson(floor)
    return value
  }
}
