import { CampusHtml } from './CampusHtml'
import { HttpError } from '../util/HttpUtil'

export interface BookingField { name: string; type: string; verifyType?: string }
export interface BookingCollected { name: string; value: string; type: string; verify?: string }
interface BookingRich { text?: string; enanle?: boolean | number | string }
interface BookingConfig { data_colle?: BookingField[]; introduction?: BookingRich; description?: BookingRich; anti_bot?: number | string }
interface VenueWire { id: number; name: string; type: number; icon?: string; images?: string; config?: BookingConfig }
interface VenueEntry { base: VenueWire }
interface VenuePageWire { data: VenueEntry[]; total: number; page: number | string; perpage: number | string }
interface VenueLimit { error?: string }
interface DetailWire extends VenueWire { usable: boolean; limit_info?: string | VenueLimit; exclusive?: boolean | number | string; is_group?: boolean | number | string; rule?: BookingServiceTime[] }
export interface BookingServiceTime { start_time: string; end_time: string }
export class BookingVenue {
  id: number = 0; name: string = ''; image: string = ''; introduction: string = ''; fields: BookingField[] = []
}
export class BookingDetail extends BookingVenue {
  usable: boolean = false; limit: string = ''; rules: string = ''; captcha: boolean = false; serviceTimes: BookingServiceTime[] = []
}
export interface BookingPeriod { id: number; str_time: string; start_time: string; end_time: string }
export interface BookingCourt { id: number; name: string }
export interface BookingAvailability { status: number; total: number; num: number | string }
export class BookingCalendar {
  day: string[] = []; time: BookingPeriod[] = []; resource: BookingCourt[] = []
  data: Record<string, Record<string, Record<string, BookingAvailability>>> = {}
  available(day: string, period: number): BookingCourt[] {
    return this.resource.filter((court: BookingCourt) => {
      const value = this.data[day]?.[String(court.id)]?.[String(period)]
      return value !== undefined && value.status === 0 && Number(value.num) > 0
    })
  }
}
export interface BookingContact { mobile: string; id_card: string }
export interface BookingOccupant { id: number; name: string; number?: string; mobile?: string; department_name?: string; collective?: boolean; show_system?: boolean }
export interface BookingPeriodDetail { detail_id: number; date: string; period_id: number; str_time: string; start_time: string; end_time: string; can_cancel: boolean | number | string }
interface BookingDay { periods: BookingPeriodDetail[] }
interface BookingGroup { dates: BookingDay[] }
interface BookingTimes { groups: BookingGroup[] }
interface AppointmentWire { id: number; resource_name: string; status_name: string; created: string; is_cancel: boolean | number | string; appointment_time: BookingTimes }
export class BookingAppointment {
  id: number = 0; name: string = ''; status: string = ''; created: string = ''; canCancel: boolean = false; periods: BookingPeriodDetail[] = []
}
export class BookingAppointments { rows: BookingAppointment[] = []; hasMore: boolean = false }
interface AppointmentPageWire { data: AppointmentWire[]; total: number; page: number | string; perpage: number | string }
interface OccupantPageWire { data: BookingOccupant[]; total: number; page: number | string; perpage: number | string }
export class BookingOccupants { rows: BookingOccupant[] = []; hasMore: boolean = false }
export interface BookingLaunch { group: number; resources: number[]; date: string; period: number; number: number; fields: BookingCollected[] }
export interface BookingLaunchResult { is_relate: boolean; process_id: number; process_url: string }
interface BookingLaunchPeriod { date: string; period_id: number }
interface BookingLaunchData { resource_ids: number[]; group_id: number; period: BookingLaunchPeriod[]; number: number }
interface BookingCaptcha { token: string; pointJson: string }
interface BookingEnvelope<T> { e: string | number; m?: string; d: T }
export class SportsBooking {
  static readonly ORIGIN: string = 'https://booking.fudan.edu.cn'
  static readonly HOME: string = SportsBooking.ORIGIN + '/reservation/fe/site/home'
  static readonly LOGIN: string = SportsBooking.ORIGIN + '/reservation/api/login/main?redirect_url=' + encodeURIComponent(SportsBooking.HOME)
  static readonly TOPIC: string = SportsBooking.ORIGIN + '/reservation/fe/site/special/special?id=48'
  static readonly APPOINTMENTS: string = SportsBooking.ORIGIN + '/reservation/fe/site/m_myReservation'
  static readonly TYPES: string[] = ['篮球', '排球', '羽毛球', '网球', '足球', '舞蹈房', '乒乓球']
  static page(id: number): string { return SportsBooking.ORIGIN + '/reservation/fe/site/m_launchReservation?id=' + id }
  static data<T>(body: string): T {
    if (body.length > 4 * 1024 * 1024) throw new Error('Booking response is too large')
    const envelope = JSON.parse(body) as BookingEnvelope<T>
    if (String(envelope.e) === 'UN_AUTH') throw new HttpError(-2, 0, '场馆预约需要校园身份验证，请点击继续验证。', '')
    if (!['OK', '0'].includes(String(envelope.e))) throw new Error('Booking ' + String(envelope.e) + ': ' + (envelope.m || '预约服务请求失败'))
    if (envelope.d === undefined || envelope.d === null) throw new Error('Booking response data is missing')
    return envelope.d
  }
  static boolean(value: boolean | number | string): boolean { return value === true || value === 1 || value === '1' || value === 'true' }
  private static text(value: BookingRich | undefined): string {
    return value === undefined || (value.enanle !== undefined && !SportsBooking.boolean(value.enanle)) ? '' :
      CampusHtml.decode((value.text ?? '').replace(/<\/(?:p|div)>/gi, '\n').replace(/<br\s*\/?\s*>/gi, '\n').replace(/<[^>]*>/g, '')).trim()
  }
  static venues(body: string): BookingVenue[] {
    const data = SportsBooking.data<VenuePageWire>(body)
    if (!Array.isArray(data.data) || !Number.isSafeInteger(data.total)) throw new Error('Invalid booking venue page')
    return data.data.map((entry: VenueEntry): BookingVenue => SportsBooking.venue(entry.base))
  }
  static total(body: string): number { return SportsBooking.data<VenuePageWire>(body).total }
  private static venue(wire: VenueWire): BookingVenue {
    if (!wire || !Number.isSafeInteger(wire.id) || typeof wire.name !== 'string') throw new Error('Invalid booking venue')
    const value = new BookingVenue(); value.id = wire.id; value.name = wire.name
    value.image = wire.images || wire.icon || ''; value.fields = wire.config?.data_colle ?? []; value.introduction = SportsBooking.text(wire.config?.introduction); return value
  }
  static detail(body: string): BookingDetail {
    const wire = SportsBooking.data<DetailWire>(body), base = SportsBooking.venue(wire), value = new BookingDetail()
    value.id = base.id; value.name = base.name; value.image = base.image; value.fields = base.fields; value.introduction = base.introduction
    value.usable = wire.usable === true; value.limit = typeof wire.limit_info === 'string' ? wire.limit_info : wire.limit_info?.error ?? ''
    value.rules = SportsBooking.text(wire.config?.description); value.captcha = Number(wire.config?.anti_bot ?? 0) !== 0; value.serviceTimes = wire.rule ?? []; return value
  }
  static calendar(body: string): BookingCalendar {
    const wire = SportsBooking.data<BookingCalendar>(body)
    if (!Array.isArray(wire.time) || !Array.isArray(wire.resource) || !Array.isArray(wire.day) || wire.data === null || typeof wire.data !== 'object') throw new Error('Invalid booking calendar')
    const value = new BookingCalendar(); value.day = wire.day; value.time = wire.time; value.resource = wire.resource; value.data = wire.data; return value
  }
  static appointments(body: string, page: number): BookingAppointments {
    const wire = SportsBooking.data<AppointmentPageWire>(body)
    if (!Array.isArray(wire.data) || !Number.isSafeInteger(wire.total)) throw new Error('Invalid booking appointment page')
    const result = new BookingAppointments()
    result.rows = wire.data.map((row: AppointmentWire): BookingAppointment => {
      const value = new BookingAppointment(); value.id = row.id; value.name = row.resource_name; value.status = row.status_name; value.created = row.created
      value.canCancel = SportsBooking.boolean(row.is_cancel); value.periods = row.appointment_time.groups.flatMap((group: BookingGroup) => group.dates.flatMap((day: BookingDay) => day.periods))
        .sort((a: BookingPeriodDetail, b: BookingPeriodDetail) => (a.date + a.start_time).localeCompare(b.date + b.start_time)); return value
    })
    result.hasMore = result.rows.length > 0 && page * Number(wire.perpage) < wire.total; return result
  }
  static occupants(body: string, page: number): BookingOccupants {
    const wire = SportsBooking.data<OccupantPageWire>(body)
    if (!Array.isArray(wire.data)) throw new Error('Invalid booking reservation information')
    const result = new BookingOccupants(); result.rows = wire.data; result.hasMore = result.rows.length > 0 && page * Number(wire.perpage) < wire.total; return result
  }
  static environment(venue: BookingVenue): string {
    const name: string = venue.name.split('-')[0]
    return /体育馆|活动中心|舞蹈房/.test(name) ? '室内' : '室外'
  }
  static filter(rows: BookingVenue[], query: string, campus: string, type: string, environment: string): BookingVenue[] {
    return rows.filter((row: BookingVenue) => (!query || row.name.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())) &&
      (!campus || row.name.includes(campus)) && (!type || row.name.includes(type)) && (!environment || SportsBooking.environment(row) === environment))
  }
  static launchFields(value: BookingLaunch): Record<string, string> {
    if (!Number.isInteger(value.number) || value.number < 1 || value.number > 4 || !Number.isSafeInteger(value.group) || value.group < 1 || !Number.isSafeInteger(value.period) || value.period < 1 || value.resources.length === 0 || value.resources.some((id: number) => !Number.isSafeInteger(id) || id < 1) || !/^\d{4}-\d{2}-\d{2}$/.test(value.date)) throw new Error('Invalid booking launch parameters')
    const data: BookingLaunchData[] = [{ resource_ids: value.resources, group_id: value.group, period: [{ date: value.date, period_id: value.period }], number: value.number }]
    const captcha: BookingCaptcha = { token: '', pointJson: '' }
    const fields: Record<string, string> = {}
    fields['data'] = JSON.stringify(data); fields['data_colle'] = JSON.stringify(value.fields)
    fields['collective'] = '0'; fields['captcha'] = JSON.stringify(captcha)
    return fields
  }
}
