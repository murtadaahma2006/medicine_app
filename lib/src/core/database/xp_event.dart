/// أنواع أحداث نقاط الخبرة — قيم عمود kind في جدول xp_events.
///
/// القيم هنا يجب أن تطابق حرفياً [DatabaseHelper.xpEventKinds] وقيد
/// CHECK في المخطط (database_helper.dart) — الإصدار v14 الطبي.
library;

enum XpEventKind {
  concept,
  flashcard,
  mcq,
  caseStep,
  streak,
  assessment,
  drill,
  review,
}

String xpEventKindToCode(XpEventKind kind) => switch (kind) {
      XpEventKind.caseStep => 'case_step',
      _ => kind.name,
    };

XpEventKind xpEventKindFromCode(String code) {
  switch (code) {
    case 'concept':
      return XpEventKind.concept;
    case 'flashcard':
      return XpEventKind.flashcard;
    case 'mcq':
      return XpEventKind.mcq;
    case 'case_step':
      return XpEventKind.caseStep;
    case 'streak':
      return XpEventKind.streak;
    case 'assessment':
      return XpEventKind.assessment;
    case 'drill':
      return XpEventKind.drill;
    case 'review':
      return XpEventKind.review;
    default:
      throw ArgumentError('نوع حدث خبرة غير معروف: $code');
  }
}
