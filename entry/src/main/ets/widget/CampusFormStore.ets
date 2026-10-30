import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { formBindingData, formProvider } from '@kit.FormKit'
import { CampusFormData } from './CampusFormData'

class FormRegistration {
  id: string = ''
  feature: string = ''
  dimension: number = 2
}

/** UIAbility and FormExtensionAbility share the application files directory.
 * Each writer owns a different file; atomic replacement avoids partial JSON.
 * The form never starts authentication or duplicates campus network requests. */
export class CampusFormStore {
  private static directory: string = ''
  static init(context: common.Context): void { CampusFormStore.directory = context.getApplicationContext().filesDir }
  private static path(name: string): string { return CampusFormStore.directory + '/desktop-' + name + '.json' }
  private static read(name: string): string {
    if (!CampusFormStore.directory) return ''
    try { return fs.readTextSync(CampusFormStore.path(name)) } catch (e) { return '' }
  }
  private static write(name: string, value: string): void {
    if (!CampusFormStore.directory) return
    const target = CampusFormStore.path(name); const temporary = target + '.tmp'
    const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    try { fs.writeSync(file.fd, value) } finally { fs.closeSync(file) }
    fs.renameSync(temporary, target)
  }
  private static registrations(): FormRegistration[] {
    try {
      const rows: FormRegistration[] = JSON.parse(CampusFormStore.read('forms')) as FormRegistration[]
      return Array.isArray(rows) ? rows.filter(row => typeof row.id === 'string' && /^\d+$/.test(row.id) && CampusFormData.supports(row.feature)) : []
    } catch (e) { return [] }
  }
  static add(id: string, feature: string, dimension: number = 2): CampusFormData {
    if (!/^\d+$/.test(id) || !CampusFormData.supports(feature)) return CampusFormData.empty(feature)
    const rows = CampusFormStore.registrations().filter(row => row.id !== id)
    const row = new FormRegistration(); row.id = id; row.feature = feature
    row.dimension = [1, 2, 3].includes(dimension) ? dimension : 2; rows.push(row)
    CampusFormStore.write('forms', JSON.stringify(rows))
    const snapshot = CampusFormStore.snapshot(feature); snapshot.dimension = row.dimension; return snapshot
  }
  static remove(id: string): void {
    CampusFormStore.write('forms', JSON.stringify(CampusFormStore.registrations().filter(row => row.id !== id)))
  }
  static snapshot(feature: string): CampusFormData {
    return CampusFormData.read(CampusFormStore.read(feature), feature)
  }
  static update(id: string): void {
    const row = CampusFormStore.registrations().find(item => item.id === id)
    if (row) CampusFormStore.deliver(row.id, CampusFormStore.snapshot(row.feature), row.dimension)
  }
  private static deliver(id: string, data: CampusFormData, dimension: number): void {
    data.dimension = [1, 2, 3].includes(dimension) ? dimension : 2
    formProvider.updateForm(id, formBindingData.createFormBindingData(JSON.stringify(data)))
      .catch(() => { /* Temporary previews may have been removed by the launcher. */ })
  }
  static publish(data: CampusFormData): void {
    if (!CampusFormData.supports(data.feature) || !CampusFormStore.directory) return
    const encoded = JSON.stringify(data)
    if (CampusFormStore.read(data.feature) === encoded) return
    CampusFormStore.write(data.feature, encoded)
    const snapshot = CampusFormData.read(encoded, data.feature)
    for (const row of CampusFormStore.registrations()) if (row.feature === data.feature) CampusFormStore.deliver(row.id, snapshot, row.dimension)
  }
  static clear(): void {
    for (const feature of ['timetable', 'card', 'electricity', 'bus']) CampusFormStore.publish(CampusFormData.empty(feature))
  }
}
