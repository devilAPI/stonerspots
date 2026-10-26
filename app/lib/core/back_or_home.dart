import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';

/// App bar leading for pages outside the tab shell (spot, add spot, login,
/// register, admin). Such a page can be the only one on the stack (opened
/// from a link, or after `go`), where Flutter would show no back button at
/// all; then this goes to the home map instead of leaving the user stuck.
class BackOrHomeButton extends StatelessWidget {
  const BackOrHomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    // without a router (widget tests) behave like the default leading
    if (GoRouter.maybeOf(context) == null) {
      return Navigator.canPop(context)
          ? const BackButton()
          : const SizedBox.shrink();
    }
    if (context.canPop()) return const BackButton();
    return IconButton(
      key: const Key('backToHome'),
      tooltip: AppLocalizations.of(context).backToHome,
      icon: const Icon(Icons.arrow_back),
      onPressed: () => context.go('/'),
    );
  }
}

/// Wraps a page outside the tab shell so the system back (Android button or
/// gesture) on a page with nothing below goes to the home map instead of
/// closing the app.
class BackToHomeScope extends StatelessWidget {
  const BackToHomeScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: GoRouter.maybeOf(context) == null || context.canPop(),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) context.go('/');
    },
    child: child,
  );
}
