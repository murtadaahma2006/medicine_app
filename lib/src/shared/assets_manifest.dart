/// قائمة بجميع معرّفات الصور (Illustrations) في التطبيق والبدائل الخاصة بها.
class AssetManifestEntry {
  final String id;
  final String group;
  final String fallback;

  const AssetManifestEntry({
    required this.id,
    required this.group,
    required this.fallback,
  });
}

abstract class AppAssetsManifest {
  static const List<AssetManifestEntry> items = [
    // 1. التخصصات الطبية (units)
    AssetManifestEntry(id: 'unit_cardio', group: 'units', fallback: '❤️'),
    AssetManifestEntry(id: 'unit_pulmo', group: 'units', fallback: '🫁'),
    AssetManifestEntry(id: 'unit_nephro', group: 'units', fallback: '🫘'),
    AssetManifestEntry(id: 'unit_gastro', group: 'units', fallback: '🫃'),
    AssetManifestEntry(id: 'unit_endo', group: 'units', fallback: '🧬'),
    AssetManifestEntry(id: 'unit_hema', group: 'units', fallback: '🩸'),
    AssetManifestEntry(id: 'unit_infect', group: 'units', fallback: '🦠'),
    AssetManifestEntry(id: 'unit_rheuma', group: 'units', fallback: '🦴'),
    AssetManifestEntry(id: 'unit_neuro', group: 'units', fallback: '🧠'),
    AssetManifestEntry(id: 'unit_onco', group: 'units', fallback: '🎗️'),

    // 2. الأونبوردنغ (onboarding)
    AssetManifestEntry(id: 'onboarding_level', group: 'onboarding', fallback: '🚀'),
    AssetManifestEntry(id: 'onboarding_goal', group: 'onboarding', fallback: '🎯'),
    AssetManifestEntry(id: 'onboarding_start', group: 'onboarding', fallback: '📚'),

    // 3. حالات الفراغ (empty)
    AssetManifestEntry(id: 'empty_review', group: 'empty', fallback: '📭'),
    AssetManifestEntry(id: 'empty_mistakes', group: 'empty', fallback: '🎉'),
    AssetManifestEntry(id: 'empty_search', group: 'empty', fallback: '🔍'),

    // 4. الشارات (badges)
    AssetManifestEntry(id: 'badge_first_step', group: 'badges', fallback: '🏅'),
    AssetManifestEntry(id: 'badge_triad', group: 'badges', fallback: '🥉'),
    AssetManifestEntry(id: 'badge_vocabulary', group: 'badges', fallback: '📖'),
    AssetManifestEntry(id: 'badge_full_mark', group: 'badges', fallback: '⭐'),
    AssetManifestEntry(id: 'badge_case_master', group: 'badges', fallback: '🩺'),
    AssetManifestEntry(id: 'badge_streak3', group: 'badges', fallback: '🔥'),
    AssetManifestEntry(id: 'badge_week_streak', group: 'badges', fallback: '🔥'),
    AssetManifestEntry(id: 'badge_xp_star', group: 'badges', fallback: '🌟'),

    // 5. المستويات (levels)
    AssetManifestEntry(id: 'level_beginner', group: 'levels', fallback: '🌱'),
    AssetManifestEntry(id: 'level_explorer', group: 'levels', fallback: '🧭'),
    AssetManifestEntry(id: 'level_builder', group: 'levels', fallback: '🧱'),
    AssetManifestEntry(id: 'level_confident', group: 'levels', fallback: '💪'),
    AssetManifestEntry(id: 'level_advanced', group: 'levels', fallback: '🚀'),

    // 6. متنوع (misc)
    AssetManifestEntry(id: 'icon_flashcards', group: 'misc', fallback: '🃏'),
    AssetManifestEntry(id: 'icon_concept', group: 'misc', fallback: '📖'),
    AssetManifestEntry(id: 'icon_case', group: 'misc', fallback: '🩺'),
    AssetManifestEntry(id: 'icon_quiz', group: 'misc', fallback: '📋'),
    AssetManifestEntry(id: 'icon_analyze', group: 'misc', fallback: '🔎'),
    AssetManifestEntry(id: 'icon_graduation', group: 'misc', fallback: '🎓'),
    AssetManifestEntry(id: 'icon_progress', group: 'misc', fallback: '📊'),
    AssetManifestEntry(id: 'icon_calendar', group: 'misc', fallback: '📅'),
    AssetManifestEntry(id: 'icon_document', group: 'misc', fallback: '📄'),
    AssetManifestEntry(id: 'icon_backup', group: 'misc', fallback: '💾'),
    AssetManifestEntry(id: 'avatar_user', group: 'misc', fallback: '🧑'),
    AssetManifestEntry(id: 'avatar_patient', group: 'misc', fallback: '🧑‍🦯'),
  ];
}
