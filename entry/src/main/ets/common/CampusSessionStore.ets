import { asset } from '@kit.AssetStoreKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { webview } from '@kit.ArkWeb'
import { BusinessError } from '@kit.BasicServicesKit'
import { PreferencesUtil } from '../util/PreferencesUtil'

interface CampusSessionEnvelope {
  version: number
  iv: string
  ciphertext: string
}

/** Account-bound cookie snapshots. Asset Store protects the AES key; only
 * authenticated ciphertext is written to Preferences, without a password. */
export class CampusSessionStore {
  private static readonly STORAGE_KEY: string = 'campus_session_encrypted_v1'
  private static readonly KEY_ALIAS: string = 'danta.campus-session.aes256.v1'
  private static operations: Promise<void> = Promise.resolve()
  private static loadState: string = 'not-started'
  private static loadCode: number = 0

  /** Outcome only. Never returns the encrypted payload, account, key or cookies. */
  static diagnostics(): string {
    return 'secureSnapshot=' + CampusSessionStore.loadState + '; secureCode=' + String(CampusSessionStore.loadCode)
  }

  static save(owner: string, cookies: webview.WebHttpCookie[]): Promise<void> {
    if (!owner) return Promise.resolve()
    // Freeze the browser result before joining the storage queue.
    const plaintext: string = JSON.stringify(cookies)
    return CampusSessionStore.serial<void>(() => CampusSessionStore.saveOnce(owner, plaintext))
  }

  static load(owner: string): Promise<webview.WebHttpCookie[]> {
    if (!owner) return Promise.resolve([])
    return CampusSessionStore.serial<webview.WebHttpCookie[]>(() => CampusSessionStore.loadOnce(owner))
  }

  static clear(): Promise<void> {
    return CampusSessionStore.serial<void>(async (): Promise<void> => {
      // Remove the ciphertext first, including when the secure key is locked.
      await PreferencesUtil.getInstance().remove(CampusSessionStore.STORAGE_KEY)
      try { await asset.remove(CampusSessionStore.keyQuery()) }
      catch (e) { if ((e as BusinessError).code !== asset.ErrorCode.NOT_FOUND) throw e as Error }
    })
  }

  private static serial<T>(operation: () => Promise<T>): Promise<T> {
    const task: Promise<T> = CampusSessionStore.operations.then(operation, operation)
    CampusSessionStore.operations = task.then(() => {}, () => {})
    return task
  }

  private static keyQuery(): asset.AssetMap {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>()
    query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(CampusSessionStore.KEY_ALIAS))
    return query
  }

  private static async key(create: boolean): Promise<cryptoFramework.SymKey> {
    let raw: Uint8Array
    const query: asset.AssetMap = CampusSessionStore.keyQuery()
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
    try {
      const rows: asset.AssetMap[] = await asset.query(query)
      const secret = rows[0]?.get(asset.Tag.SECRET)
      if (!(secret instanceof Uint8Array) || secret.length !== 32) throw new Error('Invalid campus session key')
      raw = new Uint8Array(secret)
    } catch (e) {
      if (!create || (e as BusinessError).code !== asset.ErrorCode.NOT_FOUND) throw e as Error
      raw = cryptoFramework.createRandom().generateRandomSync(32).data
      const attributes: asset.AssetMap = CampusSessionStore.keyQuery()
      attributes.set(asset.Tag.SECRET, raw)
      attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED)
      attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER)
      try { await asset.add(attributes) }
      catch (addError) { raw.fill(0); throw addError as Error }
    }
    try { return await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: raw }) }
    finally { raw.fill(0) }
  }

  private static params(owner: string, iv: Uint8Array, tag: Uint8Array): cryptoFramework.GcmParamsSpec {
    return {
      algName: 'GcmParamsSpec', iv: { data: iv }, authTag: { data: tag },
      aad: { data: new util.TextEncoder().encodeInto('danta.campus-session.v1\n' + owner) }
    }
  }

  private static async saveOnce(owner: string, plaintext: string): Promise<void> {
    const key: cryptoFramework.SymKey = await CampusSessionStore.key(true)
    const plain: Uint8Array = new util.TextEncoder().encodeInto(plaintext)
    try {
      const iv: Uint8Array = cryptoFramework.createRandom().generateRandomSync(12).data
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding')
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key,
        CampusSessionStore.params(owner, iv, new Uint8Array(16)))
      // GCM doFinal returns ciphertext followed by its 16-byte auth tag.
      const encrypted: cryptoFramework.DataBlob = await cipher.doFinal({ data: plain })
      const base64 = new util.Base64Helper()
      const envelope: CampusSessionEnvelope = {
        version: 1, iv: base64.encodeToStringSync(iv), ciphertext: base64.encodeToStringSync(encrypted.data)
      }
      await PreferencesUtil.getInstance().putString(CampusSessionStore.STORAGE_KEY, JSON.stringify(envelope))
    } finally { plain.fill(0); key.clearMem() }
  }

  private static async loadOnce(owner: string): Promise<webview.WebHttpCookie[]> {
    let key: cryptoFramework.SymKey | null = null
    let plaintext: Uint8Array | null = null
    try {
      CampusSessionStore.loadState = 'loading'; CampusSessionStore.loadCode = 0
      const saved = await PreferencesUtil.getInstance().getString(CampusSessionStore.STORAGE_KEY, '')
      if (!saved) { CampusSessionStore.loadState = 'absent'; return [] }
      const envelope = JSON.parse(saved) as CampusSessionEnvelope
      if (envelope.version !== 1 || typeof envelope.iv !== 'string' || typeof envelope.ciphertext !== 'string') {
        CampusSessionStore.loadState = 'invalid-envelope'; return []
      }
      const base64 = new util.Base64Helper()
      const iv: Uint8Array = base64.decodeSync(envelope.iv)
      const encrypted: Uint8Array = base64.decodeSync(envelope.ciphertext)
      if (iv.length !== 12 || encrypted.length < 16) { CampusSessionStore.loadState = 'invalid-envelope'; return [] }
      key = await CampusSessionStore.key(false)
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding')
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key,
        CampusSessionStore.params(owner, iv, encrypted.slice(encrypted.length - 16)))
      const decoded: cryptoFramework.DataBlob = await cipher.doFinal({ data: encrypted.slice(0, encrypted.length - 16) })
      plaintext = decoded.data
      const cookies = JSON.parse(new util.TextDecoder().decodeToString(plaintext)) as webview.WebHttpCookie[]
      CampusSessionStore.loadState = Array.isArray(cookies) ? 'loaded' : 'invalid-payload'
      return Array.isArray(cookies) ? cookies : []
    } catch (e) {
      CampusSessionStore.loadState = 'unavailable'
      const code = (e as BusinessError).code
      CampusSessionStore.loadCode = typeof code === 'number' && Number.isFinite(code) ? code : 0
      // Wrong account, missing device key, locked storage or corrupt ciphertext
      // must never import cookies or expose secret data in an error message.
      return []
    } finally { plaintext?.fill(0); key?.clearMem() }
  }
}
