import { ReadableText } from '../common/ReadableText'
import { ErrorNotice } from './ErrorNotice'
import { FloatingActionButton } from './FloatingActionButton'
import { CourseGrade, ExamSchedule, GpaListItem, SemesterInfo } from '../model/Academic'
import { LocalGpa } from '../common/LocalGpa'
import { AcademicPresentation, AcademicRankRow } from '../common/AcademicPresentation'
import { AppLanguage } from '../common/AppLanguage'
import { ThemeColors, ThemeDimens } from '../common/Theme'
import { adaptiveMaterial } from '../common/AdaptiveMaterial'
import { TabSegmentButtonV2, SegmentButtonV2Items } from '@ohos.arkui.advanced.SegmentButtonV2'
import { ColorMetrics } from '@kit.ArkUI'
import { CampusContentStyle } from '../common/CampusContentStyle'
import { SheetTransitionGuard } from '../common/SheetTransitionGuard'

/** ForEach retains nodes with an unchanged key, including their derived scope values. */
export function academicRankKey(row: AcademicRankRow, index: number, sameMajor: boolean): string {
  return JSON.stringify([sameMajor ? 'same' : 'all', String(index), row.item.id, row.item.major,
    row.item.college, row.item.name, row.item.year, row.item.gpa, row.item.credits, row.item.rank,
    row.percentile, row.isMe ? 'me' : 'peer'])
}

export function academicGradeKey(grade: CourseGrade, index: number, graduate: boolean, fallback: boolean): string {
  return JSON.stringify([graduate ? 'pg' : 'ug', fallback ? 'fallback' : 'normal', String(index),
    grade.semester, grade.courseId, grade.courseName, grade.type, grade.level, grade.gradePoint, grade.credit ?? ''])
}

export function academicExamKey(exam: ExamSchedule, grades: CourseGrade[], index: number): string {
  const grade = AcademicPresentation.examGrade(exam, grades)
  return JSON.stringify([String(index), exam.id, exam.name, exam.type, exam.testCategory, exam.date,
    exam.time, exam.location, exam.note, grade?.level ?? '', grade?.gradePoint ?? ''])
}

export function academicSemesterKey(semester: SemesterInfo): string {
  return JSON.stringify([semester.id, semester.name])
}

