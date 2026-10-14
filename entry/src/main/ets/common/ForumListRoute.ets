/** One typed route for account collections, notifications and the tag result list. */
export class ForumListRouteParams {
  section: string = 'posts'
  tag: string = ''
  constructor(section: string, tag: string = '') { this.section = section; this.tag = tag.trim().slice(0, 128) }
}
