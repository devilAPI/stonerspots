import 'package:app/core/api_client.dart';
import 'package:app/features/auth/auth_errors.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a banned account gets its own message', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(
      authErrorText(l, ApiException(403, 'account_banned', 'banned')),
      'This account is banned',
    );
  });
}