/** Pure presentation: the host owns account routing, requests and calendar saving. */
@Component
export struct AcademicContent {
  @Prop graduate: boolean = false
  @Prop exams: ExamSchedule[] = []
  @Prop grades: CourseGrade[] = []
  @Prop ranks: GpaListItem[] = []
  @Prop semesters: SemesterInfo[] = []
  @Prop semesterId: string = ''
  @Prop studentId: string = ''
  @Prop loading: boolean = false
  @Prop loadingOverlay: boolean = false
  @Prop examError: string = ''
  @Prop gradeError: string = ''
  @Prop rankError: string = ''
  @Prop semesterError: string = ''
  @Prop fallback: boolean = false
  onSemester: (id: string) => void = (_id: string) => {}
  onReload: () => void = () => {}
  onExport: () => void = () => {}
  @StorageLink('ui_material_revision') materialRevision: number = 0
  @StorageLink(AppLanguage.KEY_REVISION) languageRevision: number = 0
  @Prop view: number = 0
  @State private sameMajor: boolean = false
  @State private showGpaExplanation: boolean = false
  private gpaSheet: SheetTransitionGuard = new SheetTransitionGuard()
  private viewItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.academic_overview') }, { text: $r('app.string.academic_grades') },
    { text: $r('app.string.academic_ranking') }
  ])
  private scopeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.academic_rank_all') }, { text: $r('app.string.academic_rank_same') }
  ])

  @Builder
  Detail(label: ResourceStr, value: string, color: ResourceColor = ThemeColors.textPrimary, prominent: boolean = false) {
    if (value.length > 0) {
      Row({ space: 8 }) {
        Text(label).fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary).constraintSize({ maxWidth: 88 })
        Text(value).fontSize(prominent ? 16 : 14).lineHeight(prominent ? 23 : 21).layoutWeight(1)
          .fontWeight(prominent ? FontWeight.Medium : FontWeight.Normal).fontColor(color)
      }.width('100%').alignItems(VerticalAlign.Top)
    }
  }

  @Builder
  Metric(label: ResourceStr, value: string, color: ResourceColor = CampusContentStyle.accent) {
    if (value.length > 0) {
      Column({ space: 3 }) {
        Text(label).fontSize(11).lineHeight(16).fontColor(ThemeColors.textSecondary).width('100%')
        Text(value).fontSize(20).lineHeight(28).fontWeight(FontWeight.Bold).fontColor(color).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ErrorNote(message: () => string) {
    if (message().length > 0) {
      Row({ space: 10 }) {
        ErrorNotice({ message: message(), controlId: 'academiccontent-diagnostics', textSize: 13, textColor: CampusContentStyle.attention }).layoutWeight(1)
        FloatingActionButton({ label: $r('app.string.academic_retry'), icon: 'refresh', onCard: true, controlHeight: 48,
          actionEnabled: !this.loading, onAction: () => { this.onReload() } }).width(48)
      }.width('100%').padding(12).backgroundColor($r('app.color.input_surface')).borderRadius(12)
    }
  }

  @Builder
  Grade(grade: CourseGrade) {
    Column({ space: 8 }) {
      Text(grade.courseName).width('100%').fontSize(17).lineHeight(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      if (grade.courseId.length > 0 || grade.type.length > 0) {
        Text([grade.courseId, grade.type].filter((value: string) => value.length > 0).join(' · '))
          .width('100%').fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
      }
      if (this.graduate || this.fallback) this.Detail($r('app.string.academic_semester_label'), grade.semester)
      Row({ space: 14 }) {
        this.Metric($r('app.string.academic_grade'), grade.level, CampusContentStyle.gradeColor(grade.level))
        this.Metric($r('app.string.academic_gradepoint'), grade.gradePoint)
        if (grade.credit !== undefined) this.Metric($r('app.string.academic_credits'), grade.credit, ThemeColors.textPrimary)
      }.width('100%').alignItems(VerticalAlign.Top).padding({ top: 2 })
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).margin({ top: 4 })
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      .borderRadius(ThemeDimens.radiusLarge)
  }

  @Builder
  Exam(exam: ExamSchedule) {
    Column({ space: 8 }) {
      Text(exam.name).width('100%').fontSize(17).lineHeight(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      if (exam.id.length > 0 || exam.type.length > 0 || exam.testCategory.length > 0) {
        Text([exam.id, exam.type, exam.testCategory].filter((value: string) => value.length > 0).join(' · '))
          .width('100%').fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
      }
      if (exam.date.length > 0 || exam.time.length > 0) {
        Row({ space: 12 }) {
          this.Metric($r('app.string.academic_exam_date'), exam.date)
          this.Metric($r('app.string.academic_exam_time'), exam.time)
        }.width('100%').alignItems(VerticalAlign.Top).padding(10)
          .backgroundColor(CampusContentStyle.highlight).borderRadius(10)
      }
      this.Detail($r('app.string.academic_exam_room'), exam.location, ThemeColors.textPrimary, true)
      this.Detail($r('app.string.academic_exam_note'), exam.note, ThemeColors.textSecondary)
      if (AcademicPresentation.examGrade(exam, this.grades) !== undefined) {
        Row({ space: 14 }) {
          this.Metric($r('app.string.academic_grade'), AcademicPresentation.examGrade(exam, this.grades)?.level ?? '',
            CampusContentStyle.gradeColor(AcademicPresentation.examGrade(exam, this.grades)?.level ?? ''))
          this.Metric($r('app.string.academic_gradepoint'), AcademicPresentation.examGrade(exam, this.grades)?.gradePoint ?? '')
        }.width('100%').alignItems(VerticalAlign.Top)
      } else if (exam.type.includes('补') || exam.type.includes('缓')) {
        Text($r('app.string.academic_grade_not_for_exam')).width('100%').fontSize(13).fontColor(ThemeColors.textSecondary)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).margin({ top: 4 })
      .backgroundColor($r('app.color.surface_fallback')).systemMaterial(adaptiveMaterial(this.materialRevision))
      .borderRadius(ThemeDimens.radiusLarge)
  }

  @Builder
  GpaSymbol(symbol: Resource, description: Resource) {
    Row({ space: 6 }) {
      Image(symbol).width(18).height(18).objectFit(ImageFit.Contain)
        .fillColor(ThemeColors.textSecondary).accessibilityLevel('no')
      Text(description).layoutWeight(1).fontSize(11).lineHeight(18).fontColor(ThemeColors.textSecondary)
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  @Builder
  MyGpa() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text($r('app.string.academic_my_gpa')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).layoutWeight(1)
        Button($r('app.string.academic_gpa_explanation')).fontSize(13).fontColor(CampusContentStyle.accent)
          .backgroundColor($r('app.color.input_surface'))
          .height(32).padding({ left: 12, right: 12 }).id('academic-gpa-explanation')
          .onClick(() => { this.gpaSheet.open(() => { this.showGpaExplanation = true }, () => this.getUIContext()) })
      }.width('100%')
      if (LocalGpa.calculate(this.grades, this.graduate).gpa) {
        Row({ space: 14 }) {
          this.Metric($r('app.string.academic_gpa'), LocalGpa.calculate(this.grades, this.graduate).gpa)
          this.Metric($r('app.string.academic_gpa_credits'), LocalGpa.calculate(this.grades, this.graduate).credits, ThemeColors.textPrimary)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        Text($r('app.string.academic_my_gpa_unavailable')).width('100%').fontSize(14).fontColor(ThemeColors.textSecondary)
      }
      Text($r('app.string.academic_gpa_brief')).width('100%').fontSize(12).lineHeight(18).fontColor(ThemeColors.textSecondary)
      if (!this.graduate && !this.fallback) {
        Button($r('app.string.academic_ranking')).height(28).fontSize(13).padding(0)
          .backgroundColor(Color.Transparent).fontColor(CampusContentStyle.accent)
          .onClick(() => { this.view = 2 })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, top: 10, bottom: 12 }).margin({ top: 4 })
      .backgroundColor($r('app.color.theme_card_bg'))
      .borderRadius(ThemeDimens.radiusLarge)
      .bindSheet($$this.showGpaExplanation, this.GpaExplanation(), this.gpaSheet.options(this.showGpaExplanation, {
        height: SheetSize.FIT_CONTENT, showClose: true, dragBar: true,
        backgroundColor: $r('app.color.surface_fallback'), systemMaterial: adaptiveMaterial(this.materialRevision)
      }))
  }

  @Builder
  GpaExplanation() {
    Column({ space: 9 }) {
      Text($r('app.string.academic_gpa_explanation')).fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary).width('100%').padding({ right: 40 })
      Image($r('app.media.academic_gpa_formula')).width('100%').height(108).objectFit(ImageFit.Contain)
        .fillColor(ThemeColors.textPrimary).id('academic-gpa-formula')
        .accessibilityText($r('app.string.academic_gpa_formula_description'))
      Column({ space: 1 }) {
        this.GpaSymbol($r('app.media.academic_gpa_symbol_n'), $r('app.string.academic_gpa_symbol_courses'))
        this.GpaSymbol($r('app.media.academic_gpa_symbol_g'), $r('app.string.academic_gpa_symbol_points'))
        this.GpaSymbol($r('app.media.academic_gpa_symbol_c'), $r('app.string.academic_gpa_symbol_credits'))
      }.width('100%').accessibilityGroup(true).accessibilityText($r('app.string.academic_gpa_symbols'))
      Text(ReadableText.resource($r('app.string.academic_gpa_note'))).width('100%').fontSize(12).lineHeight(20).fontColor(ThemeColors.textSecondary).lineBreakStrategy(LineBreakStrategy.GREEDY)
      Text(AppLanguage.text($r('app.string.academic_local_scope'), this.languageRevision)
        .replace('{included}', String(LocalGpa.calculate(this.grades, this.graduate).included))
        .replace('{excluded}', String(LocalGpa.calculate(this.grades, this.graduate).excluded))
        .replace('{incomplete}', String(LocalGpa.calculate(this.grades, this.graduate).incomplete)))
        .width('100%').fontSize(12).lineHeight(19).fontColor(ThemeColors.textSecondary)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 24, right: 24, top: 12, bottom: 20 })
  }

  @Builder
  Semesters() {
    Menu() {
      ForEach(this.semesters, (semester: SemesterInfo) => {
        MenuItem({ content: semester.name }).onClick(() => { this.onSemester(semester.id) })
      }, (semester: SemesterInfo) => academicSemesterKey(semester))
    }
  }

  build() {
    Column({ space: 8 }) {
      this.ErrorNote(() => this.semesterError)
      if (this.graduate) {
        Text(ReadableText.resource($r('app.string.graduate_scores_note'))).width('100%').fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).lineBreakStrategy(LineBreakStrategy.GREEDY)
      } else if (this.fallback) {
        Text(ReadableText.resource($r('app.string.academic_fallback_note'))).width('100%').fontSize(13).lineHeight(21).fontColor(ThemeColors.textSecondary).lineBreakStrategy(LineBreakStrategy.GREEDY)
      } else {
        if (this.semesters.length > 0) {
          Button(this.semesters.find((row: SemesterInfo) => row.id === this.semesterId)?.name ??
            AppLanguage.text($r('app.string.academic_semester'), this.languageRevision))
            .width('100%').fontSize(15).fontColor(CampusContentStyle.accent).backgroundColor(Color.Transparent)
            .bindMenu(this.Semesters)
        }
        TabSegmentButtonV2({ items: this.viewItems, selectedIndex: this.view,
          $selectedIndex: (index: number) => { this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => { this.view = index }) },
          enableStateAnimation: true, itemFontColor: ColorMetrics.resourceColor(ThemeColors.textPrimary),
          itemSelectedFontColor: ColorMetrics.rgba(255, 255, 255),
          itemSelectedBackgroundColor: ColorMetrics.resourceColor(ThemeColors.primary),
          buttonBackgroundColor: ColorMetrics.resourceColor($r('app.color.input_surface'))
        }).width('100%')
      }
      this.MyGpa()
      if (this.loading && !this.loadingOverlay) LoadingProgress().width(32).height(32).color(ThemeColors.primary)
      if (this.graduate || this.view === 1 || this.fallback) {
        this.ErrorNote(() => this.gradeError)
        ForEach(this.grades, (grade: CourseGrade) => { this.Grade(grade) },
          (grade: CourseGrade, index: number) => academicGradeKey(grade, index, this.graduate, this.fallback))
        if (!this.loading && this.gradeError.length === 0 && this.grades.length === 0) {
          Text($r('app.string.academic_empty_grades')).width('100%').padding(16).fontColor(ThemeColors.textSecondary)
        }
      } else if (this.view === 2) {
        this.ErrorNote(() => this.rankError)
        TabSegmentButtonV2({ items: this.scopeItems, selectedIndex: this.sameMajor ? 1 : 0,
          $selectedIndex: (index: number) => { this.sameMajor = index === 1 },
          enableStateAnimation: true, itemFontColor: ColorMetrics.resourceColor(ThemeColors.textPrimary),
          itemSelectedFontColor: ColorMetrics.rgba(255, 255, 255),
          itemSelectedBackgroundColor: ColorMetrics.resourceColor(ThemeColors.primary),
          buttonBackgroundColor: ColorMetrics.resourceColor($r('app.color.input_surface'))
        }).width('100%')
        ForEach(AcademicPresentation.ranks(this.ranks, this.studentId, this.sameMajor), (row: AcademicRankRow) => {
          Column({ space: 8 }) {
            Text([row.item.major, row.item.college].filter((value: string) => value.length > 0).join(' · '))
              .width('100%').fontSize(16).lineHeight(23).fontWeight(row.isMe ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(row.isMe ? ThemeColors.textPrimary : CampusContentStyle.accent)
            Text([row.item.name, row.item.year].filter((value: string) => value.length > 0).join(' · '))
              .width('100%').fontSize(12).lineHeight(19).fontColor(ThemeColors.textSecondary)
            Row({ space: 14 }) {
              this.Metric($r('app.string.academic_gpa'), row.item.gpa)
              this.Metric($r('app.string.academic_rank'), row.item.rank, row.isMe ? CampusContentStyle.accent : ThemeColors.textPrimary)
            }.width('100%').alignItems(VerticalAlign.Top)
            Row({ space: 14 }) {
              this.Metric($r('app.string.academic_credits'), row.item.credits, ThemeColors.textPrimary)
              this.Metric($r('app.string.academic_percentile'), row.percentile, row.isMe ? CampusContentStyle.accent : ThemeColors.textPrimary)
            }.width('100%').alignItems(VerticalAlign.Top)
          }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
            .backgroundColor(row.isMe ? CampusContentStyle.highlight : $r('app.color.surface_fallback'))
            .systemMaterial(adaptiveMaterial(this.materialRevision))
            
            .borderRadius(ThemeDimens.radiusLarge)
        }, (row: AcademicRankRow, index: number) => academicRankKey(row, index, this.sameMajor))
        if (!this.loading && this.rankError.length === 0 && this.ranks.length === 0) {
          Text($r('app.string.academic_empty_rank')).width('100%').padding(16).fontColor(ThemeColors.textSecondary)
        }
      } else {
        this.ErrorNote(() => this.examError)
        this.ErrorNote(() => this.gradeError)
        if (this.exams.length > 0) Button($r('app.string.academic_export_exams')).onClick(() => { this.onExport() })
        ForEach(this.exams.filter((row: ExamSchedule) => !AcademicPresentation.otherExam(row)), (exam: ExamSchedule) => { this.Exam(exam) },
          (exam: ExamSchedule, index: number) => academicExamKey(exam, this.grades, index))
        if (this.exams.some((row: ExamSchedule) => AcademicPresentation.otherExam(row)) ||
          AcademicPresentation.unmatchedGrades(this.exams, this.grades).length > 0) {
          Text($r('app.string.academic_other_exams')).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textSecondary).margin({ top: 12 })
        }
        ForEach(this.exams.filter((row: ExamSchedule) => AcademicPresentation.otherExam(row)), (exam: ExamSchedule) => { this.Exam(exam) },
          (exam: ExamSchedule, index: number) => academicExamKey(exam, this.grades, index))
        ForEach(AcademicPresentation.unmatchedGrades(this.exams, this.grades), (grade: CourseGrade) => { this.Grade(grade) },
          (grade: CourseGrade, index: number) => academicGradeKey(grade, index, this.graduate, this.fallback))
        if (!this.loading && this.examError.length === 0 && this.gradeError.length === 0 && this.exams.length === 0 && this.grades.length === 0) {
          Text($r('app.string.academic_empty_grades')).width('100%').padding(16).fontColor(ThemeColors.textSecondary)
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
