import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';

/// Localized message for a failed login or registration.
String authErrorText(AppLocalizations l, Object e) {
  if (e is! ApiException) return l.errorGeneric;
  return switch (e.code) {
    'invalid_credentials' => l.authErrInvalidCredentials,
    'account_banned' => l.authErrBanned,
    'display_name_taken' => l.authErrNameTaken,
    'invalid_display_name' => l.authErrInvalidName,
    'email_taken' => l.adminErrEmailTaken,
    _ => e.message.isEmpty ? l.errorGeneric : e.message,
  };
}
