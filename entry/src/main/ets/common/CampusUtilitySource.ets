import { CampusUtilities, CampusUtilitySnapshot } from './CampusUtilities'
import { CourseReviewRepository } from '../repository/CourseReviewRepository'
import { CourseReviewGroup, CourseReviewSearch, CourseReview, CourseReviewDraft } from '../model/CourseReview'

/** The same page can be exercised with an isolated in-memory source. The
 * production adapter always calls the real guarded repositories. */
export interface CampusUtilityPageSource {
  scope(feature: string): string
  load(feature: string, force?: boolean): Promise<CampusUtilitySnapshot>
  random(): Promise<CourseReview>
  search(query: string, page: number, force?: boolean): Promise<CourseReviewSearch>
  summary(id: number): Promise<CourseReviewGroup>
  group(id: number, force?: boolean, previewOnly?: boolean): Promise<CourseReviewGroup>
  add(draft: CourseReviewDraft): Promise<CourseReview>
  modify(review: CourseReview, draft: CourseReviewDraft): Promise<void>
  remove(review: CourseReview): Promise<void>
  vote(id: number, up: boolean): Promise<CourseReview>
}
export class DefaultCampusUtilityPageSource implements CampusUtilityPageSource {
  scope(feature: string): string { return CampusUtilities.scope(feature) }
  load(feature: string, force: boolean = false): Promise<CampusUtilitySnapshot> { return CampusUtilities.load(feature, force) }
  random(): Promise<CourseReview> { return CourseReviewRepository.random() }
  search(query: string, page: number, force: boolean = false): Promise<CourseReviewSearch> { return CourseReviewRepository.search(query, page, force) }
  summary(id: number): Promise<CourseReviewGroup> { return CourseReviewRepository.summary(id) }
  group(id: number, force: boolean = false, previewOnly: boolean = false): Promise<CourseReviewGroup> {
    return CourseReviewRepository.group(id, force, previewOnly)
  }
  add(draft: CourseReviewDraft): Promise<CourseReview> { return CourseReviewRepository.add(draft) }
  modify(review: CourseReview, draft: CourseReviewDraft): Promise<void> { return CourseReviewRepository.modify(review, draft) }
  remove(review: CourseReview): Promise<void> { return CourseReviewRepository.remove(review) }
  vote(id: number, up: boolean): Promise<CourseReview> { return CourseReviewRepository.vote(id, up) }
}
