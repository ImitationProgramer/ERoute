import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

/// The Backend document is the sole source. No bundled disease catalog/fallback.
String canonicalKey(String value) => unicode.nfc(value.trim());
String aliasKey(String value) => canonicalKey(value).toLowerCase();
const publicDiseaseMapEnabled =
    false; // A separate data review/release is required.

class Disease {
  final String id, name;
  final String category, lifecycleStatus;
  final int version;
  final bool active;
  final List<String> aliases;
  Disease(
    this.id,
    this.name,
    this.active,
    Iterable<String> aliases, {
    this.category = '기저질환',
    this.lifecycleStatus = 'ACTIVE',
    this.version = 1,
  }) : aliases = List.unmodifiable(aliases);
}

enum MappingScope { exactCanonical, broadParent }

MappingScope? decodeMappingScope(Object? value) => switch (value) {
  null => null,
  'EXACT_CANONICAL' => MappingScope.exactCanonical,
  'BROAD_PARENT' => MappingScope.broadParent,
  _ => throw const FormatException('관계 범위를 확인하지 못했습니다.'),
};

class DiseaseMapping {
  final String id, diseaseId, departmentId, relation, reviewStatus;
  final String? reviewClass;
  final MappingScope? mappingScope;
  const DiseaseMapping(
    this.id,
    this.diseaseId,
    this.departmentId,
    this.relation,
    this.reviewStatus, {
    this.reviewClass,
    this.mappingScope,
  });
}

class DiseaseReference {
  final String version, sha256Hash, status, purpose, purposeVersion;
  final String catalogVersion;
  final bool publicMapApproved;
  final int schemaVersion;
  final List<Disease> diseases;
  final Map<String, String> departments, departmentAliases;
  final List<DiseaseMapping> mappings;
  final Set<String> broadNames;
  DiseaseReference._(
    this.version,
    this.sha256Hash,
    this.status,
    this.purpose,
    this.purposeVersion,
    List<Disease> diseases,
    Map<String, String> departments,
    Map<String, String> departmentAliases,
    List<DiseaseMapping> mappings,
    Set<String> broadNames, {
    this.catalogVersion = '',
    this.publicMapApproved = false,
    this.schemaVersion = 1,
  }) : diseases = List.unmodifiable(diseases),
       departments = Map.unmodifiable(departments),
       departmentAliases = Map.unmodifiable(departmentAliases),
       mappings = List.unmodifiable(mappings),
       broadNames = Set.unmodifiable(broadNames);

