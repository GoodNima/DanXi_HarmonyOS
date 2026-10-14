import { ForumFloor, ForumHole } from './Forum'

/** Quote reads stay behind an account-scoped source boundary. Native fixtures
 * can supply an in-memory source without credentials or production networking. */
export interface ForumQuoteRepository {
  getFloor(id: number): Promise<ForumFloor>
  getHole(id: number): Promise<ForumHole>
  sessionRevision(): number
}
