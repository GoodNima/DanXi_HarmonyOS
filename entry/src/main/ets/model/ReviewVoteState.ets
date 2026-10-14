import { CourseReview } from './CourseReview'

@Observed
export class ReviewVoteState {
  votes: number = 0
  myVote: number = 0
  deleted: boolean = false
  pending: boolean = false
  constructor(review: CourseReview) { this.update(review) }
  update(review: CourseReview): void { this.votes = review.votes; this.myVote = review.myVote; this.deleted = review.deleted }
}
