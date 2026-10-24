import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'review_models.dart';

const int kReviewMaxLength = 1000;

String reviewErrorText(AppLocalizations l, Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_rating':
        return l.reviewErrorInvalidRating;
      case 'invalid_body':
        return l.reviewErrorInvalidBody;
      case 'own_spot':
        return l.reviewErrorOwnSpot;
    }
  }
  return l.errorGeneric;
}

/// Shows the review dialog. [onSave] performs the request; if it throws, the
/// error is shown inline and the dialog stays open. Resolves to true when
/// saved.
Future<bool?> showReviewDialog(
  BuildContext context, {
  Review? existing,
  required Future<void> Function(int rating, String body) onSave,
}) => showDialog<bool>(
  context: context,
  builder: (_) => ReviewDialog(existing: existing, onSave: onSave),
);

class ReviewDialog extends StatefulWidget {
  const ReviewDialog({super.key, this.existing, required this.onSave});

  final Review? existing;
  final Future<void> Function(int rating, String body) onSave;

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  late final TextEditingController _body = TextEditingController(
    text: widget.existing?.body ?? '',
  );
  late int _rating = widget.existing?.rating ?? 0;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final l = AppLocalizations.of(context);
    try {
      await widget.onSave(_rating, _body.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = reviewErrorText(l, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = Colors.amber.shade700;
    return AlertDialog(
      title: Text(widget.existing == null ? l.reviewWrite : l.reviewEditMine),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      key: Key('reviewStar_$i'),
                      tooltip: l.reviewStarLabel(i),
                      isSelected: _rating >= i,
                      onPressed: _saving
                          ? null
                          : () => setState(() => _rating = i),
                      icon: Icon(Icons.star_border, color: color, size: 32),
                      selectedIcon: Icon(Icons.star, color: color, size: 32),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('reviewBody'),
                controller: _body,
                enabled: !_saving,
                minLines: 3,
                maxLines: 6,
                maxLength: kReviewMaxLength,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l.reviewBodyHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  key: const Key('reviewError'),
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('reviewSave'),
          onPressed: _rating == 0 || _saving ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
