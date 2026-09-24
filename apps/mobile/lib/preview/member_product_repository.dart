import '../features/member_ui/member_product.dart';

enum PreviewProductScenario {
  standard,
  noResults,
  failure,
  noDescription,
  noImage,
  longName,
}

/// Fictional fixture catalog only. No Dio, HTTP, assets from network or real IDs.
class PreviewProductRepository implements MedicationProductRepository {
  @override
  bool get available => true;
  PreviewProductScenario scenario = PreviewProductScenario.standard;
  Duration delay;
  PreviewProductRepository({this.delay = const Duration(milliseconds: 650)});
  @override
  String get sourceLabel => '가상 제품 · UI 검수용';
  static const products = [
    MedicationProduct(
      source: 'UI_PREVIEW_PRODUCTS',
      sourceLabel: '가상 제품 · UI 검수용',
      id: 'preview-product-100-tablet',
      name: '가상해봄',
      strength: '100 mg',
      form: '정제',
      manufacturer: '가상 제조사',
      description: '화면 검수용으로 만든 제품입니다. 실제 의약품의 효능이나 복용법을 나타내지 않습니다.',
    ),
    MedicationProduct(
      source: 'UI_PREVIEW_PRODUCTS',
      sourceLabel: '가상 제품 · UI 검수용',
      id: 'preview-product-200-tablet',
      name: '가상해봄',
      strength: '200 mg',
      form: '정제',
      manufacturer: '가상 제조사',
    ),
    MedicationProduct(
      source: 'UI_PREVIEW_PRODUCTS',
      sourceLabel: '가상 제품 · UI 검수용',
      id: 'preview-product-100-capsule',
      name: '가상해봄',
      strength: '100 mg',
      form: '캡슐',
      description: '함량이 같아도 제형이 다른 제품을 구분하는 검수용 정보입니다.',
    ),
  ];
  static const longProduct = MedicationProduct(
    source: 'UI_PREVIEW_PRODUCTS',
    sourceLabel: '가상 제품 · UI 검수용',
    id: 'preview-product-long-name',
    name: '가상해봄 긴 제품 이름 줄바꿈과 함량 및 제형 구분을 확인하는 화면 검수 전용 테스트 제품',
    strength: '100 mg',
    form: '캡슐',
    manufacturer: '가상 제조사 · 긴 업체 이름 표시 검수',
  );
  @override
  Future<List<MedicationProduct>> search(String query) async {
    final current = scenario;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (current == PreviewProductScenario.failure) {
      throw StateError('Preview search failure');
    }
    if (current == PreviewProductScenario.noResults) return [];
    final matches =
        (current == PreviewProductScenario.longName ? [longProduct] : products)
            .where(
              (p) => '${p.name} ${p.strength} ${p.form}'.contains(query.trim()),
            )
            .toList();
    if (current == PreviewProductScenario.noDescription) {
      return matches.where((p) => p.description == null).toList();
    }
    // All fixtures intentionally have no product photo. NoImage is an explicit
    // QA entry, with the first variant for an unambiguous empty-image state.
    if (current == PreviewProductScenario.noImage) {
      return matches.take(1).toList();
    }
    return matches;
  }
}