  factory DiseaseReference.decode(Map<String, dynamic> envelope) {
    try {
      final document = envelope['document'] as String;
      final hash = envelope['sha256'] as String;
      if (sha256.convert(utf8.encode(document)).toString() != hash) {
        throw const FormatException();
      }
      final j = jsonDecode(document) as Map<String, dynamic>;
      if (j['schemaVersion'] == 2) return _decodeV2(j, hash);
      if (j['schemaVersion'] != 1 ||
          j['status'] != 'DRAFT' ||
          j['publicMapApproved'] != false) {
        throw const FormatException();
      }
      String text(Map m, String key) {
        final v = m[key] as String;
        if (v.trim().isEmpty) throw const FormatException();
        return v;
      }

      final ds = <Disease>[];
      final ids = <String>{};
      final owners = <String, String>{};
      for (final d in j['diseases'] as List) {
        final id = text(d, 'id'), name = text(d, 'canonicalName');
        if (!ids.add(id) || owners.containsKey(aliasKey(name))) {
          throw const FormatException();
        }
        owners[aliasKey(name)] = id;
        ds.add(
          Disease(
            id,
            name,
            d['active'] as bool,
            (j['aliases'] as List)
                .where((a) => a['diseaseId'] == id)
                .map((a) => text(a, 'alias')),
          ),
        );
      }
      for (final a in j['aliases'] as List) {
        final id = text(a, 'diseaseId'), key = aliasKey(text(a, 'alias'));
        if (!ids.contains(id) ||
            key != a['normalizedAlias'] ||
            (owners.containsKey(key) && owners[key] != id)) {
          throw const FormatException();
        }
        owners[key] = id;
      }
      final departments = <String, String>{};
      for (final d in j['departments'] as List) {
        final id = text(d, 'id');
        if (departments.containsKey(id)) throw const FormatException();
        departments[id] = text(d, 'canonicalName');
      }
      if (departments.values.toSet().length != departments.length ||
          ds.isEmpty) {
        throw const FormatException();
      }
      final mappings = <DiseaseMapping>[];
      final mids = <String>{};
      for (final m in j['mappings'] as List) {
        final id = text(m, 'id'),
            disease = text(m, 'diseaseId'),
            dept = text(m, 'departmentId'),
            rel = text(m, 'relationType');
        if (!mids.add(id) ||
            !ids.contains(disease) ||
            !departments.containsKey(dept) ||
            !{'DIRECT', 'CONTEXTUAL', 'REVIEW_REQUIRED'}.contains(rel) ||
            m['reviewStatus'] != 'DRAFT') {
          throw const FormatException();
        }
        mappings.add(
          DiseaseMapping(id, disease, dept, rel, text(m, 'reviewStatus')),
        );
      }
      final evidenceIds = <String>{};
      for (final e in j['evidence'] as List) {
        final id = text(e, 'mappingId');
        if (!mids.contains(id)) throw const FormatException();
        evidenceIds.add(id);
      }
      if (evidenceIds.length != mids.length) throw const FormatException();
      final aliases = <String, String>{};
      for (final a in j['departmentAliases'] as List) {
        final alias = canonicalKey(text(a, 'alias')),
            id = text(a, 'departmentId');
        if (a['reviewStatus'] != 'REVIEWED' ||
            !departments.containsKey(id) ||
            aliases.containsKey(alias)) {
          throw const FormatException();
        }
        aliases[alias] = departments[id]!;
      }
      return DiseaseReference._(
        text(j, 'datasetVersion'),
        hash,
        text(j, 'status'),
        text(j, 'purpose'),
        text(j, 'purposeVersion'),
        ds,
        departments,
        aliases,
        mappings,
        (j['uncertaintyPolicy']['broadDepartmentNames'] as List)
            .cast<String>()
            .map(canonicalKey)
            .toSet(),
      );
    } catch (_) {
      throw const FormatException('질환 기준정보를 확인하지 못했습니다.');
    }
  }

  bool supports(String diseaseId) =>
      diseases.any((d) => d.id == diseaseId && d.active) &&
      mappings.any(
        (m) =>
            m.diseaseId == diseaseId &&
            m.relation == 'DIRECT' &&
            m.reviewStatus == 'APPROVED',
      );

