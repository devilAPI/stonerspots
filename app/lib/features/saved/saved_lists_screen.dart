import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_or_home.dart';
import '../../core/glass.dart';
import '../../core/net_photo.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'list_dialogs.dart';
import 'saved_controller.dart';
import 'saved_repository.dart';

/// Padding of a list under the glass bar, at a readable width.
EdgeInsets savedPagePadding(BuildContext context, double width) {
  final insets = MediaQuery.paddingOf(context);
  final gutter = sideGutter(width);
  return EdgeInsets.fromLTRB(
    insets.left + gutter,
    GlassAppBar.contentTop(context),
    insets.right + gutter,
    insets.bottom + 16,
  );
}

class SavedListsScreen extends ConsumerWidget {
  const SavedListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final lists = ref.watch(savedListsProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const BackOrHomeButton(),
        title: Text(l.saved),
        actions: [
          IconButton(
            key: const Key('newList'),
            tooltip: l.savedNewList,
            icon: const Icon(Icons.add),
            onPressed: () => showListNameDialog(context),
          ),
        ],
      ),
      body: lists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.errorGeneric),
              TextButton(
                onPressed: () => ref.invalidate(savedListsProvider),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
        data: (all) => LayoutBuilder(
          builder: (context, c) {
            // Favourites always exist, so "nothing saved" is all of it empty.
            final empty = all.every((list) => list.spotCount == 0);
            return RefreshIndicator(
              edgeOffset: GlassAppBar.contentTop(context),
              onRefresh: () => ref.refresh(savedListsProvider.future),
              child: SideInsetsHandled(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: savedPagePadding(context, c.maxWidth),
                  children: [
                    for (final list in all) _ListRow(list: list),
                    if (empty)
                      Padding(
                        key: const Key('savedEmpty'),
                        padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.bookmark_border,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(l.savedEmpty, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ListRow extends ConsumerWidget {
  const _ListRow({required this.list});

  final SpotList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return ListTile(
      key: Key('savedList-${list.id}'),
      leading: _Cover(url: list.coverUrl, isDefault: list.isDefault),
      title: Text(list.title(l), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l.savedSpotCount(list.spotCount)),
      trailing: list.isDefault
          ? null
          : ListActionsMenu(key: Key('listMenu-${list.id}'), list: list),
      onTap: () => context.push('/saved/${list.id}'),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.isDefault});

  final String? url;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 56,
        child: url == null
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  isDefault ? Icons.bookmark : Icons.bookmark_border,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : NetPhoto(url, decodeWidth: 56),
      ),
    );
  }
}

/// Rename and delete of a user's own list; [onDeleted] runs once it is gone.
class ListActionsMenu extends ConsumerWidget {
  const ListActionsMenu({super.key, required this.list, this.onDeleted});

  final SpotList list;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      onSelected: (action) async {
        if (action == 'rename') {
          await showListNameDialog(context, list: list);
        } else if (await confirmDeleteList(context, ref, list)) {
          onDeleted?.call();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const Key('renameList'),
          value: 'rename',
          child: Text(l.savedRenameList),
        ),
        PopupMenuItem(
          key: const Key('deleteList'),
          value: 'delete',
          child: Text(l.savedDelete),
        ),
      ],
    );
  }
}
