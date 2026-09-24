const guideContentStatus = 'SOURCE_GROUNDED_DRAFT';

bool validGuideId(String value) =>
    RegExp(r'^(?:[A-Z][A-Z0-9_]{0,63}|[a-z][a-z0-9-]{0,63})$').hasMatch(value);

String _required(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing guide $key');
  }
  return value;
}

String _date(Map<String, dynamic> json, String key) {
  final value = _required(json, key);
  final date = DateTime.tryParse(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      date == null ||
      date.toIso8601String().substring(0, 10) != value) {
    throw FormatException('Invalid guide $key');
  }
  return value;
}

class GuideSource {
  final String publisher, title, url, checkedAt, license;
  final String? publishedAt, finalModifiedDate;
  GuideSource.fromJson(Map<String, dynamic> j, {bool validation = false})
    : publisher = _required(
        j,
        validation ? 'organization' : 'sourceOrganization',
      ),
      title = _required(j, validation ? 'title' : 'sourceTitle'),
      // A broken source link disables that CTA; it never hides the local body.
      url = _required(j, 'sourceUrl'),
      checkedAt = _date(j, 'sourceCheckedAt'),
      license = _required(j, 'license'),
      publishedAt = j['publicationDate'] == null
          ? null
          : _date(j, 'publicationDate'),
      finalModifiedDate = validation ? _date(j, 'finalModifiedDate') : null {
    if (!j.containsKey('publicationDate') ||
        !const {
          'UNCONFIRMED',
          'KOGL_TYPE_1',
          'KOGL_TYPE_4',
        }.contains(license)) {
      throw const FormatException('Invalid source metadata');
    }
  }
}

class GuideEntry {
  final String id, title, category, summary, contentStatus;
  final String? thumbnailAsset;
  final List<String> aliases;
  final GuideSource source;
  final GuideSource? latestValidation;
  final Object? humanReviewedAtUtc;
  GuideEntry.fromJson(Map<String, dynamic> j)
    : id = _required(j, 'id'),
      title = _required(j, 'title'),
      category = _required(j, 'category'),
      summary = _required(j, 'summary'),
      contentStatus = _required(j, 'contentStatus'),
      humanReviewedAtUtc = j['humanReviewedAtUtc'],
      thumbnailAsset = j['thumbnailAsset'] as String?,
      aliases = List<String>.unmodifiable(j['aliases'] as List),
      source = GuideSource.fromJson(j),
      latestValidation = j['latestValidation'] == null
          ? null
          : GuideSource.fromJson(
              j['latestValidation'] as Map<String, dynamic>,
              validation: true,
            ) {
    if (!validGuideId(id) ||
        !const {'EMERGENCY_ACTION', 'FIRST_AID'}.contains(category) ||
        contentStatus != guideContentStatus ||
        !j.containsKey('humanReviewedAtUtc') ||
        humanReviewedAtUtc != null ||
        !j.containsKey('latestValidation') ||
        category == 'FIRST_AID' && source.publishedAt == null ||
        aliases.any((a) => !validGuideId(a)) ||
        thumbnailAsset != null &&
            !RegExp(
              r'^assets/illustrations/guides/[a-z0-9-]+\.webp$',
            ).hasMatch(thumbnailAsset!)) {
      throw const FormatException('Invalid guide metadata');
    }
  }
  String get categoryLabel =>
      category == 'EMERGENCY_ACTION' ? '응급상황 대처요령' : '응급처치 가이드';
}

enum GuideSectionType { when, actionSteps, warning, emergency }

class GuideSection {
  final GuideSectionType type;
  final String title;
  final String? intro;
  final List<String> items;
  GuideSection.fromJson(Map<String, dynamic> j)
    : type = switch (j['type']) {
        'WHEN' => GuideSectionType.when,
        'ACTION_STEPS' => GuideSectionType.actionSteps,
        'WARNING' => GuideSectionType.warning,
        'EMERGENCY' => GuideSectionType.emergency,
        _ => throw const FormatException('Unknown guide section'),
      },
      title = _required(j, 'title'),
      intro = j['intro'] as String?,
      items = List<String>.unmodifiable(
        j[j['type'] == 'ACTION_STEPS' ? 'steps' : 'items'] as List,
      ) {
    if (items.isEmpty ||
        items.any((item) => item.trim().isEmpty) ||
        intro != null && intro!.trim().isEmpty) {
      throw const FormatException('Empty guide section');
    }
  }
}

class GuideArticle extends GuideEntry {
  final List<GuideSection> sections;
  GuideArticle.fromJson(super.j)
    : sections = List<GuideSection>.unmodifiable(
        (j['sections'] as List).map(
          (s) => GuideSection.fromJson(s as Map<String, dynamic>),
        ),
      ),
      super.fromJson() {
    if (!sections.any((s) => s.type == GuideSectionType.actionSteps)) {
      throw const FormatException('Missing action steps');
    }
  }
}

class GuideCatalog {
  final List<GuideEntry> entries;
  final Map<String, GuideArticle> articles;
  final Set<String> unavailableIds;
  final String disclaimer;
  GuideCatalog({
    required List<GuideEntry> entries,
    required Map<String, GuideArticle> articles,
    required Set<String> unavailableIds,
    required this.disclaimer,
  }) : entries = List.unmodifiable(entries),
       articles = Map.unmodifiable(articles),
       unavailableIds = Set.unmodifiable(unavailableIds) {
    final routes = [
      for (final e in entries) ...[e.id, ...e.aliases],
    ];
    if (routes.toSet().length != routes.length || disclaimer.trim().isEmpty) {
      throw const FormatException(
        'Duplicate guide route or missing disclaimer',
      );
    }
  }
  GuideEntry? find(String id) {
    for (final entry in entries) {
      if (entry.id == id || entry.aliases.contains(id)) return entry;
    }
    return null;
  }
}
