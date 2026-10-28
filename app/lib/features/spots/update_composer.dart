import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/net_photo.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'photo_uploader.dart';
import 'update_tile.dart' show updateTagLabel;
import 'updates_repository.dart';

const int kMaxUpdatePhotos = 4;

String updateErrorText(AppLocalizations l, Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_photo':
        return l.updateErrorInvalidPhoto;
      case 'invalid_body':
        return l.updateErrorInvalidBody;
      case 'invalid_tag':
        return l.updateErrorInvalidTag;
    }
  }
  return l.errorGeneric;
}

/// Opens the composer for a new update on [spotId], or, with [editing], for
/// changing the text and tag of an existing one. A bottom sheet on phones, a
/// dialog on wide screens. Resolves to true when something was saved.
Future<bool?> showUpdateComposer(
  BuildContext context, {
  required int spotId,
  FeedItem? editing,
}) {
  final composer = UpdateComposer(spotId: spotId, editing: editing);
  if (context.useNavRail) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: composer,
        ),
      ),
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => composer,
  );
}

class _Picked {
  _Picked(this.file);

  final XFile file;
  int? uploadedId;
  double progress = 0;
  bool uploading = false;
}

class UpdateComposer extends ConsumerStatefulWidget {
  const UpdateComposer({super.key, required this.spotId, this.editing});

  final int spotId;
  final FeedItem? editing;

  @override
  ConsumerState<UpdateComposer> createState() => _UpdateComposerState();
}

class _UpdateComposerState extends ConsumerState<UpdateComposer> {
  late final TextEditingController _body = TextEditingController(
    text: widget.editing?.body ?? '',
  );
  late UpdateTag _tag = widget.editing?.tag ?? UpdateTag.note;
  final List<_Picked> _photos = [];
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_busy) return false;
    final text = _body.text.trim();
    final e = widget.editing;
    if (e == null) return text.isNotEmpty || _photos.isNotEmpty;
    final changed = text != e.body || _tag != e.tag;
    return changed && (text.isNotEmpty || e.photos.isNotEmpty);
  }

  Future<void> _pick() async {
    final room = kMaxUpdatePhotos - _photos.length;
    if (room <= 0) return;
    final files = await ref.read(photoPickerProvider).pickPhotos(room);
    if (!mounted) return;
    setState(() {
      for (final f in files.take(room)) {
        _photos.add(_Picked(f));
      }
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(spotUpdatesRepositoryProvider);
      final e = widget.editing;
      if (e != null) {
        final text = _body.text.trim();
        await repo.edit(
          e.id,
          body: text != e.body ? text : null,
          tag: _tag != e.tag ? _tag : null,
        );
      } else {
        final uploader = ref.read(photoUploaderProvider);
        for (final p in List.of(_photos)) {
          if (p.uploadedId != null) continue; // cached from an earlier try
          if (mounted) setState(() => p.uploading = true);
          try {
            final up = await uploader.upload(
              p.file,
              onProgress: (v) {
                if (mounted) setState(() => p.progress = v);
              },
            );
            p.uploadedId = up.id;
          } finally {
            if (mounted) setState(() => p.uploading = false);
          }
        }
        await repo.post(
          widget.spotId,
          body: _body.text.trim(),
          photoIds: [for (final p in _photos) p.uploadedId!],
          tag: _tag,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = updateErrorText(l, err);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = widget.editing;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              _isEdit ? l.updateEditTitle : l.postUpdate,
              style: theme.textTheme.titleLarge,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('updateBody'),
                    controller: _body,
                    enabled: !_busy,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: l.description,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(l.updateTagLabel, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final t in UpdateTag.values)
                        ChoiceChip(
                          key: Key('updateTag_${t.name}'),
                          label: Text(updateTagLabel(l, t)),
                          selected: _tag == t,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _tag = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (e != null) ...[
                    if (e.photos.isNotEmpty) _existingPhotos(e),
                    const SizedBox(height: 4),
                    Text(
                      l.updatePhotosReadOnly,
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else ...[
                    Row(
                      children: [
                        OutlinedButton.icon(
                          key: const Key('updateAddPhotos'),
                          icon: const Icon(Icons.add_a_photo),
                          label: Text(l.addPhotos),
                          onPressed: _busy || _photos.length >= kMaxUpdatePhotos
                              ? null
                              : _pick,
                        ),
                        const SizedBox(width: 12),
                        Text('${_photos.length}/$kMaxUpdatePhotos'),
                      ],
                    ),
                    if (_photos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _photos.length; i++)
                            _newPhoto(l, i),
                        ],
                      ),
                    ],
                  ],
                  if (_error != null)
                    Padding(
                      key: const Key('updateError'),
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(l.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('updateSubmit'),
                  onPressed: _canSubmit ? _submit : null,
                  child: Text(_isEdit ? l.save : l.updatePost),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _existingPhotos(FeedItem e) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < e.photos.length; i++)
        ClipRRect(
          key: Key('updatePhoto_$i'),
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 72,
            height: 72,
            child: NetPhoto(e.photos[i].thumbUrl),
          ),
        ),
    ],
  );

  Widget _newPhoto(AppLocalizations l, int i) {
    final p = _photos[i];
    return SizedBox(
      key: Key('updatePhoto_$i'),
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _FileThumb(file: p.file),
          ),
          if (p.uploading)
            Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                key: Key('updateProgress_$i'),
                value: p.progress,
              ),
            ),
          if (p.uploadedId != null && !p.uploading)
            const Positioned(
              left: 2,
              bottom: 2,
              child: Icon(Icons.check_circle, size: 16, color: Colors.green),
            ),
          Positioned(
            top: -4,
            right: -4,
            child: IconButton(
              key: Key('updateRemovePhoto_$i'),
              tooltip: l.updateRemovePhoto,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close),
              onPressed: _busy
                  ? null
                  : () => setState(() => _photos.removeAt(i)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileThumb extends StatefulWidget {
  const _FileThumb({required this.file});

  final XFile file;

  @override
  State<_FileThumb> createState() => _FileThumbState();
}

class _FileThumbState extends State<_FileThumb> {
  late final Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (_, snap) => snap.hasData
        ? Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            cacheWidth: 144,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.image_outlined)),
          )
        : const ColoredBox(color: Colors.black12),
  );
}
