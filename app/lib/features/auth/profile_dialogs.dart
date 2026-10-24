import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'auth_controller.dart';

String _errorText(AppLocalizations l10n, Object e) {
  if (e is ApiException) {
    if (e.code == 'wrong_password') return l10n.wrongPassword;
    if (e.code == 'invalid_password') return l10n.passwordTooShort;
    if (e.message.isNotEmpty) return e.message;
  }
  return l10n.errorGeneric;
}

/// Shows the change-password dialog. Returns true when the password changed.
Future<bool> showChangePasswordDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    ) ??
    false;

/// Shows the delete-account confirmation. Returns true when deleted.
Future<bool> showDeleteAccountDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    ) ??
    false;

/// Shared submit/busy/error handling for the two dialogs.
mixin _SubmitState<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() action) async {
    if (!form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = _errorText(l10n, e);
      });
    }
  }

  Widget? errorText() => error == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog>
    with _SubmitState {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.changePassword),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('current-password'),
                controller: _current,
                decoration: InputDecoration(labelText: l10n.currentPassword),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.isEmpty) ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-password'),
                controller: _next,
                decoration: InputDecoration(labelText: l10n.newPassword),
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return l10n.fieldRequired;
                  if (v.length < 10) return l10n.passwordTooShort;
                  if (v.length > 72) return l10n.passwordTooLong;
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('repeat-password'),
                controller: _repeat,
                decoration: InputDecoration(labelText: l10n.repeatNewPassword),
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return l10n.fieldRequired;
                  if (v != _next.text) return l10n.passwordsDontMatch;
                  return null;
                },
              ),
              ?errorText(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('change-password-submit'),
          onPressed: busy
              ? null
              : () => run(
                  () => ref
                      .read(authControllerProvider.notifier)
                      .changePassword(current: _current.text, next: _next.text),
                ),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog>
    with _SubmitState {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.deleteAccount),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.deleteAccountWarning),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('delete-password'),
                controller: _password,
                decoration: InputDecoration(labelText: l10n.password),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.isEmpty) ? l10n.fieldRequired : null,
              ),
              ?errorText(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('delete-account-submit'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: busy
              ? null
              : () => run(
                  () => ref
                      .read(authControllerProvider.notifier)
                      .deleteAccount(password: _password.text),
                ),
          child: Text(l10n.deleteAccountConfirm),
        ),
      ],
    );
  }
}
