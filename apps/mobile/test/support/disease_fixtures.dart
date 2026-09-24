import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/map_disease_selection.dart';

// Host tests read the authoritative file directly. Android tests receive a
// generated test-only define from that same file; nothing is an app asset.
String backendReferenceDocument() {
  const injected = String.fromEnvironment('DISEASE_REFERENCE_TEST_DOCUMENT');
  return injected.isNotEmpty
      ? injected
      : File(
          '../../services/backend/src/main/resources/reference/disease-departments/v0.1.json',
        ).readAsStringSync();
}

Map<String, dynamic> referenceEnvelope([String? document]) {
  final raw = document ?? backendReferenceDocument();
  return {
    'document': raw,
    'sha256': sha256.convert(utf8.encode(raw)).toString(),
  };
}

DiseaseReference backendReference() =>
    DiseaseReference.decode(referenceEnvelope());
MapDiseaseSelection confirmedSelection(
  DiseaseReference reference,
  List<String> ids,
) => MapDiseaseSelection(
  state: 'CONFIRMED',
  diseaseIds: ids,
  purpose: reference.purpose,
  purposeVersion: reference.purposeVersion,
  referenceVersion: reference.version,
  confirmedAt: DateTime.utc(2026, 9, 17),
);
