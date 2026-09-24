class GeoPoint {
  final double latitude, longitude;
  const GeoPoint(this.latitude, this.longitude);
  factory GeoPoint.fromJson(Map<String, dynamic> j) => GeoPoint(
    (j['latitude'] as num).toDouble(),
    (j['longitude'] as num).toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

class CoverageBounds {
  final GeoPoint southWest, northEast;
  CoverageBounds(this.southWest, this.northEast);
  factory CoverageBounds.fromJson(Map<String, dynamic> j) => CoverageBounds(
    GeoPoint.fromJson(j['southWest']),
    GeoPoint.fromJson(j['northEast']),
  );
}

class MapPolicy {
  final List<int> radii;
  final int defaultRadius;
  final CoverageBounds? bounds;
  MapPolicy(this.radii, this.defaultRadius, this.bounds);
  factory MapPolicy.fromJson(Map<String, dynamic> j) => MapPolicy(
    (j['radiusStepsMeters'] as List).cast<int>(),
    j['defaultRadiusMeters'],
    j['coverageBounds'] == null
        ? null
        : CoverageBounds.fromJson(j['coverageBounds']),
  );
}

class ResourceValue {
  final String status;
  final int? numericValue;
  final String? rawValue;
  final String? endpoint, sourceField, officialLabel;
  ResourceValue(
    this.status,
    this.numericValue,
    this.rawValue, {
    this.endpoint,
    this.sourceField,
    this.officialLabel,
  });
  factory ResourceValue.fromJson(Map<String, dynamic> j) => ResourceValue(
    j['interpretationStatus'],
    j['numericValue'],
    j['rawValue'],
    endpoint: j['endpoint'],
    sourceField: j['sourceField'],
    officialLabel: j['officialLabel'],
  );
  bool get known => status == 'KNOWN' && numericValue != null;
  String get display => status == 'KNOWN' && numericValue != null
      ? '$numericValue'
      : status == 'UNVERIFIED' || status == 'UNKNOWN_CODE'
      ? '확인 중'
      : '정보 미제공';
}

class HospitalSummary {
  final String hpid, name, classification, coverage, refresh;
  final GeoPoint location;
  final int centerDistance;
  final int? userDistance;
  final ResourceValue beds, reference;
  final bool stale;
  final String? rawSourceTime, parsedSourceTime, sourceTimestampStatus, error;
  final DateTime? fetchedAt, lastAttemptAt;
  final String sourceFreshness;
  final List<String> staleReasons;
  HospitalSummary({
    required this.hpid,
    required this.name,
    required this.classification,
    required this.location,
    required this.centerDistance,
    required this.userDistance,
    required this.coverage,
    required this.refresh,
    required this.beds,
    required this.reference,
    required this.stale,
    required this.rawSourceTime,
    this.parsedSourceTime,
    this.sourceTimestampStatus,
    this.sourceFreshness = 'UNKNOWN',
    this.staleReasons = const [],
    this.lastAttemptAt,
    required this.fetchedAt,
    required this.error,
  });
  factory HospitalSummary.fromJson(Map<String, dynamic> j) {
    final r = j['realtime'] as Map<String, dynamic>;
    final f = r['freshness'] as Map<String, dynamic>;
    final refs = r['referenceResources'] as List;
    final values = refs.map((value) => ResourceValue.fromJson(value)).toList();
    final hvs01 = values.where(
      (value) => value.sourceField?.toUpperCase() == 'HVS01',
    );
    return HospitalSummary(
      hpid: j['hpid'],
      name: j['name'],
      classification:
          j['emergencyClass']['name'] ??
          j['emergencyClass']['code'] ??
          '분류 정보 미제공',
      location: GeoPoint.fromJson(j['location']),
      centerDistance: j['distanceFromCenterMeters'],
      userDistance: j['distanceFromUserMeters'],
      coverage: r['coverageStatus'],
      refresh: r['refreshStatus'],
      beds: ResourceValue.fromJson(r['availableBeds']),
      reference: values.isEmpty
          ? ResourceValue('MISSING', null, null)
          : hvs01.isNotEmpty
          ? hvs01.first
          : ResourceValue('UNVERIFIED', null, null),
      stale: f['stale'],
      rawSourceTime: f['source']['sourceRawTimestamp'],
      parsedSourceTime: f['source']['parsedSourceTimestamp'],
      sourceTimestampStatus: f['source']['sourceTimestampStatus'],
      sourceFreshness: f['sourceFreshness'] ?? 'UNKNOWN',
      staleReasons: (f['staleReasons'] as List? ?? []).cast<String>(),
      lastAttemptAt: DateTime.tryParse(f['lastAttemptAt'] ?? ''),
      fetchedAt: DateTime.tryParse(f['fetchedAt'] ?? ''),
      error: r['error'],
    );
  }
  String? get refreshGuidance {
    if (refresh != 'BUDGET_DEFERRED') return null;
    if (error == 'CALL_RATE_LIMIT') {
      return '요청이 몰려 조회하지 못했습니다. 잠시 후 지도에서 새로고침해 주세요.';
    }
    if (error == 'CALL_BUDGET_LIMIT') {
      return '최근 24시간 조회 한도로 지금은 갱신할 수 없습니다. 시간이 지난 뒤 지도에서 새로고침해 주세요.';
    }
    return '조회를 완료하지 못했습니다. 잠시 후 지도에서 새로고침해 주세요.';
  }

  String? get freshnessGuidance {
    if (fetchedAt == null || coverage == 'LIVE_NOT_PROVIDED') return null;
    final messages = <String>[];
    if (staleReasons.contains('CACHE_EXPIRED')) {
      messages.add('수집 후 시간이 지나 이전 병상정보를 표시합니다.');
    }
    // Coverage and collection success never verify the provider clock.
    if (sourceFreshness == 'STALE') {
      messages.add('제공기관 갱신이 지연된 병상정보입니다.');
    } else if (sourceFreshness != 'FRESH' ||
        sourceTimestampStatus != 'VERIFIED') {
      messages.add('원천 갱신시각 확인 필요');
    }
    return messages.isEmpty ? null : messages.join('\n');
  }

  String get statusLabel {
    if (refresh == 'BUDGET_DEFERRED') {
      final label = error == 'CALL_BUDGET_LIMIT' ? '조회 한도 도달' : '갱신 대기';
      return '$label${fetchedAt == null ? '' : ' · 이전 정보'}';
    }
    if (error == 'REGION_MAPPING_ERROR') {
      return '실시간 정보를 불러오지 못했습니다.${fetchedAt == null ? '' : ' · 이전 정보'}';
    }
    if (coverage == 'LIVE_ERROR') {
      return '갱신 실패${fetchedAt == null ? '' : ' · 이전 정보'}';
    }
    if (coverage == 'LIVE_NOT_PROVIDED') return '실시간 병상정보 미제공';
    if (coverage == 'LIVE_UNKNOWN') return '실시간 정보 확인 대기';
    if (stale || sourceFreshness == 'STALE') return '이전 정보';
    return '병상정보 제공';
  }
}

class HospitalSearchResult {
  final List<HospitalSummary> hospitals;
  final int radius, totalCount;
  final bool expanded, catalogStale;
  final List<String> warnings;
  HospitalSearchResult(
    this.hospitals,
    this.radius,
    this.expanded,
    this.catalogStale,
    this.warnings, {
    int? totalCount,
  }) : totalCount = totalCount ?? hospitals.length;
  factory HospitalSearchResult.fromJson(Map<String, dynamic> j) =>
      HospitalSearchResult(
        (j['hospitals'] as List)
            .map((h) => HospitalSummary.fromJson(h))
            .toList(),
        j['meta']['effectiveRadiusMeters'],
        j['meta']['expanded'],
        j['meta']['catalogStale'],
        (j['meta']['warnings'] as List).cast<String>(),
        totalCount: j['meta']['totalCount'],
      );
}
