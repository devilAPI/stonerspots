import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dialogs.dart';
import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'saved_controller.dart';
import 'saved_repository.dart';

/// Same limit as the API.
const int kMaxListNameLength = 60;

/// Creates a list, or renames [list]; resolves to the saved list, or null
/// when cancelled.
Future<SpotList?> showListNameDialog(BuildContext context, {SpotList? list}) =>
    showDialog<SpotList>(
      context: context,
      builder: (_) => _ListNameDialog(list: list),
    );

class _ListNameDialog extends ConsumerStatefulWidget {
  const _ListNameDialog({this.list});

  final SpotList? list;

  @override
  ConsumerState<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends ConsumerState<_ListNameDialog> {
  late final _name = TextEditingController(text: widget.list?.name ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && _name.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l = AppLocalizations.of(context);
    final repo = ref.read(savedRepositoryProvider);
    final list = widget.list;
    final name = _name.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = list == null
          ? await repo.create(name)
          : await repo.rename(list.id, name);
      if (!mounted) return;
      ref.invalidate(savedListsProvider);
      if (list != null) ref.invalidate(savedListProvider(list.id));
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e) {
          ApiException(code: 'name_taken') => l.savedNameTaken,
          ApiException(code: 'list_limit') => l.savedListLimit,
          _ => l.errorGeneric,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.list == null ? l.savedNewList : l.savedRenameList),
      content: TextField(
        key: const Key('listName'),
        controller: _name,
        autofocus: true,
        maxLength: kMaxListNameLength,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: l.savedListName,
          errorText: _error,
        ),
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('listNameSave'),
          onPressed: _canSubmit ? _submit : null,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Asks, then deletes [list]; resolves to true when it is gone.
Future<bool> confirmDeleteList(
  BuildContext context,
  WidgetRef ref,
  SpotList list,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(savedRepositoryProvider);
  final sure = await confirmDialog(
    context,
    title: l.savedDeleteTitle,
    body: l.savedDeleteBody(list.title(l)),
    confirm: l.savedDelete,
    confirmKey: const Key('confirmDeleteList'),
    danger: true,
  );
  if (!sure) return false;
  try {
    await repo.deleteList(list.id);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    return false;
  }
  if (context.mounted) ref.invalidate(savedListsProvider);
  return true;
}
