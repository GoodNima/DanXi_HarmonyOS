import { ForumTag } from '../model/Forum'
import { ForumContentParser } from '../model/ForumContent'

export class ForumComposerDraft {
  content: string = ''
  divisionId: number = 0
  divisionName: string = ''
  tags: ForumTag[] = []
}
export class ForumComposerEdit {
  content: string = ''
  start: number = 0
  end: number = 0
}
/** Upstream NEW_POST lifetime: keep editor drafts in this app session, scoped
 * by forum user, without writing private post text into a shared disk cache. */
export class ForumComposer {
  static readonly LIMIT: number = 2000
  private static drafts: Map<string, string> = new Map<string, string>()
  static restore(owner: string): ForumComposerDraft | undefined {
    const raw = ForumComposer.drafts.get(owner)
    if (raw === undefined) return undefined
    const data = JSON.parse(raw) as ForumComposerDraft
    data.tags = data.tags.map((tag: ForumTag): ForumTag => {
      const copy = new ForumTag(); copy.tagId = tag.tagId; copy.name = tag.name; copy.temperature = tag.temperature; return copy
    })
    return data
  }
  static save(owner: string, draft: ForumComposerDraft): void {
    ForumComposer.drafts.set(owner, JSON.stringify(draft))
    while (ForumComposer.drafts.size > 8) {
      const first: string | undefined = ForumComposer.drafts.keys().next().value
      if (first !== undefined) ForumComposer.drafts.delete(first)
    }
  }
  static clearIf(owner: string, sent: ForumComposerDraft): void {
    if (ForumComposer.drafts.get(owner) === JSON.stringify(sent)) ForumComposer.drafts.delete(owner)
  }
  static insert(text: string, start: number, end: number, before: string, after: string = ''): ForumComposerEdit | undefined {
    const a = Math.max(0, Math.min(text.length, start)); const b = Math.max(a, Math.min(text.length, end))
    const value = text.slice(0, a) + before + text.slice(a, b) + after + text.slice(b)
    if (value.length > ForumComposer.LIMIT) return undefined
    const edit = new ForumComposerEdit(); edit.content = value; edit.start = a + before.length; edit.end = b + before.length; return edit
  }
  static images(content: string): string[] {
    const images = ForumContentParser.parse(content).filter(part => part.kind === 'image').map(part => part.source)
    return images.filter((source: string, index: number) => images.indexOf(source) === index)
  }
  static removeImage(content: string, source: string): string {
    return content.replace(/!\[[^\]]*\]\(([^\s)]+)\)/g, (match: string, url: string): string => url === source ? '' : match)
  }
  static customTag(name: string): ForumTag | undefined {
    const value = name.trim().replace(/^#+/, '').trim()
    if (!value || value.length > 128 || /[\r\n]/.test(value)) return undefined
    const tag = new ForumTag(); tag.name = value; return tag
  }
  static warning(content: string, words: string[]): string {
    const text = content.toLowerCase()
    return words.map(word => word.trim().toLowerCase()).find(word => !!word && text.includes(word)) ?? ''
  }
  static recommendations(tags: ForumTag[], content: string): ForumTag[] {
    const text: string = content.toLowerCase()
    return tags.filter(tag => tag.name.trim().length >= 2 && text.includes(tag.name.toLowerCase()))
      .sort((a: ForumTag, b: ForumTag) => b.temperature - a.temperature).slice(0, 8)
  }
}
