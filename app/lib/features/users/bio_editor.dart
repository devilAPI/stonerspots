import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Longest bio in characters and lines (`PUT /me/bio`).
const kBioMaxLength = 300;
const kBioMaxLines = 6;

/// Lines of [bio] as the server counts them, after it collapses runs of
/// empty lines and trims both ends.
int bioLineCount(String bio) {
  final t = bio.trim().replaceAll(RegExp(r'\n\s*\n(\s*\n)+'), '\n\n');
  return t.isEmpty ? 0 : '\n'.allMatches(t).length + 1;
}

/// Asks for a new bio, starting from [current]. Resolves to the text to
/// save ("" removes it), or null when cancelled.
Future<String?> showBioDialog(
  BuildContext context, {
  required String current,
}) => showDialog<String>(
  context: context,
  builder: (_) => _BioDialog(current: current),
);

class _BioDialog extends StatefulWidget {
  const _BioDialog({required this.current});

  final String current;

  @override
  State<_BioDialog> createState() => _BioDialogState();
}

class _BioDialogState extends State<_BioDialog> {
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tooManyLines = bioLineCount(_text.text) > kBioMaxLines;
    return AlertDialog(
      title: Text(l.userBioTitle),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('bioField'),
          controller: _text,
          autofocus: true,
          minLines: 3,
          maxLines: kBioMaxLines,
          maxLength: kBioMaxLength,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l.userBioHint,
            errorText: tooManyLines
                ? l.userBioTooManyLines(kBioMaxLines)
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('bioSave'),
          onPressed: tooManyLines
              ? null
              : () => Navigator.pop(context, _text.text.trim()),
          child: Text(l.save),
        ),
      ],
    );
  }
}
