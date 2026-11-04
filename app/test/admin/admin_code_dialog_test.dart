import 'package:app/core/api_client.dart' show AdminCodeReason;
import 'package:app/features/admin/admin_code_dialog.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the dialog for [reason]; [result] gets what it resolves to.
Future<void> _open(
  WidgetTester t,
  AdminCodeReason reason,
  void Function(String?) result,
) async {
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async =>
                result(await showAdminCodeDialog(context, reason)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

Finder get _field => find.byKey(const Key('admin-code-field'));

FilledButton _submit(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('admin-code-submit')));

void main() {
  testWidgets('six digits, focused, Enter submits', (t) async {
    String? got = 'unset';
    await _open(t, AdminCodeReason.required, (r) => got = r);

    expect(find.text('Admin confirmation'), findsOneWidget);
    expect(find.textContaining('Enter the 6-digit code'), findsOneWidget);
    final editable = t.widget<EditableText>(
      find.descendant(of: _field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    // only digits, at most six
    await t.enterText(_field, '12ab34');
    await t.pump();
    expect(find.text('1234'), findsOneWidget);
    expect(_submit(t).onPressed, isNull);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(got, 'unset'); // not yet complete: stays open

    await t.enterText(_field, '1234567');
    await t.pump();
    expect(find.text('123456'), findsOneWidget);
    expect(_submit(t).onPressed, isNotNull);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(got, '123456');
    expect(_field, findsNothing);
  });

  testWidgets('the button submits too', (t) async {
    String? got;
    await _open(t, AdminCodeReason.required, (r) => got = r);
    await t.enterText(_field, '654321');
    await t.pump();
    await t.tap(find.byKey(const Key('admin-code-submit')));
    await t.pumpAndSettle();
    expect(got, '654321');
  });

  testWidgets('cancel resolves to null', (t) async {
    String? got = 'unset';
    await _open(t, AdminCodeReason.required, (r) => got = r);
    await t.enterText(_field, '123456');
    await t.tap(find.byKey(const Key('admin-code-cancel')));
    await t.pumpAndSettle();
    expect(got, isNull);
  });

  testWidgets('a wrong code shows why until the admin types', (t) async {
    await _open(t, AdminCodeReason.invalid, (_) {});
    expect(find.text('Wrong code. Try again.'), findsOneWidget);
    await t.enterText(_field, '1');
    await t.pump();
    expect(find.text('Wrong code. Try again.'), findsNothing);
  });

  testWidgets('a used code says to wait for the next one', (t) async {
    await _open(t, AdminCodeReason.reused, (_) {});
    expect(find.textContaining('used already'), findsOneWidget);
  });

  testWidgets('an expired session says so', (t) async {
    await _open(t, AdminCodeReason.expired, (_) {});
    expect(find.textContaining('session has expired'), findsOneWidget);
  });

  testWidgets('too many attempts: only the message and close', (t) async {
    String? got = 'unset';
    await _open(t, AdminCodeReason.rateLimited, (r) => got = r);
    expect(find.text('Too many attempts. Wait a few minutes.'), findsOneWidget);
    expect(_field, findsNothing);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(got, isNull);
  });
}
