import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_or_home.dart';
import '../../l10n/app_localizations.dart';
import 'auth_errors.dart';

/// Page frame shared by login and registration: [fields] in a narrow
/// centred form, the auth [error] below them, the submit button and a link
/// to the other page ([switchLabel], replacing this one with [switchTo]).
class AuthFormPage extends StatelessWidget {
  const AuthFormPage({
    super.key,
    required this.formKey,
    required this.title,
    required this.fields,
    required this.error,
    required this.onSubmit,
    required this.switchLabel,
    required this.switchTo,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final List<Widget> fields;
  final Object? error;

  /// Null disables the button.
  final VoidCallback? onSubmit;
  final String switchLabel;
  final String switchTo;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              children: [
                ...fields,
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    authErrorText(AppLocalizations.of(context), error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: onSubmit, child: Text(title)),
                TextButton(
                  onPressed: () => context.pushReplacement(switchTo),
                  child: Text(switchLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
