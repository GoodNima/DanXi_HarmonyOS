/** Keep long feeds lazy while preserving existing rows when the next page arrives. */
export class ForumListSource<T> implements IDataSource {
  private items: T[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number { return this.items.length }
  getData(index: number): T { return this.items[index] }

  prepend(items: T[]): void {
    if (items.length === 0) return
    this.items = items.concat(this.items)
    // Insert notifications preserve the mounted rows and let native List
    // maintain their viewport position. Reloading here discards that anchor.
    for (const listener of this.listeners) {
      for (let i: number = 0; i < items.length; i++) listener.onDataAdd(i)
    }
  }
  changed(index: number): void {
    if (index < 0 || index >= this.items.length) return
    for (const listener of this.listeners) listener.onDataChange(index)
  }

  update(items: T[]): void {
    const previous: T[] = this.items
    this.items = items.slice()
    const appended: boolean = items.length >= previous.length &&
      previous.every((item: T, index: number) => item === items[index])
    for (const listener of this.listeners) {
      if (appended) {
        for (let i: number = previous.length; i < items.length; i++) listener.onDataAdd(i)
      } else listener.onDataReloaded()
    }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener)
  }
}
