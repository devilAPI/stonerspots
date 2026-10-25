import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/responsive.dart';
import '../../core/spot_tag_widgets.dart';
import '../../core/tag_catalog.dart';
import '../../l10n/app_localizations.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// Localized inline message for an error of the admin tag endpoints.
String adminTagErrorText(AppLocalizations l, Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'tag_taken':
        return l.adminErrTagTaken;
      case 'invalid_tag':
        return l.adminErrTagKey;
      case 'invalid_name':
      case 'missing_field':
        return l.adminErrTagName;
    }
  }
  return l.errorGeneric;
}

/// Admin tab for the tag catalog: add, rename, re-icon, reorder and delete.
/// Every change also refreshes the app-wide [tagCatalogProvider].
class AdminTagsTab extends ConsumerStatefulWidget {
  const AdminTagsTab({super.key});

  @override
  ConsumerState<AdminTagsTab> createState() => _AdminTagsTabState();
}

class _AdminTagsTabState extends ConsumerState<AdminTagsTab> {
  List<AdminTag>? _tags;
  bool _failed = false;
  bool _busy = false;

  AdminRepository get _repo => ref.read(adminRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final tags = await _repo.tags();
      if (!mounted) return;
      setState(() => _tags = tags);
      ref.read(tagCatalogProvider.notifier).replace([
        for (final t in tags) t.tag,
      ]);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit([AdminTag? tag]) async {
    final saved = await showTagDialog(context, existing: tag?.tag);
    if (saved == true) {
      if (mounted) _snack(AppLocalizations.of(context).adminTagSaved);
      await _load();
    }
  }

  /// Swaps [index] with its neighbour and renumbers both, so equal sort
  /// values cannot keep them in place.
  Future<void> _move(int index, int delta) async {
    final tags = _tags!;
    final other = index + delta;
    if (other < 0 || other >= tags.length) return;
    final errorText = AppLocalizations.of(context).errorGeneric;
    setState(() => _busy = true);
    try {
      await _repo.updateTag(
        tags[index].tag.wire,
        AdminTagDraft(sort: (other + 1) * 10),
      );
      await _repo.updateTag(
        tags[other].tag.wire,
        AdminTagDraft(sort: (index + 1) * 10),
      );
    } catch (_) {
      _snack(errorText);
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(AdminTag tag) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.adminDeleteTagTitle(spotTagLabel(ctx, tag.tag))),
        content: Text(l10n.adminDeleteTagBody(tag.spotCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirm-delete-tag'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.adminDeleteTag),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteTag(tag.tag.wire);
      _snack(l10n.adminTagDeleted);
    } catch (e) {
      // already gone counts as done
      if (!(e is ApiException && e.status == 404)) _snack(l10n.errorGeneric);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = _tags;
    if (_failed && tags == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.errorGeneric),
            TextButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (tags == null) return const Center(child: CircularProgressIndicator());
    final gutter = sideGutter(MediaQuery.sizeOf(context).width);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter + 12, 8, gutter + 12, 88),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('tag-new'),
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(l10n.adminNewTag),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < tags.length; i++)
            Card(
              key: Key('admin-tag-${tags[i].tag.wire}'),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Icon(spotTagIcon(tags[i].tag)),
                title: Text('${tags[i].tag.nameDe} · ${tags[i].tag.nameEn}'),
                subtitle: Text(
                  '${tags[i].tag.wire} · '
                  '${l10n.adminTagSpots(tags[i].spotCount)}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      key: Key('tag-up-${tags[i].tag.wire}'),
                      tooltip: l10n.adminTagMoveUp,
                      onPressed: _busy || i == 0 ? null : () => _move(i, -1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      key: Key('tag-down-${tags[i].tag.wire}'),
                      tooltip: l10n.adminTagMoveDown,
                      onPressed: _busy || i == tags.length - 1
                          ? null
                          : () => _move(i, 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      key: Key('tag-edit-${tags[i].tag.wire}'),
                      tooltip: l10n.adminEditTag,
                      onPressed: _busy ? null : () => _edit(tags[i]),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      key: Key('tag-delete-${tags[i].tag.wire}'),
                      tooltip: l10n.adminDeleteTag,
                      onPressed: _busy ? null : () => _delete(tags[i]),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Create ([existing] null) or edit dialog for a tag; resolves to true when
/// saved.
Future<bool?> showTagDialog(BuildContext context, {SpotTag? existing}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _TagDialog(existing: existing),
    );

class _TagDialog extends ConsumerStatefulWidget {
  const _TagDialog({this.existing});
  final SpotTag? existing;

  @override
  ConsumerState<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends ConsumerState<_TagDialog> {
  late final _key = TextEditingController(text: widget.existing?.wire ?? '');
  late final _de = TextEditingController(text: widget.existing?.nameDe ?? '');
  late final _en = TextEditingController(text: widget.existing?.nameEn ?? '');
  late String _icon = widget.existing?.icon ?? kTagIcons.keys.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _de.dispose();
    _en.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final old = widget.existing;
    final de = _de.text.trim(), en = _en.text.trim();
    if (de.isEmpty || en.isEmpty) {
      setState(() => _error = l10n.adminErrTagName);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    try {
      if (old == null) {
        await repo.createTag(
          AdminTagDraft(
            tag: _key.text.trim(),
            nameDe: de,
            nameEn: en,
            icon: _icon,
          ),
        );
      } else {
        final draft = AdminTagDraft(
          nameDe: de != old.nameDe ? de : null,
          nameEn: en != old.nameEn ? en : null,
          icon: _icon != old.icon ? _icon : null,
        );
        if (!draft.isEmpty) await repo.updateTag(old.wire, draft);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = adminTagErrorText(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.existing == null ? l10n.adminNewTag : l10n.adminEditTag,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('tag-key'),
                controller: _key,
                enabled: widget.existing == null,
                decoration: InputDecoration(
                  labelText: l10n.adminTagKey,
                  helperText: l10n.adminTagKeyHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('tag-name-de'),
                controller: _de,
                decoration: InputDecoration(labelText: l10n.adminTagNameDe),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('tag-name-en'),
                controller: _en,
                decoration: InputDecoration(labelText: l10n.adminTagNameEn),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.adminTagIcon,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in kTagIcons.entries)
                    IconButton(
                      key: Key('tag-icon-${e.key}'),
                      isSelected: _icon == e.key,
                      style: IconButton.styleFrom(
                        backgroundColor: _icon == e.key
                            ? scheme.primaryContainer
                            : null,
                      ),
                      onPressed: () => setState(() => _icon = e.key),
                      icon: Icon(e.value),
                    ),
                ],
              ),
              if (_error != null)
                Padding(
                  key: const Key('tag-error'),
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('tag-save'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
