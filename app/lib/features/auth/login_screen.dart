import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import 'auth_controller.dart';
import 'auth_form_page.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.redirectTo});

  /// Where to go after a successful login (defaults to the map).
  final String? redirectTo;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(authControllerProvider.notifier)
        .login(_email.text, _password.text);
    if (!mounted) return;
    if (ref.read(authControllerProvider).value != null) {
      final to = widget.redirectTo;
      if (to != null) {
        // sent here by the auth redirect: on to the page that was asked for
        context.canPop() ? context.pushReplacement(to) : context.go(to);
      } else {
        // opened from a page: back to it
        context.canPop() ? context.pop() : context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    return AuthFormPage(
      formKey: _form,
      title: l10n.login,
      error: auth.error,
      onSubmit: auth.isLoading ? null : _submit,
      switchLabel: l10n.noAccountYet,
      switchTo: '/register',
      fields: [
        TextFormField(
          key: const Key('loginEmail'),
          controller: _email,
          // type right away; Tab then goes on to the password
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.loginId),
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          textInputAction: TextInputAction.next,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('loginPassword'),
          controller: _password,
          decoration: InputDecoration(labelText: l10n.password),
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          // Enter logs in
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) {
            if (!auth.isLoading) _submit();
          },
          validator: (v) =>
              (v == null || v.isEmpty) ? l10n.fieldRequired : null,
        ),
      ],
    );
  }
}
