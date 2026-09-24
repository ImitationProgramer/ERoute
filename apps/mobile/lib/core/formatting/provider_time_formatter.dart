/// Formats a provider wall-clock value without assigning or converting a zone.
String? formatProviderWallTime(String? parsed) {
  if (parsed == null) return null;
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$',
  ).firstMatch(parsed);
  if (match == null) return null;
  final year = int.parse(match[1]!),
      month = int.parse(match[2]!),
      day = int.parse(match[3]!);
  final hour = int.parse(match[4]!), minute = int.parse(match[5]!);
  // UTC is used solely to validate calendar components, never as a source instant.
  final calendar = DateTime.utc(year, month, day);
  if (calendar.year != year ||
      calendar.month != month ||
      calendar.day != day ||
      hour > 23 ||
      minute > 59) {
    return null;
  }
  return '${match[1]}.${match[2]}.${match[3]} ${match[4]}:${match[5]}';
}

String formatFetchedTime(DateTime instant) {
  final value = instant.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}.${two(value.month)}.${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}

/// Device-local presentation clock, separate from unverified provider wall time.
DateTime localPresentationNow() => DateTime.now().toLocal();

String formatCollectionAge(DateTime instant, DateTime now) {
  final age = now.difference(instant);
  if (age.isNegative) return formatFetchedTime(instant);
  if (age.inMinutes < 1) return '방금';
  if (age.inHours < 1) return '${age.inMinutes}분 전';
  if (age.inDays < 1) return '${age.inHours}시간 전';
  return formatFetchedTime(instant);
}
