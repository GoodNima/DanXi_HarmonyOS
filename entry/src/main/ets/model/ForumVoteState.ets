import { ForumFloor } from './Forum'

/** A row-local observable: votes never change the list item's identity. */
@Observed
export class ForumVoteState {
  liked: boolean = false
  disliked: boolean = false
  like: number = 0
  dislike: number = 0
  deleted: boolean = false
  pending: boolean = false
  constructor(floor: ForumFloor) { this.update(floor) }
  update(floor: ForumFloor): void {
    this.liked = floor.liked; this.disliked = floor.disliked
    this.like = floor.like; this.dislike = floor.dislike; this.deleted = floor.deleted
  }
}
