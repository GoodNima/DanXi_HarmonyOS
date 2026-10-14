import { CardRecord } from './Card'

export class CardPresentation {
  static amount(record: CardRecord): string {
    const value = record.payment.trim().replace(/^[+\-−￥¥\s]+/, '')
    if (!value) return '—'
    const sign = record.type.includes('充值') ? '+' : '-'
    return sign + '¥' + value
  }

  static balance(cash: string): string {
    const value = cash.trim().replace(/^[￥¥\s]+/, '')
    return value ? '¥' + value : '—'
  }

  static isLow(cash: string): boolean {
    const value = Number(cash.trim().replace(/^[￥¥\s]+/, ''))
    return cash.trim().length > 0 && Number.isFinite(value) && value < 20
  }
}
