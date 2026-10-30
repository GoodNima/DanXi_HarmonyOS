import { asset } from '@kit.AssetStoreKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'

interface CampusCredential { owner: string; password: string }

/** One account-bound credential held by the OS secure asset service, never Preferences. */
export class CampusCredentialStore {
  private static readonly ALIAS: string = 'danta.campus-credential.v1'
  private static owner: string = ''
  private static epoch: number = 0
  private static operations: Promise<void> = Promise.resolve()
  private static loadState: string = 'not-started'
  private static loadCode: number = 0
  private static saveState: string = 'not-started'
  private static saveCode: number = 0

  /** Status and native error codes only; no account, alias, payload or secret. */
  static diagnostics(): string {
    return 'credentialLoad=' + CampusCredentialStore.loadState + '; credentialLoadCode=' + String(CampusCredentialStore.loadCode) +
      '; credentialSave=' + CampusCredentialStore.saveState + '; credentialSaveCode=' + String(CampusCredentialStore.saveCode)
  }

  static bind(owner: string): void {
    if (CampusCredentialStore.owner === owner) return
    const previous = CampusCredentialStore.owner
    CampusCredentialStore.owner = owner
    CampusCredentialStore.epoch++
    CampusCredentialStore.loadState = 'not-started'; CampusCredentialStore.loadCode = 0
    CampusCredentialStore.saveState = 'not-started'; CampusCredentialStore.saveCode = 0
    if (previous) CampusCredentialStore.serial<void>(() => CampusCredentialStore.remove()).catch(() => {})
  }

  static save(owner: string, password: string): Promise<void> {
    const epoch = CampusCredentialStore.epoch
    if (!owner || !password || owner !== CampusCredentialStore.owner) return Promise.resolve()
    const credential: CampusCredential = { owner: owner, password: password }
    const secret = new util.TextEncoder().encodeInto(JSON.stringify(credential))
    return CampusCredentialStore.serial<void>(async (): Promise<void> => {
      let state: string = 'cancelled'
      let code: number = 0
      try {
        if (epoch !== CampusCredentialStore.epoch || owner !== CampusCredentialStore.owner) return
        const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>()
        attributes.set(asset.Tag.SECRET, secret)
        try { await asset.update(CampusCredentialStore.query(), attributes) }
        catch (e) {
          if ((e as BusinessError).code !== asset.ErrorCode.NOT_FOUND) throw e as Error
          if (epoch !== CampusCredentialStore.epoch || owner !== CampusCredentialStore.owner) return
          attributes.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(CampusCredentialStore.ALIAS))
          attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED)
          attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER)
          await asset.add(attributes)
        }
        state = 'saved'
      } catch (error) {
        code = CampusCredentialStore.errorCode(error as BusinessError)
        state = code === 24000005 ? 'locked' : 'unavailable'
        throw error as Error
      } finally {
        secret.fill(0)
        if (epoch === CampusCredentialStore.epoch && owner === CampusCredentialStore.owner) {
          CampusCredentialStore.saveState = state; CampusCredentialStore.saveCode = code
        }
      }
    })
  }

  static load(owner: string): Promise<string> {
    const epoch = CampusCredentialStore.epoch
    if (!owner || owner !== CampusCredentialStore.owner) return Promise.resolve('')
    return CampusCredentialStore.serial<string>(async (): Promise<string> => {
      let secret: Uint8Array | null = null
      let state: string = 'cancelled'
      let code: number = 0
      try {
        if (epoch !== CampusCredentialStore.epoch || owner !== CampusCredentialStore.owner) return ''
        const query = CampusCredentialStore.query()
        query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
        const rows: asset.AssetMap[] = await asset.query(query)
        const value = rows[0]?.get(asset.Tag.SECRET)
        if (!(value instanceof Uint8Array)) { state = 'invalid-payload'; return '' }
        secret = value
        if (epoch !== CampusCredentialStore.epoch || owner !== CampusCredentialStore.owner) return ''
        let credential: CampusCredential
        try { credential = JSON.parse(new util.TextDecoder().decodeToString(secret)) as CampusCredential }
        catch (error) { state = 'invalid-payload'; return '' }
        if (credential === null || typeof credential.owner !== 'string' || typeof credential.password !== 'string') {
          state = 'invalid-payload'; return ''
        }
        if (credential.owner !== owner) { state = 'account-mismatch'; return '' }
        state = credential.password.length > 0 ? 'loaded' : 'empty'
        return credential.password
      } catch (e) {
        // Missing legacy credentials, locked storage and unavailable devices keep manual login working.
        code = CampusCredentialStore.errorCode(e as BusinessError)
        // Keep this catch independent of the optional native API object: an
        // unavailable Asset service must remain a safe manual-login fallback.
        state = code === 24000002 ? 'absent' : code === 24000005 ? 'locked' : 'unavailable'
        return ''
      } finally {
        secret?.fill(0)
        if (epoch === CampusCredentialStore.epoch && owner === CampusCredentialStore.owner) {
          CampusCredentialStore.loadState = state; CampusCredentialStore.loadCode = code
        }
      }
    })
  }

  static clear(): Promise<void> {
    CampusCredentialStore.owner = ''
    CampusCredentialStore.epoch++
    CampusCredentialStore.loadState = 'cleared'; CampusCredentialStore.loadCode = 0
    CampusCredentialStore.saveState = 'not-started'; CampusCredentialStore.saveCode = 0
    return CampusCredentialStore.serial<void>(async (): Promise<void> => {
      await CampusCredentialStore.remove()
    })
  }

  private static async remove(): Promise<void> {
    try { await asset.remove(CampusCredentialStore.query()) }
    catch (e) { if ((e as BusinessError).code !== asset.ErrorCode.NOT_FOUND) throw e as Error }
  }

  private static errorCode(error: BusinessError): number {
    return typeof error.code === 'number' && Number.isFinite(error.code) ? error.code : 0
  }

  private static query(): asset.AssetMap {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>()
    query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(CampusCredentialStore.ALIAS))
    return query
  }

  private static serial<T>(operation: () => Promise<T>): Promise<T> {
    const task = CampusCredentialStore.operations.then(operation, operation)
    CampusCredentialStore.operations = task.then(() => {}, () => {})
    return task
  }
}
