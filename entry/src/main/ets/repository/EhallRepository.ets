import { BaseRepository } from './BaseRepository'
import { HttpError, HttpUtil } from '../util/HttpUtil'
import { FduAuthPolicy } from '../model/FduAuth'

export interface EhallStudentInfo { name: string; identity: string; department: string }
interface EhallProfileWire { name?: string; identity?: string; depart?: string }

/** Original ehall_repository.dart: one GET, window.userInfoDSL, no script execution. */
export class EhallRepository extends BaseRepository {
  static readonly INFO_URL: string = 'https://ehall.fudan.edu.cn/'
  async studentInfo(cookies: string): Promise<EhallStudentInfo> {
    const response = await this.httpUtil.get(EhallRepository.INFO_URL, undefined,
      { 'Cookie': cookies, 'User-Agent': HttpUtil.BROWSER_UA, 'Accept': 'text/html' }, 8000)
    try { return EhallRepository.parseStudentInfo(response.data) }
    catch (error) {
      if (error instanceof HttpError && response.diagnostics) error.diagnostics += '\n' + response.diagnostics
      throw error as Error
    }
  }
  static parseStudentInfo(body: string): EhallStudentInfo {
    if (body.length > 2 * 1024 * 1024) throw EhallRepository.protocol('response-too-large')
    if (FduAuthPolicy.isLoginDocument(body)) throw new HttpError(-2, 0, '一站式服务大厅会话已失效，请继续身份验证。', '', '', false,
      'stage=ehall-profile; proof=login-document')
    const marker = /window\s*\.\s*userInfoDSL\s*=\s*\{/.exec(body)
    if (marker === null) {
      throw EhallRepository.protocol('missing-profile-marker')
    }
    const start: number = marker.index + marker[0].length - 1
    let depth: number = 0; let quoted: boolean = false; let escaped: boolean = false
    for (let index: number = start; index < Math.min(body.length, start + 65536); index++) {
      const value: string = body[index]
      if (quoted) {
        if (escaped) escaped = false
        else if (value === '\\') escaped = true
        else if (value === '"') quoted = false
      } else if (value === '"') quoted = true
      else if (value === '{') depth++
      else if (value === '}' && --depth === 0) {
        let wire: EhallProfileWire
        try { wire = JSON.parse(body.substring(start, index + 1)) as EhallProfileWire }
        catch (error) { throw EhallRepository.protocol('invalid-profile-json') }
        if (wire.name !== undefined && typeof wire.name !== 'string') throw EhallRepository.protocol('invalid-profile-name')
        const name: string = typeof wire.name === 'string' ? wire.name.trim() : ''
        if (!name) throw EhallRepository.protocol('missing-profile-name')
        if (name.length > 100 || /[\x00-\x1f<>]/.test(name)) throw EhallRepository.protocol('invalid-profile-name')
        return { name: name, identity: typeof wire.identity === 'string' ? wire.identity.trim() : '',
          department: typeof wire.depart === 'string' ? wire.depart.trim().substring(0, 160) : '' }
      }
    }
    throw EhallRepository.protocol('incomplete-profile-json')
  }
  private static protocol(reason: string): HttpError {
    const error = new HttpError(200, 0, '校园账户资料暂时无法读取，请稍后重新加载。', '', '', false,
      'stage=ehall-profile; EhallProfileProtocolError; reason=' + reason)
    error.name = reason === 'missing-profile-marker' || reason === 'missing-profile-name' ?
      'EhallProfileUnavailableError' : 'EhallProfileProtocolError'
    return error
  }
}
