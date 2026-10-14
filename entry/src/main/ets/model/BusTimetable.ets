import { BusDirection, BusSchedule } from './Academic'
import { Constant } from '../common/Constant'

/** Mirrors upstream BusPage._filterBus: reverse backwards and matching dual routes. */
export class BusTimetable {
  static readonly CAMPUSES: string[] = Constant.CAMPUS_NAMES

  static reversed(item: BusSchedule): BusSchedule {
    return { id: item.id, startCampus: item.endCampus, endCampus: item.startCampus,
      startTime: item.endTime, endTime: item.startTime,
      direction: item.direction === BusDirection.BACKWARD ? BusDirection.FORWARD :
        item.direction === BusDirection.FORWARD ? BusDirection.BACKWARD : item.direction,
      holidayRun: item.holidayRun }
  }

  static minutes(time: string): number {
    const match = /^(\d{1,2}):(\d{2})$/.exec(time)
    if (match === null) return -1
    const hour = Number(match[1]), minute = Number(match[2])
    return hour < 24 && minute < 60 ? hour * 60 + minute : -1
  }

  static filter(items: BusSchedule[], start: string, end: string, showAll: boolean, now: Date): BusSchedule[] {
    const rows: BusSchedule[] = []
    const currentMinutes = now.getHours() * 60 + now.getMinutes()
    for (const raw of items) {
      const item = raw.direction === BusDirection.BACKWARD ||
        (raw.direction === BusDirection.DUAL && raw.startCampus === end && raw.endCampus === start)
        ? BusTimetable.reversed(raw) : raw
      if (item.startCampus !== start || item.endCampus !== end) continue
      const departure = BusTimetable.minutes(item.startTime || item.endTime)
      if (showAll || departure < 0 || departure > currentMinutes) rows.push(item)
    }
    return rows.sort((a: BusSchedule, b: BusSchedule) =>
      BusTimetable.minutes(a.startTime || a.endTime) - BusTimetable.minutes(b.startTime || b.endTime))
  }
}
