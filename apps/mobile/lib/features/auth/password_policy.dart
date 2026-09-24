import 'package:unorm_dart/unorm_dart.dart' as unicode;

String normalizePassword(String value) => unicode.nfc(value);
String normalizePhone(String value) => value.replaceAll(RegExp(r'[ -]'), '');
String? passwordValidation(String? input) {
  final value = input ?? '';
  if (value.length > 4096) return '비밀번호는 15~128자로 입력해주세요.';
  final length = normalizePassword(value).runes.length;
  return length < 15 || length > 128 ? '비밀번호는 15~128자로 입력해주세요.' : null;
}
