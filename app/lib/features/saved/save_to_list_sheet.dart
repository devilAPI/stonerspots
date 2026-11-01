import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'list_dialogs.dart';
import 'saved_controller.dart';

/// Lets the user pick the lists a spot is in. Changes apply as they are made.
Future<void> showSaveToListSheet(BuildContext context, int spotId) =>
    showModalBottomSheet<void>(
      context: context,
      // above the shell's floating tab bar
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
      builder: (_) => SaveToListSheet(spotId: spotId),
    );

class SaveToListSheet extends ConsumerStatefulWidget {
  const SaveToListSheet({super.key, required this.spotId});

  final int spotId;

  @override
  ConsumerState<SaveToListSheet> createState() => _SaveToListSheetState();
}

class _SaveToListSheetState extends ConsumerState<SaveToListSheet> {
  // A snackbar would show behind this sheet.
  bool _failed = false;

  Future<void> _set(int listId, bool saved) async {
    setState(() => _failed = false);
    try {
      await ref
          .read(spotSavedProvider(widget.spotId).notifier)
          .setInList(listId, saved: saved);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _newList() async {
    final list = await showListNameDialog(context);
    if (list != null && mounted) await _set(list.id, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lists = ref.watch(savedListsProvider);
    final inLists = ref.watch(spotSavedProvider(widget.spotId)).value ?? {};
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l.savedPickLists, style: theme.textTheme.titleMedium),
            ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l.errorGeneric,
                  key: const Key('saveSheetError'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Flexible(
              child: lists.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(child: Text(l.errorGeneric)),
                      TextButton(
                        onPressed: () => ref.invalidate(savedListsProvider),
                        child: Text(l.retry),
                      ),
                    ],
                  ),
                ),
                data: (all) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final list in all)
                      CheckboxListTile(
                        key: Key('listCheck-${list.id}'),
                        value: inLists.contains(list.id),
                        title: Text(
                          list.title(l),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (v) => _set(list.id, v ?? false),
                      ),
                    ListTile(
                      key: const Key('sheetNewList'),
                      leading: const Icon(Icons.add),
                      title: Text(l.savedNewList),
                      onTap: _newList,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
