import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/glass.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../activity/activity_bell.dart';
import '../users/user_profile_screen.dart';
import 'auth_controller.dart';
import 'profile_dialogs.dart';

/// The profile tab: your own profile page, laid out like everyone else's,
/// with your account's buttons in the header and the account menu.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return const _LoggedOut();
    return UserProfileScreen(
      // a new page per account, so nothing of the last one stays
      key: ValueKey('profile-${user.id}'),
      userId: user.id,
      asTab: true,
      actions: [
        const ActivityBell(),
        const _SettingsButton(),
        _AccountMenu(user: user),
      ],
      headerExtra: _OwnButtons(user: user),
    );
  }
}

class _LoggedOut extends StatelessWidget {
  const _LoggedOut();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(l10n.navProfile),
        actions: const [_SettingsButton()],
      ),
      // Its padding covers the bar and the shell's glass navigation.
      body: Center(
        child: Padding(
          padding: MediaQuery.paddingOf(context).add(const EdgeInsets.all(16)),
          child: FilledButton(
            onPressed: () => context.push('/login'),
            child: Text(l10n.login),
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('open-settings'),
    tooltip: AppLocalizations.of(context).settingsTitle,
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => context.push('/settings'),
  );
}

/// Saved spots, and the admin page for admins, under your counts.
class _OwnButtons extends StatelessWidget {
  const _OwnButtons({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            key: const Key('open-saved'),
            icon: const Icon(Icons.bookmark_border),
            onPressed: () => context.push('/saved'),
            label: Text(l10n.saved),
          ),
        ),
        if (user.isAdmin) ...[
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonalIcon(
              key: const Key('open-admin'),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.push('/admin'),
              label: Text(l10n.adminOpen),
            ),
          ),
        ],
      ],
    );
  }
}

enum _AccountAction { password, logout, delete }

/// Your email and what you can do with the account.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final error = Theme.of(context).colorScheme.error;
    return PopupMenuButton<_AccountAction>(
      key: const Key('account-menu'),
      tooltip: l10n.profileAccountMenu,
      icon: const Icon(Icons.more_vert),
      onSelected: (a) => _run(context, ref, a),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alternate_email),
            title: Text(user.email),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('change-password'),
          value: _AccountAction.password,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.changePassword),
          ),
        ),
        PopupMenuItem(
          key: const Key('logout'),
          value: _AccountAction.logout,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: Text(l10n.logout),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('delete-account'),
          value: _AccountAction.delete,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            iconColor: error,
            textColor: error,
            leading: const Icon(Icons.delete_forever),
            title: Text(l10n.deleteAccount),
          ),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _AccountAction a,
  ) async {
    switch (a) {
      case _AccountAction.password:
        final l10n = AppLocalizations.of(context);
        final messenger = ScaffoldMessenger.of(context);
        if (await showChangePasswordDialog(context)) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.passwordChanged)));
        }
      case _AccountAction.logout:
        await ref.read(authControllerProvider.notifier).logout();
      case _AccountAction.delete:
        await showDeleteAccountDialog(context);
    }
  }
}
