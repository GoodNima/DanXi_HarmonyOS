import { BaseRepository } from './BaseRepository'
import { HttpError, HttpUtil } from '../util/HttpUtil'

export interface EhallStudentInfo { name: string; identity: string; department: string }
interface EhallProfileWire { name?: string; identity?: string; depart?: string }

/** Original ehall_repository.dart: one GET, window.userInfoDSL, no script execution. */
export class EhallRepository extends BaseRepository {
  static readonly INFO_URL: string = 'https://ehall.fudan.edu.cn/'
  async studentInfo(cookies: string): Promise<EhallStudentInfo> {
    const response = await this.httpUtil.get(EhallRepository.INFO_URL, undefined,
      { 'Cookie': cookies, 'User-Agent': HttpUtil.BROWSER_UA, 'Accept': 'text/html' }, 8000)
    return EhallRepository.parseStudentInfo(response.data)
  }
  static parseStudentInfo(body: string): EhallStudentInfo {
    if (body.length > 2 * 1024 * 1024) throw new Error('Account profile response is too large')
    const marker = /window\s*\.\s*userInfoDSL\s*=\s*\{/.exec(body)
    if (marker === null) {
      throw new HttpError(-2, 0, '一站式服务大厅尚未返回登录后的用户资料，请继续身份验证。', '')
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
        const wire: EhallProfileWire = JSON.parse(body.substring(start, index + 1)) as EhallProfileWire
        if (wire.name !== undefined && typeof wire.name !== 'string') throw new Error('Account profile name has an invalid format')
        const name: string = typeof wire.name === 'string' ? wire.name.trim() : ''
        if (!name) throw new HttpError(-2, 0, '一站式服务大厅会话已失效，请继续身份验证。', '')
        if (name.length > 100 || /[\x00-\x1f<>]/.test(name)) throw new Error('Account profile contains no valid name')
        return { name: name, identity: typeof wire.identity === 'string' ? wire.identity.trim() : '',
          department: typeof wire.depart === 'string' ? wire.depart.trim().substring(0, 160) : '' }
      }
    }
    throw new Error('Account profile JSON is incomplete')
  }
}
