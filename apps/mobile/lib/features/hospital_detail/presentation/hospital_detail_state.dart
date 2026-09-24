import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../emergency_map/domain/hospital_summary.dart';
import '../../emergency_map/presentation/emergency_map_controller.dart';
import '../data/remote_hospital_detail_repository.dart';
import '../domain/hospital_detail.dart';
import '../domain/hospital_detail_repository.dart';

enum HospitalDetailTab { basic, clinical }

enum HospitalDetailPhase { loading, dataAvailable, partialData, error }

enum DetailFieldStatus { loading, available, notProvided, requestFailed }

class HospitalDetailState {
  final String hpid;
  final HospitalSummary? searchHospital;
  final String? searchSource;
  final HospitalDetailTab tab;
  final AsyncValue<HospitalDetail> detail;
  const HospitalDetailState({
    required this.hpid,
    required this.searchHospital,
    required this.searchSource,
    required this.tab,
    required this.detail,
  });
  HospitalDetail? get loaded => detail.valueOrNull;
  HospitalSummary? get realtime => loaded?.realtimeView ?? searchHospital;
  DetailFieldStatus fieldStatus(String? value) {
    if (value?.trim().isNotEmpty == true) return DetailFieldStatus.available;
    if (loaded != null) return DetailFieldStatus.notProvided;
    return detail.isLoading
        ? DetailFieldStatus.loading
        : DetailFieldStatus.requestFailed;
  }

  HospitalDetailPhase get phase {
    if (detail.isLoading && loaded == null) return HospitalDetailPhase.loading;
    if (detail.hasError) return HospitalDetailPhase.error;
    final data = loaded;
    if (data == null) return HospitalDetailPhase.loading;
    final live = data.realtimeView;
    return data.address?.trim().isNotEmpty != true ||
            data.mainPhone == null ||
            data.classification == '분류 정보 미제공' ||
            data.catalogStale ||
            live.coverage != 'LIVE_AVAILABLE' ||
            live.stale ||
            !live.beds.known
        ? HospitalDetailPhase.partialData
        : HospitalDetailPhase.dataAvailable;
  }
}

final hospitalDetailRepositoryProvider = Provider<HospitalDetailRepository>(
  (ref) => RemoteHospitalDetailRepository(createApiClient()),
);

final hospitalDetailRequestProvider = FutureProvider.autoDispose
    .family<HospitalDetail, String>(
      (ref, hpid) => ref.watch(hospitalDetailRepositoryProvider).get(hpid),
    );

final hospitalDetailTabProvider = StateProvider.autoDispose
    .family<HospitalDetailTab, String>((ref, hpid) => HospitalDetailTab.basic);

// Capture once per open detail, rather than following later Map searches.
final _detailSeedProvider = Provider.autoDispose
    .family<({HospitalSummary? hospital, String? source}), String>((ref, hpid) {
      final map = ref.read(mapControllerProvider);
      final matches = map.snapshot?.result.hospitals.where(
        (h) => h.hpid == hpid,
      );
      return (
        hospital: matches == null || matches.isEmpty ? null : matches.first,
        source: map.snapshot?.source,
      );
    });

final hospitalDetailProvider = Provider.autoDispose
    .family<HospitalDetailState, String>((ref, hpid) {
      final seed = ref.watch(_detailSeedProvider(hpid));
      return HospitalDetailState(
        hpid: hpid,
        searchHospital: seed.hospital,
        searchSource: seed.source,
        tab: ref.watch(hospitalDetailTabProvider(hpid)),
        detail: ref.watch(hospitalDetailRequestProvider(hpid)),
      );
    });
