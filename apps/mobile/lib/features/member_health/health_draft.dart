/// Only memory. Revalidation, notifications and app switches never extend TTL.
class HealthDraft {
  final Duration Function() elapsed;
  final Duration ttl;
  String? userId;
  int? sessionGeneration, consentEpoch, dataVersion;
  Map<String, dynamic>? values;
  Duration? editedAt;
  HealthDraft({required this.elapsed, this.ttl = const Duration(minutes: 10)});
  void edit({
    required String user,
    required int session,
    required int epoch,
    required int version,
    required Map<String, dynamic> data,
  }) {
    userId = user;
    sessionGeneration = session;
    consentEpoch = epoch;
    dataVersion = version;
    values = data;
    editedAt = elapsed();
  }

  bool get expired => editedAt != null && elapsed() - editedAt! >= ttl;
  Map<String, dynamic>? restore(
    String user,
    int session,
    int epoch,
    int version,
  ) {
    if (expired ||
        userId != user ||
        sessionGeneration != session ||
        consentEpoch != epoch) {
      clear();
      return null;
    }
    if (dataVersion != version) return null;
    return values;
  }

  void clear() {
    values = null;
    editedAt = null;
    userId = null;
    sessionGeneration = null;
    consentEpoch = null;
    dataVersion = null;
  }
}
