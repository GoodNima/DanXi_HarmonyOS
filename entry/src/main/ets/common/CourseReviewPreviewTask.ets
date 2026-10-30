import { taskpool } from '@kit.ArkTS'
import { CourseReviewPreview, CourseReviewPreviewParser } from './CourseReviewPreviewParser'

@Concurrent
export function parseCourseReviewPreview(body: string, reviewsOnly: boolean): string {
  return CourseReviewPreviewParser.parse(body, reviewsOnly)
}

export async function readCourseReviewPreview(body: string, reviewsOnly: boolean = false): Promise<CourseReviewPreview> {
  const task = new taskpool.Task(parseCourseReviewPreview, body, reviewsOnly)
  const result = await taskpool.execute(task, taskpool.Priority.LOW) as string
  return JSON.parse(result) as CourseReviewPreview
}
