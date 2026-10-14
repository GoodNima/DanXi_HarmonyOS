/**
 * Campus card (一卡通) model.
 *
 * Ported from lib/model/... via lib/repository/fdu/ecard_repository.dart, which
 * defines `CardInfo` and `CardRecord` inline at the bottom of the repository.
 *
 * Every field is a STRING, not a parsed number or Date, because that is what the
 * server actually sends: the balance arrives as display text and the timestamp
 * as two separate table cells. Parsing them into numbers here would invent
 * precision the source does not have, and would throw on any row whose format
 * differs -- losing the whole page instead of one field.
 */

/**
 * One transaction row of `POST /epay/consume/query`.
 *
 * The upstream builds these from four `<td>` cells:
 *   details[0] -> date cell (two children: the date, then the time)
 *   details[1] -> type
 *   details[2] -> location
 *   details[3] -> payment
 */
export interface CardRecord {
  /** `yyyy-MM-ddTHH:mm`, assembled from the two halves of the first cell. */
  time: string
  /** e.g. 消费 / 充值. */
  type: string
  /** Where the transaction happened. */
  location: string
  /** Amount as display text, sign included. */
  payment: string
}

/**
 * Balance and identity of the card holder, plus whatever records were requested.
 *
 * `name` and `cash` both come from the `myepay` page. The upstream treats an
 * empty name as a hard failure ("Unable to get user name") because that page is
 * only served to a live session -- an empty name means the session silently
 * lapsed and the page returned is the login shell, which must not be rendered
 * as an account with no name and no money.
 */
export interface CardInfo {
  name: string
  /** Balance as display text, e.g. `12.34`. */
  cash: string
  records: CardRecord[]
}
