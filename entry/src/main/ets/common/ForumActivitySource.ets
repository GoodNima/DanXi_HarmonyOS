import { AnnouncementConfig } from './AnnouncementConfig'
import { AnnouncementSnapshot } from '../model/AnnouncementConfigData'

/** Public announcement dependency shared by feed and campus; fixtures never alter its cache. */
export interface ForumActivitySource {
  peek(): AnnouncementSnapshot
  load(force?: boolean): Promise<AnnouncementSnapshot>
}

export class DefaultForumActivitySource implements ForumActivitySource {
  peek(): AnnouncementSnapshot { return AnnouncementConfig.peek() }
  load(force: boolean = false): Promise<AnnouncementSnapshot> { return AnnouncementConfig.load(force) }
}
