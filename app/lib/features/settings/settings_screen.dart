import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/back_or_home.dart';
import '../../core/glass.dart';
import '../../core/settings.dart';
import '../../l10n/app_localizations.dart';
import '../updater/update_controller.dart';
import '../updater/update_ui.dart';
import 'whats_new.dart';

/// App settings, in sections. A new setting is one more tile in a section,
/// usually a [BoolSetting] provider.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const BackOrHomeButton(),
        title: Text(l10n.settingsTitle),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              safe.left + 16,
              GlassAppBar.contentTop(context) + 8,
              safe.right + 16,
              safe.bottom + 16,
            ),
            children: [
              _Section(
                title: l10n.settingsAppearance,
                children: [
                  SwitchListTile(
                    key: const Key('disableTransparency'),
                    title: Text(l10n.settingsDisableTransparency),
                    subtitle: Text(l10n.settingsDisableTransparencyHint),
                    value: ref.watch(transparencyDisabledProvider),
                    onChanged: ref
                        .read(transparencyDisabledProvider.notifier)
                        .set,
                  ),
                ],
              ),
              if (ref.watch(updaterConfigProvider).platform != null) ...[
                const SizedBox(height: 16),
                _Section(
                  title: l10n.settingsUpdates,
                  children: const [UpdateSettingsTiles()],
                ),
              ],
              const SizedBox(height: 16),
              _Section(
                title: l10n.settingsAbout,
                children: [
                  ListTile(
                    key: const Key('whatsNew'),
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text(l10n.whatsNewTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showWhatsNewDialog(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A headed group of settings on a card.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Material(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
