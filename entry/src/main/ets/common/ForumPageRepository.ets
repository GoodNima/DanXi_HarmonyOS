import { ForumDivision, ForumFloor, ForumHole, ForumUser } from '../model/Forum'

/** Feed dependency boundary: native fixtures use an in-memory session without persisting credentials. */
export interface ForumPageRepository {
  restoreSession(): Promise<boolean>
  sessionRevision(): number
  peekCachedDivisions(): ForumDivision[]
  getMe(force?: boolean): Promise<ForumUser>
  getDivisions(force?: boolean): Promise<ForumDivision[]>
  getHomepageHoles(startTimeMs: number, size?: number, order?: string): Promise<ForumHole[]>
  getDivisionHoles(startTimeMs: number, divisionId: number, tag: string, length?: number,
    order?: string): Promise<ForumHole[]>
  searchFloors(keyword: string, offset?: number, size?: number, accurate?: boolean): Promise<ForumFloor[]>
}
