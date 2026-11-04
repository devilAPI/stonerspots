import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/back_or_home.dart';
import '../../core/glass.dart';
import '../../l10n/app_localizations.dart';
import 'legal_info.dart';
import 'legal_markdown.dart';
import 'privacy_text.dart';
import 'rules_text.dart';

/// Routes of the legal pages. They work logged in and out, and on the web
/// they can be linked from outside (`…/#/legal/imprint`; the static pages in
/// `web/legal/` forward `…/legal/imprint` there).
const kImprintPath = '/legal/imprint';
const kPrivacyPath = '/legal/privacy';
const kRulesPath = '/legal/rules';

/// German for German, English for everything else (the app's two
/// languages).
bool _german(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'de';

/// Page frame of the legal pages: glass app bar, a readable column of
/// selectable text.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const BackOrHomeButton(),
        title: Text(title),
      ),
      body: SelectionArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                safe.left + 20,
                GlassAppBar.contentTop(context) + 12,
                safe.right + 20,
                safe.bottom + 32,
              ),
              children: [child],
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds [builder] with the operator details, or the "not set up yet"
/// note ([notConfigured]) when the server has none or cannot be asked.
class _WithLegalInfo extends ConsumerWidget {
  const _WithLegalInfo({required this.builder, required this.notConfigured});

  final Widget Function(LegalInfo info) builder;
  final String notConfigured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(legalInfoProvider);
    return switch (info) {
      AsyncData(:final value) when value.configured => builder(value),
      AsyncData() => _Note(text: notConfigured),
      AsyncError() => _Note(
        text: notConfigured,
        onRetry: () => ref.invalidate(legalInfoProvider),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('legalNotConfigured'),
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      child: Text(AppLocalizations.of(context).retry),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name, address lines and optional country.
List<Widget> _postal(LegalInfo info, {String? name}) => [
  Text(name ?? info.operatorName),
  for (final line in info.address.split('\n'))
    if (line.trim().isNotEmpty) Text(line.trim()),
  if (info.country.isNotEmpty) Text(info.country),
];

/// Impressum / legal notice in the usual § 5 DDG layout.
class ImprintScreen extends StatelessWidget {
  const ImprintScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return LegalPage(
      title: l10n.legalImprint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.legalImprint, style: text.headlineSmall),
          const SizedBox(height: 16),
          _WithLegalInfo(
            notConfigured: l10n.legalNotConfigured,
            builder: (info) => Column(
              key: const Key('imprintDetails'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.legalImprintHeading, style: text.titleMedium),
                const SizedBox(height: 8),
                ..._postal(info),
                const SizedBox(height: 20),
                Text(l10n.legalContact, style: text.titleMedium),
                const SizedBox(height: 8),
                Text('${l10n.legalEmail}: ${info.email}'),
                if (info.phone.isNotEmpty)
                  Text('${l10n.legalPhone}: ${info.phone}'),
                const SizedBox(height: 20),
                Text(l10n.legalResponsible, style: text.titleMedium),
                const SizedBox(height: 8),
                ..._postal(info, name: info.responsible),
                if (info.extra.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(info.extra),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The operator as controller, at the top of the privacy policy.
class _Controller extends StatelessWidget {
  const _Controller();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _WithLegalInfo(
      notConfigured: l10n.legalNotConfiguredPrivacy,
      builder: (info) => Column(
        key: const Key('privacyController'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._postal(info),
          Text('${l10n.legalEmail}: ${info.email}'),
          if (info.phone.isNotEmpty) Text('${l10n.legalPhone}: ${info.phone}'),
          const SizedBox(height: 8),
          Text('${l10n.legalPrivacyContact}: ${info.privacyEmail}'),
        ],
      ),
    );
  }
}

/// Datenschutzerklärung / privacy policy.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => LegalPage(
    title: AppLocalizations.of(context).legalPrivacy,
    child: LegalMarkdown(
      _german(context) ? privacyTextDe : privacyTextEn,
      slots: const {'controller': _Controller()},
    ),
  );
}

/// Nutzungsregeln / community rules.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) => LegalPage(
    title: AppLocalizations.of(context).legalRules,
    child: LegalMarkdown(_german(context) ? rulesTextDe : rulesTextEn),
  );
}
