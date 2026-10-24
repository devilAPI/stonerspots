import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import 'add_spot_screen.dart' show categoryLabel;
import 'photo_uploader.dart';
import 'spot_api.dart';
import 'updates_repository.dart';

final spotDetailProvider = FutureProvider.autoDispose.family<Spot, int>(
    (ref, id) => ref.watch(spotApiProvider).getSpot(id));

final spotUpdatesProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, int>((ref, id) =>
        ref.watch(spotUpdatesRepositoryProvider).listForSpot(id));

class SpotDetailScreen extends ConsumerStatefulWidget {
  const SpotDetailScreen({super.key, required this.spotId});

  final int spotId;

  @override
  ConsumerState<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends ConsumerState<SpotDetailScreen> {
  bool _liked = false;
  int? _likeCount;

  /// Runs [action] if logged in, otherwise sends the user to the login page.
  void _gated(VoidCallback action) {
    if (ref.read(authControllerProvider).value == null) {
      final here = GoRouterState.of(context).uri.toString();
      context.push('/login?from=${Uri.encodeComponent(here)}');
      return;
    }
    action();
  }

  Future<void> _toggleLike() async {
    final errorText = AppLocalizations.of(context).errorGeneric;
    final want = !_liked;
    try {
      final r = await ref
          .read(spotApiProvider)
          .setLike(widget.spotId, liked: want);
      if (mounted) {
        setState(() {
          _liked = r.liked;
          _likeCount = r.likeCount;
        });
      }
    } catch (_) {
      _snack(errorText);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _report(String type, int id) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.report),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: l.reportReason),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.report)),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      await ref.read(spotApiProvider).report(type, id, reason);
    } catch (_) {
      _snack(l.errorGeneric);
    }
  }

  Future<void> _postUpdate() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final picked = <dynamic>[];
    final posted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l.postUpdate),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('updateBody'),
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(labelText: l.description),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_a_photo),
                  label: Text('${l.addPhotos} (${picked.length}/4)'),
                  onPressed: picked.length >= 4
                      ? null
                      : () async {
                          final files = await ref
                              .read(photoPickerProvider)
                              .pickPhotos(4 - picked.length);
                          setLocal(() =>
                              picked.addAll(files.take(4 - picked.length)));
                        },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
            FilledButton(
              onPressed: () async {
                final body = controller.text.trim();
                if (body.isEmpty && picked.isEmpty) return;
                try {
                  final ids = <int>[];
                  for (final f in picked) {
                    ids.add((await ref.read(photoUploaderProvider).upload(f)).id);
                  }
                  await ref
                      .read(spotUpdatesRepositoryProvider)
                      .post(widget.spotId, body: body, photoIds: ids);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (_) {
                  _snack(l.errorGeneric);
                }
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (posted == true) ref.invalidate(spotUpdatesProvider(widget.spotId));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.watch(authControllerProvider); // keep the session loaded for gating
    final spotAsync = ref.watch(spotDetailProvider(widget.spotId));
    final updates = ref.watch(spotUpdatesProvider(widget.spotId));

    return Scaffold(
      appBar: AppBar(
        title: Text(spotAsync.value?.title ?? l.spotDetailTitle),
        actions: [
          PopupMenuButton<String>(
            key: const Key('menu'),
            onSelected: (v) {
              if (v == 'report') {
                _gated(() => _report('spot', widget.spotId));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'report', child: Text(l.report)),
            ],
          ),
        ],
      ),
      body: spotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(l.errorGeneric),
            TextButton(
                onPressed: () =>
                    ref.invalidate(spotDetailProvider(widget.spotId)),
                child: Text(l.retry)),
          ]),
        ),
        data: (spot) {
          final items = updates.value ?? const <FeedItem>[];
          final urls = <String>[
            if (spot.coverUrl != null) spot.coverUrl!,
            for (final i in items)
              for (final p in i.photos)
                if (p.url != spot.coverUrl) p.url,
          ];
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (urls.isNotEmpty)
                SizedBox(
                  height: 220,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(8),
                    itemCount: urls.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                          imageUrl: urls[i], fit: BoxFit.cover),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spot.title,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(categoryLabel(l, spot.category)),
                    if (spot.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(spot.description),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      FilledButton.tonalIcon(
                        key: const Key('like'),
                        onPressed: () => _gated(_toggleLike),
                        icon: Icon(_liked
                            ? Icons.favorite
                            : Icons.favorite_border),
                        label: Text(l.like),
                      ),
                      const SizedBox(width: 12),
                      Text(l.likesCount(_likeCount ?? spot.likeCount)),
                    ]),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('postUpdate'),
                      onPressed: () => _gated(_postUpdate),
                      icon: const Icon(Icons.edit),
                      label: Text(l.postUpdate),
                    ),
                  ],
                ),
              ),
              const Divider(),
              updates.when(
                loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator())),
                error: (_, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.errorGeneric),
                ),
                data: (list) => Column(
                  children: [
                    for (final u in list)
                      ListTile(
                        title: Text(u.body),
                        subtitle: Text(
                            '${u.author.displayName} · ${u.createdAt.toLocal().toString().substring(0, 16)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.flag_outlined),
                          tooltip: l.report,
                          onPressed: () =>
                              _gated(() => _report('update', u.id)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
