import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UI assumptions, not MFDS fields or an HTTP/DB schema. An explicit selection
/// is stored separately from the user's name/note; never match legacy names.
class MedicationProduct {
  final String source, sourceLabel, id, name;
  final String? strength, form, manufacturer, description, imageAsset;
  const MedicationProduct({
    required this.source,
    required this.sourceLabel,
    required this.id,
    required this.name,
    this.strength,
    this.form,
    this.manufacturer,
    this.description,
    this.imageAsset,
  });
  String get variant => '${strength ?? '함량 정보 없음'} · ${form ?? '제형 정보 없음'}';
  bool sameProduct(MedicationProduct other) =>
      source == other.source && id == other.id;
}

abstract interface class MedicationProductRepository {
  String get sourceLabel;
  bool get available;
  Future<List<MedicationProduct>> search(String query);
}

final medicationProductRepositoryProvider =
    Provider<MedicationProductRepository>(
      (ref) => UnavailableMedicationProducts(),
    );

class MedicationSearchState {
  final String query;
  final bool busy, attempted;
  final List<MedicationProduct> products;
  final String? error;
  MedicationSearchState({
    this.query = '',
    this.busy = false,
    this.attempted = false,
    List<MedicationProduct> products = const [],
    this.error,
  }) : products = List.unmodifiable(products);
}

class MedicationSearchController extends StateNotifier<MedicationSearchState> {
  final MedicationProductRepository repository;
  int _request = 0;
  MedicationSearchController(this.repository) : super(MedicationSearchState());
  void clear() {
    ++_request;
    state = MedicationSearchState();
  }

  Future<void> search(String text) async {
    final query = text.trim();
    final request = ++_request;
    if (query.isEmpty) {
      state = MedicationSearchState();
      return;
    }
    if (query.length > 80) {
      state = MedicationSearchState(
        query: query,
        error: '검색어는 80자 이내로 입력해주세요.',
      );
      return;
    }
    state = MedicationSearchState(query: query, busy: true, attempted: true);
    try {
      final products = await repository.search(query);
      if (!mounted || request != _request) return;
      state = MedicationSearchState(
        query: query,
        products: products,
        attempted: true,
      );
    } catch (_) {
      if (!mounted || request != _request) return;
      state = MedicationSearchState(
        query: query,
        attempted: true,
        error: '약을 검색하지 못했어요. 다시 검색하거나 직접 입력해주세요.',
      );
    }
  }
}

final medicationSearchProvider =
    StateNotifierProvider.autoDispose<
      MedicationSearchController,
      MedicationSearchState
    >(
      (ref) => MedicationSearchController(
        ref.watch(medicationProductRepositoryProvider),
      ),
    );

class UnavailableMedicationProducts implements MedicationProductRepository {
  @override
  bool get available => false;
  @override
  String get sourceLabel => '약 검색 준비 중';
  @override
  Future<List<MedicationProduct>> search(String query) =>
      Future.error(StateError('PRODUCT_SEARCH_UNAVAILABLE'));
}
