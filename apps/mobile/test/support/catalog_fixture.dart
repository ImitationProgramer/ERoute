import 'dart:convert';
import 'dart:io';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';

Map<String, dynamic> catalogJson() =>
    jsonDecode(
          const String.fromEnvironment(
                'DISEASE_CATALOG_TEST_DOCUMENT',
              ).isNotEmpty
              ? const String.fromEnvironment('DISEASE_CATALOG_TEST_DOCUMENT')
              : File(
                  '../../services/backend/src/main/resources/reference/diseases/catalog.json',
                ).readAsStringSync(),
        )
        as Map<String, dynamic>;

class FixtureCatalogRepository implements DiseaseCatalogRepository {
  Map<String, dynamic>? json;
  bool offline = false;
  @override
  Future<DiseaseCatalog> catalog() async {
    if (offline) throw Exception('offline');
    return DiseaseCatalog.fromJson(json ?? catalogJson());
  }
}

class MemoryConditionVault implements ConditionVault {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next) async {
    if (fail) throw Exception('storage');
    value = next;
  }
}
