import '../localization/app_strings.dart';
import 'app_exception.dart';

/// Returns a user-facing, localized message for [error]. Diagnostic detail is
/// intentionally NOT shown (it goes to the redacted log instead).
String localizedError(AppStrings strings, Object error) {
  if (error is AppException) {
    final key = 'error_${error.code.toLowerCase()}';
    if (strings.has(key)) return strings.t(key);
  }
  return strings.t('error_generic');
}
