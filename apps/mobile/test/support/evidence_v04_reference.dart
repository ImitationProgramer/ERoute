// Host-only view of the Backend source of truth. Never a mobile asset.
import 'dart:convert';
import 'dart:io';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'disease_fixtures.dart';

DiseaseReference evidenceV04Reference({bool published = true}) {
  final data =
      jsonDecode(
            File(
              '../../services/backend/src/main/resources/reference/disease-departments/v0.4.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  if (published) {
    data['mappings'] = (data['mappings'] as List)
        .where((m) => m['reviewStatus'] == 'APPROVED')
        .toList();
    data['departmentAliases'] = (data['departmentAliases'] as List)
        .where((m) => m['reviewStatus'] == 'APPROVED')
        .toList();
  }
  return DiseaseReference.decode(referenceEnvelope(jsonEncode(data)));
}
