/** A module keeps the same functional identity in cards, previews and editing.
 * Status colors belong to the information value, not to this category. */
export class CampusCategory {
  static of(id: string): string {
    if (['timetable', 'academic', 'exam', 'gpa', 'course_review'].includes(id)) return 'courses'
    if (['empty_classroom', 'library', 'library_books'].includes(id)) return 'spaces'
    if (id === 'announcement') return 'academic_notice'
    if (['card', 'electricity'].includes(id)) return 'accounts'
    if (['dining', 'sports'].includes(id)) return 'living'
    if (['bus', 'campus_access', 'life_code'].includes(id)) return 'mobility'
    return 'information'
  }

  static color(id: string): ResourceColor {
    const category: string = CampusCategory.of(id)
    // Alternate cool study/space tones with warm notices and daily-life tones.
    // Reuse fixed pigments so category identity does not change with appearance.
    if (category === 'courses') return $r('app.color.campus_palette_indigo')
    if (category === 'spaces') return $r('app.color.campus_palette_teal')
    if (category === 'academic_notice') return $r('app.color.campus_palette_orange')
    if (category === 'accounts') return $r('app.color.campus_palette_yellow')
    if (category === 'living') return $r('app.color.campus_palette_pink')
    if (category === 'mobility') return $r('app.color.campus_palette_blue')
    return $r('app.color.campus_palette_violet')
  }
}
