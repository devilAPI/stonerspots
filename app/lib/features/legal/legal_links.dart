import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import 'legal_pages.dart';

/// Opens a legal page on top of the current one.
void openLegalPage(BuildContext context, String path) => context.push(path);

/// A small link (no button padding), for running text and footers.
class LegalLink extends StatelessWidget {
  const LegalLink({super.key, required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => openLegalPage(context, path),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// "Impressum · Datenschutz · Nutzungsregeln" under the login and
/// registration forms.
class LegalLinksFooter extends StatelessWidget {
  const LegalLinksFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dot = Text(' · ', style: Theme.of(context).textTheme.bodySmall);
    return Wrap(
      key: const Key('legalLinks'),
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        LegalLink(
          key: const Key('link-imprint'),
          label: l10n.legalImprint,
          path: kImprintPath,
        ),
        dot,
        LegalLink(
          key: const Key('link-privacy'),
          label: l10n.legalPrivacy,
          path: kPrivacyPath,
        ),
        dot,
        LegalLink(
          key: const Key('link-rules'),
          label: l10n.legalRules,
          path: kRulesPath,
        ),
      ],
    );
  }
}

/// Splits [text] at `[...]` parts: plain text at even indexes, the bracketed
/// link texts at odd ones.
List<String> splitBracketLinks(String text) {
  final parts = <String>[];
  var rest = text;
  while (true) {
    final open = rest.indexOf('[');
    final close = open < 0 ? -1 : rest.indexOf(']', open);
    if (close < 0) {
      parts.add(rest);
      return parts;
    }
    parts
      ..add(rest.substring(0, open))
      ..add(rest.substring(open + 1, close));
    rest = rest.substring(close + 1);
  }
}

/// "Mit der Registrierung akzeptierst du die Nutzungsregeln und hast die
/// Datenschutzerklärung gelesen." with both links. The sentence comes from
/// the translations: its first `[...]` links the rules, the second the
/// privacy policy.
class RegisterConsentText extends StatelessWidget {
  const RegisterConsentText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final parts = splitBracketLinks(
      AppLocalizations.of(context).registerConsent,
    );
    const targets = [
      (key: Key('consent-rules'), path: kRulesPath),
      (key: Key('consent-privacy'), path: kPrivacyPath),
    ];
    return Text.rich(
      key: const Key('registerConsent'),
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < parts.length; i++)
            if (i.isEven)
              TextSpan(text: parts[i])
            else if (i ~/ 2 < targets.length)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: LegalLink(
                  key: targets[i ~/ 2].key,
                  label: parts[i],
                  path: targets[i ~/ 2].path,
                ),
              )
            else
              TextSpan(text: parts[i]),
        ],
      ),
    );
  }
}
