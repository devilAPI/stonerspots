import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import 'auth_controller.dart';
import 'profile_dialogs.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navProfile)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: user == null
                ? FilledButton(
                    onPressed: () => context.push('/login'),
                    child: Text(l10n.login),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        user.displayName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      if (user.isAdmin) ...[
                        FilledButton.tonalIcon(
                          key: const Key('open-admin'),
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          onPressed: () => context.push('/admin'),
                          label: Text(l10n.adminOpen),
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton(
                        key: const Key('change-password'),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final done = await showChangePasswordDialog(context);
                          if (done) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(l10n.passwordChanged)),
                            );
                          }
                        },
                        child: Text(l10n.changePassword),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () =>
                            ref.read(authControllerProvider.notifier).logout(),
                        child: Text(l10n.logout),
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        key: const Key('delete-account'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        ),
                        icon: const Icon(Icons.delete_forever),
                        onPressed: () => showDeleteAccountDialog(context),
                        label: Text(l10n.deleteAccount),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
