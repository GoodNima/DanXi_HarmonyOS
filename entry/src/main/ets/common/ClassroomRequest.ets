import { EmptyClassroom } from '../model/Academic'

/** Refreshing the same room must replace nodes when its displayed availability changes. */
export function classroomRowKey(row: EmptyClassroom, index: number): string {
  return JSON.stringify([String(index), row.building, row.room, row.roomId ?? '', row.day ?? '', row.campus,
    row.capacity > 0 ? String(row.capacity) : '',
    row.freePeriods === undefined ? 'raw' : 'periods',
    row.freePeriods === undefined ? row.status : JSON.stringify(row.freePeriods),
    JSON.stringify(row.periods ?? [])])
}

export interface ClassroomResult {
  rows: EmptyClassroom[]
  error: string
}

/** A building switch invalidates all older responses, including older errors. */
export class ClassroomRequest {
  private version: number = 0

  invalidate(): void { this.version++ }

  async load(fetchRows: (building: string, force: boolean) => Promise<EmptyClassroom[]>,
    building: string, force: boolean): Promise<ClassroomResult | undefined> {
    const version = ++this.version
    try {
      const rows = await fetchRows(building, force)
      if (version !== this.version) return undefined
      return { rows: rows, error: '' }
    } catch (e) {
      if (version !== this.version) return undefined
      const raw = String(e)
      return { rows: [], error: raw.replace(/^[A-Za-z]+Error: /, '').replace(/^Error: /, '') }
    }
  }
}
