import { Person } from '../model/Person'
import { FduRepository } from '../repository/FduRepository'
import { CardRepository } from '../repository/CardRepository'
import { CampusService } from './CampusService'
import { AppState } from './AppState'
import { EhallRepository } from '../repository/EhallRepository'
import { HttpError } from '../util/HttpUtil'

/** Display only authenticated fields; an empty UIS profile is not a fake name/avatar. */
export class AccountIdentity {
  private static flight: Promise<string> | null = null
  private static flightOwner: string = ''
  private static retryOwner: string = ''
  private static retryAt: number = 0
  static readonly KEY_NAME: string = 'account_verified_name'
  static readonly KEY_OWNER: string = 'account_verified_name_owner'
  static readonly KEY_REVISION: string = 'account_identity_revision'
  static text(value: string | undefined): string { return typeof value === 'string' ? value.trim() : '' }
  static profileName(person: Person, verifiedName: string = ''): string {
    return AccountIdentity.text(person.getInfo()?.name) || AccountIdentity.text(verifiedName)
  }
  /** Process-only identity cache. A changed credential/profile snapshot cannot
   * display the previous account's asynchronously retrieved name. */
  static cachedName(person: Person): string {
    const name: string = AccountIdentity.profileName(person)
    if (name) return name
    if (!person.isLoggedIn() || !AccountIdentity.id(person) || AppStorage.get<string>(AccountIdentity.KEY_OWNER) !== person.toJson()) return ''
    return AccountIdentity.text(AppStorage.get<string>(AccountIdentity.KEY_NAME))
  }
  static publishName(person: Person, name: string): void {
    const value: string = AccountIdentity.text(name)
    if (!value || !person.isLoggedIn() || person.toJson() !== AppStorage.get<string>(AppState.KEY_PERSON) ||
      !AppStorage.get<boolean>(AppState.KEY_IS_LOGGED_IN)) return
    if (AppStorage.get<string>(AccountIdentity.KEY_OWNER) === person.toJson() &&
      AppStorage.get<string>(AccountIdentity.KEY_NAME) === value) return
    AppStorage.setOrCreate<string>(AccountIdentity.KEY_OWNER, person.toJson())
    AppStorage.setOrCreate<string>(AccountIdentity.KEY_NAME, value)
    AccountIdentity.publishRevision()
  }
  static clearIfOwnerChanged(person: Person): void {
    const owner: string = AppStorage.get<string>(AccountIdentity.KEY_OWNER) ?? ''
    if (!owner || (person.isLoggedIn() && owner === person.toJson())) return
    AccountIdentity.clearName()
  }
  static clearName(): void {
    if (!(AppStorage.get<string>(AccountIdentity.KEY_OWNER) ?? '') && !(AppStorage.get<string>(AccountIdentity.KEY_NAME) ?? '')) return
    AppStorage.setOrCreate<string>(AccountIdentity.KEY_OWNER, '')
    AppStorage.setOrCreate<string>(AccountIdentity.KEY_NAME, '')
    AccountIdentity.publishRevision()
  }
  private static publishRevision(): void {
    AppStorage.setOrCreate<number>(AccountIdentity.KEY_REVISION, (AppStorage.get<number>(AccountIdentity.KEY_REVISION) ?? 0) + 1)
  }
  static id(person: Person): string {
    return AccountIdentity.text(person.getInfo()?.studentId) || AccountIdentity.text(person.getInfo()?.id)
  }
  static details(person: Person): string {
    const department: string = AccountIdentity.text(person.getInfo()?.department)
    const grade: string = AccountIdentity.text(person.getInfo()?.grade)
    return department + (department && grade ? ' · ' : '') + grade
  }
  static email(person: Person): string { return AccountIdentity.text(person.getInfo()?.email) }
  static avatar(person: Person): string {
    const source: string = AccountIdentity.text(person.getInfo()?.avatarUrl)
    return /^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i.test(source) ? source : ''
  }

  /** One passive profile read shared by Campus and My, with a failure cooldown.
   * This never opens a browser; the existing shared SSO session is used on demand. */
  static async syncName(person: Person, force: boolean = false): Promise<string> {
    const name: string = AccountIdentity.cachedName(person)
    if (name || !person.isLoggedIn() || !AccountIdentity.id(person)) return name
    const owner: string = person.toJson()
    if (owner !== AppStorage.get<string>(AppState.KEY_PERSON) || !AppState.isLoggedIn()) return ''
    if (AccountIdentity.flight !== null && AccountIdentity.flightOwner === owner) return AccountIdentity.flight
    if (!force && owner === AccountIdentity.retryOwner && Date.now() < AccountIdentity.retryAt) return ''
    const task: Promise<string> = AccountIdentity.readName(person)
    AccountIdentity.flightOwner = owner; AccountIdentity.flight = task
    try { return await task } finally {
      if (AccountIdentity.flight === task) {
        AccountIdentity.flight = null
        AccountIdentity.retryOwner = owner; AccountIdentity.retryAt = Date.now() + 5 * 60 * 1000
      }
    }
  }
  private static async readName(person: Person): Promise<string> {
    let name: string = ''; let department: string = ''
    try {
      const profile = await FduRepository.getInstance().withService(CampusService.EHALL,
        (cookies: string) => new EhallRepository().studentInfo(cookies))
      name = profile.name; department = profile.department
    } catch (error) {
      // Original login only falls back for a profile format/service problem.
      // Timeout/MFA must not start a second protected-service request.
      if (error instanceof HttpError && (error.statusCode === -1 || error.statusCode === -2 || error.statusCode === 401 ||
        error.name === 'EhallProfileUnavailableError')) return ''
      try { name = await AccountIdentity.verifiedName(person) } catch (fallbackError) { return '' }
    }
    if (await AppState.updateIdentity(person.toJson(), name, department)) return name
    return ''
  }

  /** Upstream ecard_repository.getName calls loadCardInfo(-1). Reuse that cache
   * only when its service is already verified, so opening My never adds an MFA page. */
  static async verifiedName(person: Person): Promise<string> {
    const name: string = AccountIdentity.profileName(person)
    if (name || !person.isLoggedIn() || !AccountIdentity.id(person)) return name
    const cookies: string = FduRepository.getInstance().cookiesFor(CampusService.ECARD)
    if (!cookies) return ''
    const repository: CardRepository = CardRepository.getInstance()
    repository.setSession(cookies)
    return AccountIdentity.text((await repository.getCardInfo(-1)).name)
  }
}
