import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Asks [title] (and [body]) with "Cancel" and [confirm]; true when the
/// user confirmed. [danger] makes the confirm button red, for what cannot
/// be undone. [confirmKey] finds that button in tests.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String confirm,
  required Key confirmKey,
  bool danger = false,
}) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: confirmKey,
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirm),
          ),
        ],
      );
    },
  );
  return ok == true;
}

extension ShowText on ScaffoldMessengerState {
  /// Shows [text] in a snackbar.
  void showText(String text) => showSnackBar(SnackBar(content: Text(text)));
}
