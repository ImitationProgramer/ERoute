import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Invalidates derived sensitive presentation before a local health mutation.
/// Contains no user identifiers or health values.
final privacyChangeProvider = StateProvider<int>((ref) => 0);
