import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _adult = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).register(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
          adult: _adult,
        );
    if (!mounted) return;
    if (ref.read(authControllerProvider).value != null) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    final error = auth.error;
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.register)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: l10n.displayName),
                  validator: required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: InputDecoration(labelText: l10n.email),
                  keyboardType: TextInputType.emailAddress,
                  validator: required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(labelText: l10n.password),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.length < 10) ? l10n.passwordTooShort : null,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _adult,
                  onChanged: (v) => setState(() => _adult = v ?? false),
                  title: Text(l10n.adultConfirm),
                ),
                if (error != null)
                  Text(
                    error is ApiException ? error.message : l10n.errorGeneric,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: (_adult && !auth.isLoading) ? _submit : null,
                  child: Text(l10n.register),
                ),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: Text(l10n.haveAccount),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
