import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;
import '../../l10n/app_localizations.dart';

/// What `POST /admin/2fa/enable` hands out: the new secret, and the same as
/// an `otpauth://` URI for the QR code.
class TwoFactorEnrollment {
  const TwoFactorEnrollment({required this.secret, required this.uri});

  final String secret;
  final String uri;

  factory TwoFactorEnrollment.fromJson(Map<String, dynamic> j) =>
      TwoFactorEnrollment(
        secret: (j['secret'] ?? '') as String,
        uri: (j['uri'] ?? '') as String,
      );
}

/// The admin's own TOTP 2FA (`/admin/2fa*`).
abstract class TwoFactorRepository {
  /// Whether 2FA is on for the signed-in admin.
  Future<bool> enabled();

  /// Starts the setup with a new secret; 2FA is on only after [verify].
  Future<TwoFactorEnrollment> start();

  /// Turns 2FA on with the first code from the new secret.
  Future<void> verify(String code);

  /// Turns 2FA off; needs the password and a current code.
  Future<void> disable({required String password, required String code});
}

class ApiTwoFactorRepository implements TwoFactorRepository {
  ApiTwoFactorRepository(this._api);

  final ApiClient _api;

  @override
  Future<bool> enabled() async =>
      ((await _api.get<Map<String, dynamic>>('/admin/2fa'))['enabled'] ?? false)
          as bool;

  @override
  Future<TwoFactorEnrollment> start() async => TwoFactorEnrollment.fromJson(
    await _api.post<Map<String, dynamic>>('/admin/2fa/enable'),
  );

  @override
  Future<void> verify(String code) =>
      _api.post<dynamic>('/admin/2fa/verify', data: {'code': code});

  @override
  Future<void> disable({required String password, required String code}) async {
    // The route wants 2FA proof like any admin route. The code from the form
    // opens the session for it, so the admin is not asked a second time; the
    // server accepts the same code once more in the body.
    if (!_api.hasAdminSession) await _api.openAdminSession(code);
    await _api.post<dynamic>(
      '/admin/2fa/disable',
      data: {'password': password, 'code': code},
    );
    _api.clearAdminSession();
  }
}

final twoFactorRepositoryProvider = Provider<TwoFactorRepository>(
  (ref) => ApiTwoFactorRepository(ref.watch(apiClientProvider)),
);

/// Localized inline message for an error of the 2FA routes.
String twoFactorErrorText(AppLocalizations l, Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'totp_invalid':
        return l.twoFactorErrInvalid;
      case 'totp_reused':
        return l.twoFactorErrReused;
      case 'invalid_code':
        return l.twoFactorErrDigits;
      case 'rate_limited':
        return l.twoFactorErrRateLimited;
      case 'no_secret':
        return l.twoFactorErrNoSecret;
      case 'already_enabled':
        return l.twoFactorErrAlreadyOn;
      case 'not_enabled' || 'totp_not_enabled':
        return l.twoFactorErrNotOn;
      case 'wrong_password':
        return l.wrongPassword;
    }
  }
  return l.errorGeneric;
}
