import { BusSchedule, EmptyClassroom } from '../model/Academic'
import { BusTimetable } from '../model/BusTimetable'
import { CampusPreviewItem } from '../model/CampusPreviewItem'
import { ClassroomPresentation } from './ClassroomPresentation'

/** Local projections only: route changes never request a second timetable. */
export class CampusCardInformation {
  static buses(items: BusSchedule[], start: string, end: string, now: Date): CampusPreviewItem[] {
    const forward = CampusCardInformation.busDirection(items, start, end, now)
    const reverse = CampusCardInformation.busDirection(items, end, start, now)
    return [forward, reverse]
  }

  private static busDirection(items: BusSchedule[], start: string, end: string, now: Date): CampusPreviewItem {
    const departures = BusTimetable.filter(items, start, end, false, now)
    const row = new CampusPreviewItem(); row.label = start + ' → ' + end
    row.value = departures[0]?.startTime || departures[0]?.endTime || ''
    row.detail = departures[1]?.startTime || departures[1]?.endTime || ''
    return row
  }

  static classrooms(items: EmptyClassroom[], slot: number): CampusPreviewItem[] {
    return items.filter((room: EmptyClassroom) => ClassroomPresentation.slotFree(room, slot) === true)
      .slice(0, 8).map((room: EmptyClassroom): CampusPreviewItem => {
        const row = new CampusPreviewItem(); row.label = room.room
        row.value = room.capacity > 0 ? String(room.capacity) : ''
        row.detail = ClassroomPresentation.freeRanges(room.freePeriods ?? [])
        return row
      })
  }

  static classroomTotal(items: EmptyClassroom[], slot: number): number {
    return items.filter((room: EmptyClassroom) => ClassroomPresentation.slotFree(room, slot) !== undefined).length
  }
}