  static DiseaseReference _decodeV2(Map<String, dynamic> j, String hash) {
    Never bad() => throw const FormatException();
    String text(Map m, String key) {
      final v = m[key];
      if (v is! String || v.trim().isEmpty) bad();
      return v;
    }

    void approval(Map m) {
      final a = m['approval'];
      if (a is! Map || a['version'] != m['version']) bad();
      text(a, 'reviewer');
      if (DateTime.tryParse(text(a, 'approvedAt')) == null) bad();
    }

    void evidence(Map e) {
      text(e, 'sourceName');
      text(e, 'rawDepartmentText');
      if (e['notes'] is! String) bad();
      final url = Uri.tryParse(text(e, 'sourceUrl'));
      if (url == null ||
          !{'http', 'https'}.contains(url.scheme) ||
          url.host.isEmpty) {
        bad();
      }
      if (DateTime.tryParse(text(e, 'checkedAt')) == null) bad();
    }

    if (j['status'] != 'READY' || j['publicMapApproved'] is! bool) bad();
    final diseases = <Disease>[], ids = <String>{}, owners = <String, String>{};
    for (final value in j['diseases'] as List) {
      final d = value as Map;
      final id = text(d, 'id'),
          name = text(d, 'displayName'),
          state = text(d, 'lifecycleStatus');
      if (!ids.add(id) ||
          !{'ACTIVE', 'INACTIVE', 'RETIRED'}.contains(state) ||
          d['active'] != (state == 'ACTIVE') ||
          d['version'] is! int ||
          d['version'] < 1) {
        bad();
      }
      final aliases = (d['aliases'] as List).cast<String>();
      final local = <String>{};
      for (final term in [name, ...aliases]) {
        final key = aliasKey(term);
        if (key.isEmpty || !local.add(key) || owners.containsKey(key)) bad();
        owners[key] = id;
      }
      diseases.add(
        Disease(
          id,
          name,
          d['active'],
          aliases,
          category: text(d, 'category'),
          lifecycleStatus: state,
          version: d['version'],
        ),
      );
    }
    final departments = <String, String>{},
        allDepartments = <String, String>{},
        names = <String>{};
    for (final value in j['departments'] as List) {
      final d = value as Map;
      final id = text(d, 'id'), name = text(d, 'canonicalName');
      if (allDepartments.containsKey(id) ||
          !names.add(canonicalKey(name)) ||
          d['active'] is! bool ||
          d['version'] is! int ||
          d['version'] < 1) {
        bad();
      }
      allDepartments[id] = name;
      if (d['active'] == true) departments[id] = name;
    }
    if (diseases.isEmpty || allDepartments.isEmpty) bad();
    final mappings = <DiseaseMapping>[], mids = <String>{}, pairs = <String>{};
    for (final value in j['mappings'] as List) {
      final m = value as Map;
      final id = text(m, 'id'),
          d = text(m, 'diseaseId'),
          dep = text(m, 'departmentId'),
          rel = text(m, 'relationType'),
          review = text(m, 'reviewStatus');
      if (m.containsKey('priority') ||
          !mids.add(id) ||
          !pairs.add('$d|$dep') ||
          !ids.contains(d) ||
          !allDepartments.containsKey(dep) ||
          !{'DIRECT', 'CONTEXTUAL', 'REVIEW_REQUIRED'}.contains(rel) ||
          !{'DRAFT', 'APPROVED', 'REJECTED', 'RETIRED'}.contains(review) ||
          m['version'] is! int ||
          m['version'] < 1) {
        bad();
      }
      final es = m['evidence'] as List;
      if (review == 'APPROVED') {
        if (es.isEmpty) bad();
        for (final e in es) {
          evidence(e as Map);
        }
        approval(m);
      } else if (m['approval'] != null) {
        bad();
      }
      final mappingScope = decodeMappingScope(m['mappingScope']);
      if (departments.containsKey(dep)) {
        mappings.add(
          DiseaseMapping(id, d, dep, rel, review, mappingScope: mappingScope),
        );
      }
    }
    final aliases = <String, String>{}, aliasNames = <String>{};
    for (final value in j['departmentAliases'] as List) {
      final a = value as Map;
      final alias = canonicalKey(text(a, 'alias')),
          dep = text(a, 'departmentId'),
          review = text(a, 'reviewStatus');
      if (names.contains(alias) ||
          !aliasNames.add(alias) ||
          !allDepartments.containsKey(dep) ||
          !{'DRAFT', 'APPROVED', 'REJECTED', 'RETIRED'}.contains(review) ||
          a['version'] is! int ||
          a['version'] < 1) {
        bad();
      }
      if (review == 'APPROVED') {
        evidence(a['evidence'] as Map);
        approval(a);
        if (departments.containsKey(dep)) aliases[alias] = departments[dep]!;
      } else if (a['approval'] != null) {
        bad();
      }
    }
    final broad = (j['broadDepartmentNames'] as List)
        .cast<String>()
        .map(canonicalKey)
        .toSet();
    if (!names.containsAll(broad)) bad();
    text(j, 'vocabularyVersion');
    return DiseaseReference._(
      text(j, 'datasetVersion'),
      hash,
      text(j, 'status'),
      text(j, 'purpose'),
      text(j, 'purposeVersion'),
      diseases,
      departments,
      aliases,
      mappings,
      broad,
      catalogVersion: text(j, 'catalogVersion'),
      publicMapApproved: j['publicMapApproved'],
      schemaVersion: 2,
    );
  }

  /// Search suggestions only. Never pass the stored conditions text here.
  List<Disease> search(String query) {
    final key = aliasKey(query);
    return diseases
        .where(
          (d) =>
              d.active &&
              (key.isEmpty ||
                  aliasKey(d.name).contains(key) ||
                  d.aliases.any((a) => aliasKey(a).contains(key))),
        )
        .toList();
  }
}
