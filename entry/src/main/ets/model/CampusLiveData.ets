import { ElectricityInfo } from './Academic'
import { DeveloperNotice } from './AnnouncementConfigData'
import { CampusPreviewItem } from './CampusPreviewItem'

/** Server display values are preserved; a missing result is never a synthetic zero. */
export class CampusLiveSummary {
  items: CampusPreviewItem[] = []
  value: string = ''
  description: string = ''
  secondary: string = ''
  updatedAt: number = 0
  status: string = 'ready'
  tone: string = ''
}

export class DiningTraffic {
  name: string = ''
  zone: string = ''
  current: number = 0
  maximum: number = 0
  ratio(): number { return this.maximum > 0 ? this.current / this.maximum : 0 }
}

/** One source document contains all four campuses. Keep the verified read
 * together so a campus selection only changes the local projection. */
export class DiningCampusData {
  error: string = ''
  campus: string = ''
  traffic: DiningTraffic[] = []
}

export class DiningSnapshot {
  campuses: DiningCampusData[] = []
  updatedAt: number = 0
  status: string = 'ready'
  readVersion: number = 0
}

export class LibraryVisitors {
  id: string = ''
  name: string = ''
  visitors: string = ''
  openTime: string = ''
  remaining: number = -1
  capacity: number = 0
  ratio(): number { return this.capacity > 0 ? Number(this.visitors) / this.capacity : 0 }
}

export class ElectricityUsage {
  dormName: string = ''
  date: string = ''
  amount: string = ''
}

export class CampusLiveData {
  feature: string = ''
  campus: string = ''
  dining: DiningTraffic[] = []
  diningCampuses: DiningCampusData[] = []
  libraries: LibraryVisitors[] = []
  electricity: ElectricityInfo | null = null
  history: ElectricityUsage[] = []
  historyUpdatedAt: number = 0
  notices: DeveloperNotice[] = []
  updatedAt: number = 0
  historyError: string = ''
  historyFailure: Object | null = null
  status: string = 'ready'
  diningReadVersion: number = 0
}

export class CampusLiveParams {
  feature: string = 'developer_notice'
}

export class DiningOutsideMealTime extends Error {
  constructor() { super('DiningOutsideMealTime'); this.name = 'DiningOutsideMealTime' }
}
