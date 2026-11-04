import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart' show AdminCodeReason;
import '../../core/glass.dart';
import '../../l10n/app_localizations.dart';

/// Field for a 6-digit TOTP code: digits only, large and spaced out.
class TotpCodeField extends StatelessWidget {
  const TotpCodeField({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.errorText,
    this.labelText,
    this.enabled = true,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String? errorText;
  final String? labelText;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    enabled: enabled,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.done,
    autofillHints: const [AutofillHints.oneTimeCode],
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ],
    textAlign: TextAlign.center,
    style: const TextStyle(
      fontFamily: 'monospace',
      fontSize: 24,
      letterSpacing: 8,
    ),
    decoration: InputDecoration(
      labelText: labelText,
      hintText: '000000',
      errorText: errorText,
      errorMaxLines: 3,
    ),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
}

/// Asks the admin for a 2FA code (`ApiClient.onAdminCodeNeeded`).
/// Resolves to the code, or null when cancelled.
Future<String?> showAdminCodeDialog(
  BuildContext context,
  AdminCodeReason reason,
) => showDialog<String>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: false,
  builder: (_) => AdminCodeDialog(reason: reason),
);

class AdminCodeDialog extends StatefulWidget {
  const AdminCodeDialog({super.key, required this.reason});

  final AdminCodeReason reason;

  @override
  State<AdminCodeDialog> createState() => _AdminCodeDialogState();
}

class _AdminCodeDialogState extends State<AdminCodeDialog> {
  final _code = TextEditingController();

  /// The reason's error shows until the admin types again.
  bool _showError = true;

  bool get _complete => _code.text.length == 6;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_complete) Navigator.of(context).pop(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cancel = TextButton(
      key: const Key('admin-code-cancel'),
      onPressed: () => Navigator.of(context).pop(),
      child: Text(
        widget.reason == AdminCodeReason.rateLimited ? l.close : l.cancel,
      ),
    );
    if (widget.reason == AdminCodeReason.rateLimited) {
      return GlassDialog(
        title: Text(l.adminCodeTitle),
        content: Text(
          l.twoFactorErrRateLimited,
          key: const Key('admin-code-error'),
        ),
        actions: [cancel],
      );
    }
    final error = switch (widget.reason) {
      AdminCodeReason.invalid => l.twoFactorErrInvalid,
      AdminCodeReason.reused => l.twoFactorErrReused,
      _ => null,
    };
    return GlassDialog(
      title: Text(l.adminCodeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.reason == AdminCodeReason.expired
                ? l.adminCodeExpired
                : l.adminCodePrompt,
          ),
          const SizedBox(height: 16),
          TotpCodeField(
            key: const Key('admin-code-field'),
            controller: _code,
            autofocus: true,
            errorText: _showError ? error : null,
            onChanged: (_) => setState(() => _showError = false),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        cancel,
        FilledButton(
          key: const Key('admin-code-submit'),
          onPressed: _complete ? _submit : null,
          child: Text(l.twoFactorConfirm),
        ),
      ],
    );
  }
}
