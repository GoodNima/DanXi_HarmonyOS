import { SemesterInfo } from '../model/Academic'
import { ScheduleSnapshot } from '../repository/TimetableRepository'

/** A read adapter permits native verification with synthetic semester data.
 * Ordinary pages use the guarded, account-scoped timetable repository. */
export interface TimetableSource {
  cached(): Promise<ScheduleSnapshot | undefined>
  load(selected?: SemesterInfo, force?: boolean): Promise<ScheduleSnapshot>
  semesters(): Promise<SemesterInfo[]>
}
