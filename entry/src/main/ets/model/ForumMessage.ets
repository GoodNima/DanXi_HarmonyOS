import { ForumFloor, jsonString, jsonNumber, jsonBoolean, jsonObject } from './Forum'

/** Wire names match upstream OTMessage; report messages wrap their floor in data.floor. */
export class ForumMessage {
  messageId: number = 0
  title: string = ''
  description: string = ''
  code: string = ''
  created: string = ''
  read: boolean = false
  floor: ForumFloor | null = null
  reportReason: string = ''
  static fromJson(source: Record<string, Object>): ForumMessage {
    const row = new ForumMessage()
    row.messageId = jsonNumber(source, 'message_id')
    row.title = jsonString(source, 'message')
    row.description = jsonString(source, 'description')
    row.code = jsonString(source, 'code')
    row.created = jsonString(source, 'time_created')
    row.read = jsonBoolean(source, 'has_read')
    const data = jsonObject(source, 'data')
    if (data !== null) {
      const floor = row.code === 'report' || row.code === 'report_dealt' ? jsonObject(data, 'floor') : data
      if (floor !== null && jsonNumber(floor, 'floor_id') > 0) row.floor = ForumFloor.fromJson(floor)
      if (row.code === 'report' || row.code === 'report_dealt') row.reportReason = jsonString(data, 'reason')
    }
    return row
  }
}
