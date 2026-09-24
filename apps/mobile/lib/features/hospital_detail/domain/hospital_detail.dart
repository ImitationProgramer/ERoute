import '../../emergency_map/domain/hospital_summary.dart';

class HospitalContactNumber {
  final String sourceField, officialLabel, rawValue;
  const HospitalContactNumber({
    required this.sourceField,
    required this.officialLabel,
    required this.rawValue,
  });
  factory HospitalContactNumber.fromJson(Map<String, dynamic> json) =>
      HospitalContactNumber(
        sourceField: json['sourceField'],
        officialLabel: json['officialLabel'],
        rawValue: json['rawValue'],
      );
}

class HospitalDepartment {
  final String name, source, status;
  const HospitalDepartment(this.name, this.source, this.status);
  factory HospitalDepartment.fromJson(Map<String, dynamic> j) =>
      HospitalDepartment(
        j['name'] ?? '',
        j['source'] ?? 'NMC',
        j['interpretationStatus'] ?? 'UNVERIFIED',
      );
}

class HospitalOperatingHours {
  final String day, status;
  final String? open, close;
  const HospitalOperatingHours({
    required this.day,
    required this.status,
    this.open,
    this.close,
  });
  factory HospitalOperatingHours.fromJson(Map<String, dynamic> j) =>
      HospitalOperatingHours(
        day: j['day'],
        status: j['status'] ?? 'UNVERIFIED',
        open: j['open'],
        close: j['close'],
      );
  String get display {
    if (status == 'KNOWN' && open != null && close != null) {
      return '$open - $close';
    }
    if (status == 'MISSING' || status == 'NOT_PROVIDED') return '정보 미제공';
    return '정보 확인 필요';
  }
}

class HospitalBasicInfo {
  final String fetchStatus, dataStatus, refreshStatus, departmentsStatus;
  final String? departmentsRaw,
      sourceRawTimestamp,
      parsedSourceTimestamp,
      error;
  final DateTime? fetchedAt, lastAttemptAt;
  final List<HospitalDepartment> departments;
  final List<HospitalOperatingHours> operatingHours;
  final bool stale;
  final List<String> staleReasons;
  const HospitalBasicInfo({
    required this.fetchStatus,
    this.dataStatus = 'NOT_COLLECTED',
    this.refreshStatus = 'NOT_REQUESTED',
    this.departmentsStatus = 'MISSING',
    this.departments = const [],
    this.operatingHours = const [],
    this.stale = false,
    this.staleReasons = const [],
    this.departmentsRaw,
    this.sourceRawTimestamp,
    this.parsedSourceTimestamp,
    this.fetchedAt,
    this.lastAttemptAt,
    this.error,
  });
  factory HospitalBasicInfo.fromJson(Map<String, dynamic> j) =>
      HospitalBasicInfo(
        fetchStatus: j['fetchStatus'],
        dataStatus: j['dataStatus'] ?? 'NOT_COLLECTED',
        refreshStatus: j['refreshStatus'] ?? 'NOT_REQUESTED',
        departmentsStatus: j['departmentsStatus'] ?? 'MISSING',
        departments: (j['departments'] as List? ?? [])
            .map((d) => HospitalDepartment.fromJson(d))
            .toList(),
        operatingHours: (j['operatingHours'] as List? ?? [])
            .map((h) => HospitalOperatingHours.fromJson(h))
            .toList(),
        stale: j['stale'] ?? false,
        staleReasons: (j['staleReasons'] as List? ?? []).cast<String>(),
        departmentsRaw: j['departmentsRaw'],
        sourceRawTimestamp: j['sourceRawTimestamp'],
        parsedSourceTimestamp: j['parsedSourceTimestamp'],
        fetchedAt: DateTime.tryParse(j['fetchedAt'] ?? ''),
        lastAttemptAt: DateTime.tryParse(j['lastAttemptAt'] ?? ''),
        error: j['error'],
      );
}

class HospitalDetail {
  final String hpid, name, classification;
  final String? address;
  final GeoPoint? location;
  final HospitalContactNumber? mainPhone, secondaryPhone;
  final DateTime masterUpdatedAt, catalogFetchedAt, generatedAt;
  final String catalogVersion;
  final bool catalogStale;
  final HospitalSummary realtimeView;
  final HospitalBasicInfo basicInfo;
  const HospitalDetail({
    required this.hpid,
    required this.name,
    required this.classification,
    required this.address,
    required this.location,
    required this.mainPhone,
    required this.secondaryPhone,
    required this.masterUpdatedAt,
    required this.catalogFetchedAt,
    required this.generatedAt,
    required this.catalogVersion,
    required this.catalogStale,
    required this.realtimeView,
    required this.basicInfo,
  });
  factory HospitalDetail.fromJson(Map<String, dynamic> json) {
    HospitalContactNumber? contact(Object? value) => value == null
        ? null
        : HospitalContactNumber.fromJson(value as Map<String, dynamic>);
    final emergencyClass = json['emergencyClass'] as Map<String, dynamic>;
    final rawLocation = json['location'];
    final latitude = rawLocation is Map ? rawLocation['latitude'] : null;
    final longitude = rawLocation is Map ? rawLocation['longitude'] : null;
    final location = latitude is num && longitude is num
        ? GeoPoint(latitude.toDouble(), longitude.toDouble())
        : null;
    return HospitalDetail(
      hpid: json['hpid'],
      name: json['name'],
      classification:
          emergencyClass['name'] ?? emergencyClass['code'] ?? '분류 정보 미제공',
      address: json['address'],
      location: location,
      mainPhone: contact(json['mainPhone']),
      secondaryPhone: contact(json['secondaryPhone']),
      masterUpdatedAt: DateTime.parse(json['masterUpdatedAt']),
      catalogFetchedAt: DateTime.parse(json['catalogFetchedAt']),
      generatedAt: DateTime.parse(json['generatedAt']),
      catalogVersion: json['catalogVersion'],
      catalogStale: json['catalogStale'],
      realtimeView: HospitalSummary.fromJson({
        ...json,
        // This detail-only summary supplies realtime presentation, never markers.
        // Preserve unavailable geometry without fabricating a valid destination.
        'location': (location ?? const GeoPoint(double.nan, double.nan))
            .toJson(),
        'distanceFromCenterMeters': 0,
        'distanceFromUserMeters': null,
      }),
      basicInfo: HospitalBasicInfo.fromJson(json['basicInfo']),
    );
  }
}
