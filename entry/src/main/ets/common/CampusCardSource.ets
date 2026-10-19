import { AppState } from './AppState'
import { CampusService } from './CampusService'
import { FduRepository } from '../repository/FduRepository'
import { CardRepository } from '../repository/CardRepository'
import { CardInfo, CardRecord } from '../model/Card'

/** Production service reads and the native page share one typed request contract. */
export interface CampusCardSource {
  owner(): string
  canVerify(): boolean
  needsVerification(): boolean
  verify(): Promise<string>
  read(days: number, force: boolean, onBalance: (info: CardInfo) => void,
    onProgress: (page: number, total: number) => void): Promise<CardInfo>
}
export class DefaultCampusCardSource implements CampusCardSource {
  owner(): string { const person = AppState.getPerson(); return person.getStudentId() + ':' + person.getToken() }
  canVerify(): boolean { return FduRepository.getInstance().canLoginOnDemand() }
  needsVerification(): boolean { return FduRepository.getInstance().needsVerification(CampusService.ECARD) }
  verify(): Promise<string> { return FduRepository.getInstance().verifyService(CampusService.ECARD) }
  read(days: number, force: boolean, onBalance: (info: CardInfo) => void,
    onProgress: (page: number, total: number) => void): Promise<CardInfo> {
    return FduRepository.getInstance().withService(CampusService.ECARD, async (cookies: string): Promise<CardInfo> => {
      const repository = CardRepository.getInstance()
      repository.setSession(cookies)
      if (force) repository.invalidate()
      const balance = await repository.getCardInfo(-1)
      onBalance(balance)
      const records = await repository.getCardRecords(days, onProgress, (rows: CardRecord[]) => {
        onBalance({ name: balance.name, cash: balance.cash, records: rows })
      })
      return { name: balance.name, cash: balance.cash, records: records }
    })
  }
}
