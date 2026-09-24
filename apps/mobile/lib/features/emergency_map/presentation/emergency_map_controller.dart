import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/location/location_service.dart';
import '../../../core/location/geolocator_location_service.dart';
import '../../../core/location/location_fix.dart';
import '../../../core/map/map_scene.dart';
import '../../../core/map/map_camera_controller.dart';
import '../../../core/map/camera_fit_geometry.dart';
import '../../../core/network/api_client.dart';
import '../data/remote_hospital_repository.dart';
import '../domain/hospital_repository.dart';
import '../domain/hospital_summary.dart';
import 'emergency_map_state.dart';

final hospitalRepositoryProvider = Provider<HospitalRepository>(
  (ref) => RemoteHospitalRepository(createApiClient()),
);
final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);
final mapControllerProvider = ChangeNotifierProvider(
  (ref) => EmergencyMapController(
    ref.watch(hospitalRepositoryProvider),
    ref.watch(locationServiceProvider),
  ),
);

class EmergencyMapController extends ChangeNotifier {
  final HospitalRepository repository;
  final LocationService locationService;
  EmergencyMapController(this.repository, this.locationService);
  MapPolicy? policy;
  GeoPoint? userLocation, center, pendingCenter;
  LocationFix? userFix;
  SearchPresentationSnapshot? snapshot;
  bool userExploring = false;
  String source = 'MANUAL';
  String? message, error;
  bool loading = false, locating = false;
  bool _disposed = false;
  int _generation = 0;
  HospitalSearchResult? result;
  int? requestedRadiusMeters;
  String? selectedHpid;
  EmergencyMapState get state => EmergencyMapState(
    policy: policy,
    userFix: userFix,
    center: center,
    pendingCenter: pendingCenter,
    snapshot: snapshot,
    requestedRadiusMeters: requestedRadiusMeters,
    source: source,
    selectedHpid: selectedHpid,
    message: message,
    error: error,
    loading: loading,
    locating: locating,
    userExploring: userExploring,
  );
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  Future<void> initialize() async {
    locating = true;
    notifyListeners();
    final positionFuture = locationService.current();
    try {
      policy = await repository.policy();
      requestedRadiusMeters ??= policy!.defaultRadius;
    } catch (_) {
      error = '서비스에 연결하지 못했습니다. 다시 시도해주세요.';
    }
    userFix = await positionFuture;
    if (_disposed) return;
    userLocation = userFix?.point;
    locating = false;
    if (userLocation != null) {
      center = userLocation;
      source = 'GPS';
    } else {
      message = '위치를 확인할 수 없습니다. 지도를 이동해 검색 위치를 선택해주세요.';
      try {
        final p = await SharedPreferences.getInstance();
        final raw = p.getString('manual-search-center');
        if (raw != null) center = GeoPoint.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    notifyListeners();
    if (center != null) await search();
  }

  void moveCamera(GeoPoint value) {
    cameraMoved(MapCameraEvent(value, CameraMoveOrigin.userGesture));
  }

  void cameraMoved(MapCameraEvent event) {
    if (!event.userInitiated) return;
    userExploring = true;
    final reference = snapshot?.center ?? center;
    pendingCenter =
        reference == null || distanceMeters(reference, event.center) >= 100
        ? event.center
        : null;
    notifyListeners();
  }

  Future<void> searchHere() async {
    if (pendingCenter == null) return;
    _generation++;
    result = null;
    snapshot = null;
    center = pendingCenter;
    source = 'MANUAL';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'manual-search-center',
        jsonEncode(center!.toJson()),
      );
    } catch (_) {}
    await search();
  }

  Future<void> locate() async {
    _generation++;
    loading = false;
    locating = true;
    notifyListeners();
    userFix = await locationService.current();
    if (_disposed) return;
    userLocation = userFix?.point;
    locating = false;
    if (userLocation == null) {
      message = '위치 권한 또는 기기 위치 설정을 확인해주세요. 지도에서 직접 검색할 수도 있습니다.';
      notifyListeners();
      return;
    }
    result = null;
    snapshot = null;
    center = userLocation;
    source = 'GPS';
    pendingCenter = null;
    message = null;
    await search();
  }

  Future<void> search() async {
    if (center == null || _disposed) return;
    final generation = ++_generation;
    final requestCenter = center!;
    final requestSource = source;
    final requestUser = userLocation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      policy ??= await repository.policy();
      requestedRadiusMeters ??= policy!.defaultRadius;
      final response = await repository.search(
        requestCenter,
        requestSource,
        requestUser,
        requestedRadiusMeters ?? policy?.defaultRadius,
      );
      if (generation != _generation || _disposed) return;
      result = response;
      snapshot = SearchPresentationSnapshot(
        center: requestCenter,
        source: requestSource,
        result: response,
        revision: generation,
      );
      pendingCenter = null;
      userExploring = false;
      if (!response.hospitals.any((h) => h.hpid == selectedHpid)) {
        selectedHpid = null;
      }
    } catch (_) {
      if (generation == _generation) {
        error = snapshot == null
            ? '병원 정보를 불러오지 못했습니다. 다시 시도해주세요.'
            : '병원 정보를 새로 불러오지 못했습니다. 이전 검색 결과를 표시합니다.';
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void select(String hpid) {
    if (selectedHpid == hpid ||
        !(snapshot?.result.hospitals.any((h) => h.hpid == hpid) ?? false)) {
      return;
    }
    selectedHpid = hpid;
    notifyListeners();
  }

  Future<void> selectRadius(int radiusMeters) async {
    if (loading || policy == null || !policy!.radii.contains(radiusMeters)) {
      return;
    }
    if (requestedRadiusMeters == radiusMeters && snapshot != null) return;
    requestedRadiusMeters = radiusMeters;
    notifyListeners();
    if (center != null) await search();
  }
}
