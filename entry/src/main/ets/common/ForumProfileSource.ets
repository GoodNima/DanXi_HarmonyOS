import { ForumRepository } from '../repository/ForumRepository'
import { ForumUser } from '../model/Forum'

/** The default source retains repository-owned session publication. Test hosts
 * can supply an in-memory subclass without creating or persisting credentials. */
export class ForumProfileSource {
  sessionRevision(): number { return ForumRepository.getInstance().sessionRevision() }
  restoreSession(): Promise<boolean> { return ForumRepository.getInstance().restoreSession() }
  isLoggedIn(): boolean { return ForumRepository.getInstance().isLoggedIn() }
  getMe(): Promise<ForumUser> { return ForumRepository.getInstance().getMe() }
}
