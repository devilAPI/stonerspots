import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'admin_controller.dart';

// The building blocks of the admin lists: paged list, row card, search
// box, status chip, selection.

String formatAdminDateTime(BuildContext context, DateTime d) {
  final loc = MaterialLocalizations.of(context);
  final local = d.toLocal();
  return '${loc.formatShortDate(local)} '
      '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

/// Read-only row of five stars, [rating] of them filled.
class AdminStarRow extends StatelessWidget {
  const AdminStarRow(this.rating, {super.key});
  final int rating;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: AppLocalizations.of(context).adminRatingStars(rating),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= rating ? Icons.star : Icons.star_border,
              size: 18,
              color: color,
            ),
        ],
      ),
    );
  }
}

/// Scrollable, centred list with loading / empty / error states, pull to
/// refresh and "load more" near the end.
class AdminPagedList<T> extends StatefulWidget {
  const AdminPagedList({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRetry,
    required this.itemBuilder,
  });

  final AdminListState<T> state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetry;
  final Widget Function(BuildContext, T) itemBuilder;

  @override
  State<AdminPagedList<T>> createState() => _AdminPagedListState<T>();
}

class _AdminPagedListState<T> extends State<AdminPagedList<T>> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 400) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    final gutter = sideGutter(MediaQuery.sizeOf(context).width);
    // A short first page may not fill the viewport, so nothing would scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMore();
    });

    if (state.error != null && state.items.isEmpty && !state.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.errorGeneric),
            TextButton(onPressed: widget.onRetry, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (!state.loadedOnce || (state.loading && state.items.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    final Widget list;
    if (state.items.isEmpty) {
      list = ListView(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(child: Text(l10n.noResults)),
        ],
      );
    } else {
      list = ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (ctx, i) => i >= state.items.length
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : widget.itemBuilder(ctx, state.items[i]),
      );
    }
    return RefreshIndicator(onRefresh: widget.onRefresh, child: list);
  }
}

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hidden = status == 'hidden';
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(hidden ? l10n.statusHidden : l10n.statusActive),
      backgroundColor: hidden ? scheme.errorContainer : null,
    );
  }
}

class AdminTile extends StatelessWidget {
  const AdminTile({
    super.key,
    required this.body,
    this.actions = const [],
    this.selected,
    this.onSelected,
    this.selectKey,
  });
  final List<Widget> body;
  final List<Widget> actions;

  /// With a value the tile has a checkbox; [onSelected] null disables it.
  final bool? selected;
  final ValueChanged<bool>? onSelected;
  final Key? selectKey;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...body,
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 4, children: actions),
          ),
      ],
    );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: selected == true
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(selected == null ? 12 : 0, 12, 12, 12),
        child: selected == null
            ? content
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    key: selectKey,
                    value: selected,
                    onChanged: onSelected == null
                        ? null
                        : (v) => onSelected!(v ?? false),
                  ),
                  Expanded(child: content),
                ],
              ),
      ),
    );
  }
}

/// The ids of the selected rows of a list. Rows that left the list (deleted,
/// or another search) drop out of it.
mixin AdminSelection<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  final selected = <int>{};
  bool busy = false;

  void toggle(int id, bool on) =>
      setState(() => on ? selected.add(id) : selected.remove(id));

  /// [selected] limited to the ids still in [loaded].
  List<int> current(Iterable<int> loaded) {
    final ids = loaded.toSet();
    selected.retainWhere(ids.contains);
    return selected.toList();
  }

  /// Runs [action]; it calls the callback it gets when its request goes
  /// out (after its questions), which turns the bar busy.
  Future<void> run(
    Future<bool> Function(List<int> ids, VoidCallback onSend) action,
    List<int> ids,
  ) async {
    final ran = await action(ids, () => setState(() => busy = true));
    if (!mounted) return;
    setState(() {
      busy = false;
      if (ran) selected.clear();
    });
  }
}

/// Search box that only queries on submit (Enter / search key).
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.fieldKey,
    required this.hint,
    required this.initial,
    required this.onSubmitted,
  });

  final Key fieldKey;
  final String hint;
  final String initial;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final gutter = sideGutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + gutter, 8, 12 + gutter, 4),
      child: TextFormField(
        key: fieldKey,
        initialValue: initial,
        textInputAction: TextInputAction.search,
        onFieldSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
