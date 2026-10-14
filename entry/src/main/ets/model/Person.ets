/**
 * Person model - represents logged-in user.
 * Ported from lib/model/person.dart
 */

export interface PersonInfo {
  id: string
  name: string
  studentId: string
  department: string
  grade: string
  email: string
  gender: string
  avatarUrl: string
}

interface PersonData {
  academicGroup?: string
  info: PersonInfo | null
  token: string
  loginTime: number
}

export class Person {
  academicGroup: string = 'unknown'
  private info: PersonInfo | null = null
  private token: string = ''
  private loginTime: number = 0

  constructor(info?: PersonInfo, token?: string) {
    if (info) this.info = info
    if (token) this.token = token
    this.loginTime = Date.now()
  }

  getInfo(): PersonInfo | null {
    return this.info
  }

  setInfo(info: PersonInfo): void {
    this.info = info
  }

  getToken(): string {
    return this.token
  }

  setToken(token: string): void {
    this.token = token
  }

  isLoggedIn(): boolean {
    return this.info !== null && this.token !== ''
  }

  getDisplayName(): string {
    return this.info?.name ?? '未登录'
  }

  getStudentId(): string {
    return this.info?.studentId ?? ''
  }

  getDepartment(): string {
    return this.info?.department ?? ''
  }

  getGrade(): string {
    return this.info?.grade ?? ''
  }

  toJson(): string {
    return JSON.stringify({
      academicGroup: this.academicGroup,
      info: this.info,
      token: this.token,
      loginTime: this.loginTime,
    } as PersonData)
  }

  static fromJson(json: string): Person {
    try {
      const data: PersonData = JSON.parse(json) as PersonData
      const person = new Person(data.info ?? undefined, data.token)
      person.academicGroup = data.academicGroup === 'undergraduate' || data.academicGroup === 'postgraduate' ? data.academicGroup : 'unknown'
      person.loginTime = data.loginTime ?? 0
      return person
    } catch (e) {
      return new Person()
    }
  }

  logout(): void {
    this.info = null
    this.token = ''
    this.loginTime = 0
  }
}
