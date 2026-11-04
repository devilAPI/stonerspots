import 'package:flutter/material.dart';

/// One block of a legal text.
sealed class LegalBlock {
  const LegalBlock();
}

class LegalHeading extends LegalBlock {
  const LegalHeading(this.level, this.text);

  /// 1 (`# `), 2 (`## `) or 3 (`### `).
  final int level;
  final String text;
}

class LegalParagraph extends LegalBlock {
  const LegalParagraph(this.text);
  final String text;
}

class LegalBullet extends LegalBlock {
  const LegalBullet(this.text);
  final String text;
}

/// A `{{name}}` line: the page puts a widget of its own there (e.g. the
/// operator's details from the server).
class LegalSlot extends LegalBlock {
  const LegalSlot(this.name);
  final String name;
}

/// Parses the small Markdown subset the legal texts use:
///
/// - `# `, `## `, `### ` headings
/// - `- ` list items (following lines indented by two spaces belong to
///   the item)
/// - paragraphs (lines up to the next blank line)
/// - `**bold**` inside any text
/// - a line `{{name}}` alone: a slot for a widget
List<LegalBlock> parseLegalMarkdown(String source) {
  final blocks = <LegalBlock>[];
  final para = <String>[];
  String? bullet;

  void flush() {
    if (para.isNotEmpty) {
      blocks.add(LegalParagraph(para.join(' ')));
      para.clear();
    }
    if (bullet != null) {
      blocks.add(LegalBullet(bullet!));
      bullet = null;
    }
  }

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      flush();
      continue;
    }
    final heading = RegExp(r'^(#{1,3}) (.*)$').firstMatch(trimmed);
    if (heading != null && !line.startsWith(' ')) {
      flush();
      blocks.add(LegalHeading(heading.group(1)!.length, heading.group(2)!));
      continue;
    }
    final slot = RegExp(r'^\{\{(\w+)\}\}$').firstMatch(trimmed);
    if (slot != null) {
      flush();
      blocks.add(LegalSlot(slot.group(1)!));
      continue;
    }
    if (line.startsWith('- ')) {
      flush();
      bullet = line.substring(2).trim();
      continue;
    }
    if (bullet != null && line.startsWith('  ')) {
      bullet = '$bullet $trimmed';
      continue;
    }
    if (bullet != null) flush();
    para.add(trimmed);
  }
  flush();
  return blocks;
}

/// [text] with `**bold**` parts in bold.
TextSpan legalSpan(String text, TextStyle? style) {
  final parts = text.split('**');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(
            text: parts[i],
            style: i.isOdd
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          ),
    ],
  );
}

/// Renders a legal text written in the subset [parseLegalMarkdown] reads.
/// [slots] fill the `{{name}}` lines; unknown slots are left out.
class LegalMarkdown extends StatelessWidget {
  const LegalMarkdown(this.source, {super.key, this.slots = const {}});

  final String source;
  final Map<String, Widget> slots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final body = theme.bodyMedium?.copyWith(height: 1.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in parseLegalMarkdown(source))
          switch (b) {
            LegalHeading(:final level, :final text) => Padding(
              padding: EdgeInsets.only(top: level == 1 ? 0 : 20, bottom: 8),
              child: Text(
                text,
                style: switch (level) {
                  1 => theme.headlineSmall,
                  2 => theme.titleMedium,
                  _ => theme.titleSmall,
                },
              ),
            ),
            LegalParagraph(:final text) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text.rich(legalSpan(text, body)),
            ),
            LegalBullet(:final text) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: body),
                  Expanded(child: Text.rich(legalSpan(text, body))),
                ],
              ),
            ),
            LegalSlot(:final name) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: slots[name] ?? const SizedBox.shrink(),
            ),
          },
      ],
    );
  }
}
