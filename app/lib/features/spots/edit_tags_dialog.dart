import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'add_spot_errors.dart';
import 'spot_api.dart';

/// Localized message for a failed `PUT /spots/{id}/tags`.
String spotTagsErrorText(AppLocalizations l, Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'forbidden':
        return l.tagsErrForbidden;
      case 'invalid_tags':
        return l.tagsErrInvalid;
    }
  }
  return addSpotErrorText(l, e);
}

/// Lets the author or an admin change a spot's tags. Resolves to the updated
/// spot, or null when cancelled.
Future<Spot?> showEditTagsDialog(
  BuildContext context, {
  required int spotId,
  required List<SpotTag> initial,
}) => showDialog<Spot>(
  context: context,
  builder: (_) => _EditTagsDialog(spotId: spotId, initial: initial),
);

class _EditTagsDialog extends ConsumerStatefulWidget {
  const _EditTagsDialog({required this.spotId, required this.initial});

  final int spotId;
  final List<SpotTag> initial;

  @override
  ConsumerState<_EditTagsDialog> createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends ConsumerState<_EditTagsDialog> {
  late List<SpotTag> _tags = SpotTag.sorted(widget.initial);
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final spot = await ref
          .read(spotApiProvider)
          .setTags(widget.spotId, _tags);
      if (mounted) Navigator.pop(context, spot);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = spotTagsErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.editTags),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SpotTagSelector(
              keyPrefix: 'editTag-',
              selected: _tags,
              onChanged: (next) => setState(() => _tags = next),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('editTagsError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('editTagsSave'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
