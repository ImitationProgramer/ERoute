import '../../core/config/app_config.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';
import 'disease_reference.dart';

String catalogKey(String value) =>
    aliasKey(value).replaceAll(RegExp(r'\s+'), '');

class DiseaseCategory {
  final String id, name;
  final int sortOrder;
  const DiseaseCategory(this.id, this.name, this.sortOrder);
}

class DiseaseCatalog {
  final String version;
  final List<DiseaseCategory> categories;
  final List<Disease> diseases;
  final List<String> quickPicks;
  final Map<String, String> _index = {};
  DiseaseCatalog.fromJson(Map<String, dynamic> j)
    : version = j['catalogVersion'] as String,
      categories =
          (j['categories'] as List)
              .map(
                (c) => DiseaseCategory(
                  c['id'] as String,
                  c['name'] as String,
                  c['sortOrder'] as int,
                ),
              )
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      diseases = (j['diseases'] as List)
          .map(
            (d) => Disease(
              d['id'] as String,
              d['canonicalName'] as String,
              d['active'] as bool,
              List<String>.from(d['aliases'] as List),
              category: d['categoryId'] as String,
            ),
          )
          .toList(),
      quickPicks = List<String>.from(j['quickPickDiseaseIds'] as List? ?? []) {
    void require(bool ok) {
      if (!ok) throw const FormatException('질환 목록을 확인하지 못했습니다.');
    }

    require(version.isNotEmpty && diseases.isNotEmpty);
    require(categories.map((c) => c.id).toSet().length == categories.length);
    require(diseases.map((d) => d.id).toSet().length == diseases.length);
    for (final c in categories) {
      require(c.id.isNotEmpty && c.name.trim().isNotEmpty);
    }
    for (final d in diseases) {
      require(
        d.id.isNotEmpty &&
            d.name.trim().isNotEmpty &&
            categories.any((c) => c.id == d.category),
      );
      for (final name in [d.name, ...d.aliases]) {
        final key = catalogKey(name);
        require(key.isNotEmpty && (_index[key] == null || _index[key] == d.id));
        _index[key] = d.id;
      }
    }
    require(
      quickPicks.toSet().length == quickPicks.length &&
          quickPicks.every((id) => byId(id)?.active == true),
    );
  }
  Disease? byId(String id) => diseases.where((d) => d.id == id).firstOrNull;
  String? exact(String value) {
    final id = _index[catalogKey(value)];
    return id != null && byId(id)?.active == true ? id : null;
  }

  List<Disease> search(String value) {
    final key = catalogKey(value);
    return diseases
        .where(
          (d) =>
              d.active &&
              [d.name, ...d.aliases].any((s) => catalogKey(s).contains(key)),
        )
        .toList();
  }
}

abstract interface class DiseaseCatalogRepository {
  Future<DiseaseCatalog> catalog();
}

final diseaseCatalogRepositoryProvider = Provider<DiseaseCatalogRepository>((
  ref,
) {
  final dio = createApiClient();
  ref.onDispose(() => dio.close(force: true));
  return RemoteDiseaseCatalogRepository(dio);
});

class RemoteDiseaseCatalogRepository implements DiseaseCatalogRepository {
  final Dio dio;
  RemoteDiseaseCatalogRepository(this.dio);
  String get cacheKey =>
      'eroute.public.diseases.${AppConfig.authEnvironment}.${sha256.convert(utf8.encode(dio.options.baseUrl))}';
  @override
  Future<DiseaseCatalog> catalog() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final r = await dio.get('/api/v1/reference/diseases');
      final json = Map<String, dynamic>.from(r.data as Map);
      final value = DiseaseCatalog.fromJson(json);
      await prefs.setString(cacheKey, jsonEncode(json));
      return value;
    } catch (_) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        return DiseaseCatalog.fromJson(
          Map<String, dynamic>.from(jsonDecode(cached) as Map),
        );
      }
      rethrow;
    }
  }
}
