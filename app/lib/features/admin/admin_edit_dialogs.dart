import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/coordinates.dart';
import '../../l10n/app_localizations.dart';
import '../../core/models.dart'
    show Author, FeedItem, PhotoRef, SpotTag, UpdateTag;
import '../spots/update_tile.dart' show updateTagLabel;
import '../../core/spot_tag_widgets.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// Localized inline message for an error of `PATCH /admin/users/{id}`.
String adminUserErrorText(AppLocalizations l, Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'invalid_display_name':
        return l.adminErrInvalidDisplayName;
      case 'invalid_email':
        return l.adminErrInvalidEmail;
      case 'email_taken':
        return l.adminErrEmailTaken;
      case 'display_name_taken':
        return l.authErrNameTaken;
      case 'cannot_demote_self':
        return l.adminErrCannotDemoteSelf;
      case 'last_admin':
        return l.adminErrLastAdmin;
    }
  }
  return l.errorGeneric;
}

/// Localized inline message for an error of `PATCH /admin/spots/{id}`.
String adminSpotErrorText(AppLocalizations l, Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'invalid_title':
        return l.adminErrInvalidTitle;
      case 'invalid_description':
        return l.adminErrInvalidDescription;
      case 'invalid_category':
        return l.adminErrInvalidCategory;
      case 'invalid_status':
        return l.adminErrInvalidStatus;
      case 'invalid_location':
        return l.adminErrInvalidLocation;
      case 'invalid_tags':
        return l.tagsErrInvalid;
      case 'invalid_owner':
        return l.adminErrInvalidOwner;
    }
  }
  return l.errorGeneric;
}

/// Formats a point the way the coordinates field is prefilled.
String formatLatLon(double lat, double lon) => '$lat, $lon';

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.fieldKey, required this.text});
  final Key fieldKey;
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

Widget _dialogBody(List<Widget> children) => ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 440),
  child: SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  ),
);

/// Opens the user edit dialog; resolves to the updated user, or null when
/// cancelled or nothing changed.
Future<AdminUser?> showEditUserDialog(
  BuildContext context, {
  required AdminUser user,
  required int? currentUserId,
}) => showDialog<AdminUser>(
  context: context,
  builder: (_) => _EditUserDialog(user: user, currentUserId: currentUserId),
);

class _EditUserDialog extends ConsumerStatefulWidget {
  const _EditUserDialog({required this.user, required this.currentUserId});
  final AdminUser user;
  final int? currentUserId;

  @override
  ConsumerState<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<_EditUserDialog> {
  late final _name = TextEditingController(text: widget.user.displayName);
  late final _email = TextEditingController(text: widget.user.email);
  late bool _isAdmin = widget.user.isAdmin;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final u = widget.user;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final patch = AdminUserPatch(
      displayName: name != u.displayName ? name : null,
      email: email != u.email ? email : null,
      isAdmin: _isAdmin != u.isAdmin ? _isAdmin : null,
    );
    if (patch.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final updated = await ref
          .read(adminRepositoryProvider)
          .updateUser(u.id, patch);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = adminUserErrorText(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final own = widget.currentUserId == widget.user.id;
    return AlertDialog(
      title: Text(l10n.adminEditUser),
      content: _dialogBody([
        TextField(
          key: const Key('edit-user-name'),
          controller: _name,
          decoration: InputDecoration(labelText: l10n.displayName),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('edit-user-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: l10n.email),
        ),
        SwitchListTile(
          key: const Key('edit-user-admin'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.adminIsAdmin),
          subtitle: own ? Text(l10n.adminSelfAdminHint) : null,
          value: _isAdmin,
          onChanged: own ? null : (v) => setState(() => _isAdmin = v),
        ),
        _ErrorText(fieldKey: const Key('edit-user-error'), text: _error),
      ]),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('edit-user-save'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Opens the spot edit dialog; resolves to the updated spot, or null when
/// cancelled or nothing changed.
Future<AdminSpot?> showEditSpotDialog(
  BuildContext context, {
  required AdminSpot spot,
}) => showDialog<AdminSpot>(
  context: context,
  builder: (_) => _EditSpotDialog(spot: spot),
);

class _EditSpotDialog extends ConsumerStatefulWidget {
  const _EditSpotDialog({required this.spot});
  final AdminSpot spot;

  @override
  ConsumerState<_EditSpotDialog> createState() => _EditSpotDialogState();
}

class _EditSpotDialogState extends ConsumerState<_EditSpotDialog> {
  late final _title = TextEditingController(text: widget.spot.title);
  late final _description = TextEditingController(
    text: widget.spot.description,
  );
  late final _coords = TextEditingController(
    text: formatLatLon(widget.spot.lat, widget.spot.lon),
  );
  // The chips show one choice, but "locked" is stored as an active spot
  // with locked set; spots.status itself is only active or hidden.
  late String _status = widget.spot.status == 'hidden'
      ? 'hidden'
      : widget.spot.locked
      ? 'locked'
      : 'active';
  late List<SpotTag> _tags = SpotTag.sorted(widget.spot.tags);
  late Author _owner = widget.spot.author;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _coords.dispose();
    super.dispose();
  }

  static bool _sameTags(List<SpotTag> a, List<SpotTag> b) =>
      SpotTag.encode(a) == SpotTag.encode(b);

  static bool _same(double a, double b) => (a - b).abs() < 1e-9;

  Future<void> _save() async {
    final s = widget.spot;
    final l10n = AppLocalizations.of(context);

    LatLng? point;
    final raw = _coords.text.trim();
    if (raw != formatLatLon(s.lat, s.lon)) {
      point = parseCoordinates(raw);
      if (point == null) {
        setState(() => _error = l10n.adminCoordsInvalid);
        return;
      }
      if (!inSupportedRegion(point)) {
        setState(() => _error = l10n.placeSearchOutside);
        return;
      }
      if (_same(point.latitude, s.lat) && _same(point.longitude, s.lon)) {
        point = null;
      }
    }

    final title = _title.text.trim();
    final description = _description.text.trim();
    final status = _status == 'hidden' ? 'hidden' : 'active';
    // Hiding keeps the lock as it was.
    final locked = _status == 'hidden' ? s.locked : _status == 'locked';
    final patch = AdminSpotPatch(
      title: title != s.title ? title : null,
      description: description != s.description ? description : null,
      status: status != s.status ? status : null,
      lat: point?.latitude,
      lon: point?.longitude,
      tags: _sameTags(_tags, s.tags) ? null : _tags,
      ownerId: _owner.id != s.author.id ? _owner.id : null,
      locked: locked != s.locked ? locked : null,
    );
    if (patch.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(adminRepositoryProvider)
          .updateSpot(s.id, patch);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = adminSpotErrorText(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminEditSpot),
      content: _dialogBody([
        TextField(
          key: const Key('edit-spot-title'),
          controller: _title,
          decoration: InputDecoration(labelText: l10n.title),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('edit-spot-description'),
          controller: _description,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(labelText: l10n.description),
        ),
        const SizedBox(height: 12),
        Text(l10n.adminStatus, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const Key('edit-spot-status-active'),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility, size: 16),
                  const SizedBox(width: 6),
                  Text(l10n.statusActive),
                ],
              ),
              selected: _status == 'active',
              onSelected: (_) => setState(() => _status = 'active'),
            ),
            ChoiceChip(
              key: const Key('edit-spot-status-hidden'),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility_off, size: 16),
                  const SizedBox(width: 6),
                  Text(l10n.statusHidden),
                ],
              ),
              selected: _status == 'hidden',
              onSelected: (_) => setState(() => _status = 'hidden'),
            ),
            ChoiceChip(
              key: const Key('edit-spot-status-locked'),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 16),
                  const SizedBox(width: 6),
                  Text(l10n.statusLocked),
                ],
              ),
              selected: _status == 'locked',
              onSelected: (_) => setState(() => _status = 'locked'),
            ),
          ],
        ),
        ListTile(
          key: const Key('edit-spot-owner'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(l10n.adminOwner),
          subtitle: Text(_owner.displayName),
          trailing: TextButton(
            key: const Key('edit-spot-change-owner'),
            onPressed: () async {
              final picked = await showUserPickerDialog(context);
              if (picked != null) {
                setState(
                  () => _owner = Author(
                    id: picked.id,
                    displayName: picked.displayName,
                  ),
                );
              }
            },
            child: Text(l10n.adminChangeOwner),
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.tagsTitle, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SpotTagSelector(
          keyPrefix: 'edit-spot-tag-',
          selected: _tags,
          onChanged: (next) => setState(() => _tags = next),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('edit-spot-coords'),
          controller: _coords,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(labelText: l10n.adminCoordinates),
        ),
        _ErrorText(fieldKey: const Key('edit-spot-error'), text: _error),
      ]),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('edit-spot-save'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Searches users by name or email and resolves to the one picked (null =
/// cancelled).
Future<AdminUser?> showUserPickerDialog(BuildContext context) =>
    showDialog<AdminUser>(
      context: context,
      builder: (_) => const _UserPicker(),
    );

class _UserPicker extends ConsumerStatefulWidget {
  const _UserPicker();

  @override
  ConsumerState<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends ConsumerState<_UserPicker> {
  List<AdminUser>? _users;
  bool _failed = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final gen = ++_gen;
    setState(() => _failed = false);
    try {
      final page = await ref
          .read(adminRepositoryProvider)
          .users(q: q.trim().isEmpty ? null : q.trim());
      if (mounted && gen == _gen) setState(() => _users = page.items);
    } catch (_) {
      if (mounted && gen == _gen) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final users = _users;
    return AlertDialog(
      title: Text(l10n.adminPickUser),
      content: SizedBox(
        width: 400,
        height: 360,
        child: Column(
          children: [
            TextField(
              key: const Key('owner-search'),
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.adminSearchUsers,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _failed
                  ? Center(child: Text(l10n.errorGeneric))
                  : users == null
                  ? const Center(child: CircularProgressIndicator())
                  : users.isEmpty
                  ? Center(child: Text(l10n.noResults))
                  : ListView(
                      children: [
                        for (final u in users)
                          ListTile(
                            key: Key('owner-pick-${u.id}'),
                            title: Text(u.displayName),
                            subtitle: Text(u.email),
                            onTap: () => Navigator.pop(context, u),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

/// Localized inline message for an error of `PATCH /admin/updates/{id}`.
String adminUpdateErrorText(AppLocalizations l, Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'invalid_body':
      case 'last_photo':
        return l.updateErrorInvalidBody;
      case 'invalid_tag':
        return l.updateErrorInvalidTag;
    }
  }
  return l.errorGeneric;
}

/// Admin edit of anyone's update (text, status tag, and its photos: rotate
/// by 90° or remove); resolves to true when anything was saved.
Future<bool?> showAdminUpdateDialog(BuildContext context, FeedItem item) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _AdminUpdateDialog(item: item),
    );

class _AdminUpdateDialog extends ConsumerStatefulWidget {
  const _AdminUpdateDialog({required this.item});
  final FeedItem item;

  @override
  ConsumerState<_AdminUpdateDialog> createState() => _AdminUpdateDialogState();
}

class _AdminUpdateDialogState extends ConsumerState<_AdminUpdateDialog> {
  late final _body = TextEditingController(text: widget.item.body);
  late UpdateTag _tag = widget.item.tag;
  // What the server has; moves forward as each step of a save succeeds, so
  // a retry after a partial failure never applies a step twice.
  late String _savedBody = widget.item.body;
  late UpdateTag _savedTag = widget.item.tag;
  late final List<PhotoRef> _photos = [...widget.item.photos];
  // Pending clockwise quarter turns (1-3) and removals, by photo id.
  final Map<int, int> _turns = {};
  final Set<int> _removed = {};
  bool _saved = false;
  bool _busy = false;
  String? _error;

  void _turn(int id, int quarters) => setState(() {
    final t = ((_turns[id] ?? 0) + quarters) % 4;
    if (t == 0) {
      _turns.remove(id);
    } else {
      _turns[id] = t;
    }
  });

  void _toggleRemoved(int id) => setState(() {
    if (!_removed.remove(id)) _removed.add(id);
  });

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final body = _body.text.trim();
    final patch = AdminUpdatePatch(
      body: body != _savedBody ? body : null,
      tag: _tag != _savedTag ? _tag : null,
    );
    if (patch.isEmpty && _turns.isEmpty && _removed.isEmpty) {
      Navigator.pop(context, _saved);
      return;
    }
    // An update needs text or photos.
    if (body.isEmpty && _removed.length == _photos.length) {
      setState(() => _error = l10n.updateErrorInvalidBody);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    try {
      if (!patch.isEmpty) {
        await repo.updateUpdate(widget.item.id, patch);
        _saved = true;
        _savedBody = body;
        _savedTag = _tag;
      }
      for (final id in [..._turns.keys]) {
        if (_removed.contains(id)) continue;
        await repo.rotatePhoto(id, _turns[id]! * 90);
        _saved = true;
        _turns.remove(id);
      }
      for (final id in [..._removed]) {
        try {
          await repo.deletePhoto(id);
        } on ApiException catch (e) {
          if (e.code != 'not_found') rethrow;
        }
        _saved = true;
        _removed.remove(id);
        _turns.remove(id);
        _photos.removeWhere((p) => p.id == id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = adminUpdateErrorText(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminEditUpdate),
      content: _dialogBody([
        Text(
          widget.item.author.displayName,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('admin-update-body'),
          controller: _body,
          minLines: 3,
          maxLines: 8,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.updateTagLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in UpdateTag.values)
              ChoiceChip(
                key: Key('admin-update-tag-${t.wire}'),
                label: Text(updateTagLabel(l10n, t)),
                selected: _tag == t,
                onSelected: (_) => setState(() => _tag = t),
              ),
          ],
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.adminPhotos, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final p in _photos) _photoTile(l10n, p)],
          ),
        ],
        _ErrorText(fieldKey: const Key('admin-update-error'), text: _error),
      ]),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _saved),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('admin-update-save'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }

  Widget _photoTile(AppLocalizations l10n, PhotoRef p) {
    final removed = _removed.contains(p.id);
    return Column(
      key: Key('admin-photo-${p.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: removed ? 0.3 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 96,
              height: 96,
              child: RotatedBox(
                quarterTurns: _turns[p.id] ?? 0,
                child: CachedNetworkImage(
                  imageUrl: p.thumbUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('admin-photo-${p.id}-left'),
              tooltip: l10n.adminPhotoRotateLeft,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.rotate_left, size: 20),
              onPressed: _busy || removed ? null : () => _turn(p.id, 3),
            ),
            IconButton(
              key: Key('admin-photo-${p.id}-right'),
              tooltip: l10n.adminPhotoRotateRight,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.rotate_right, size: 20),
              onPressed: _busy || removed ? null : () => _turn(p.id, 1),
            ),
            IconButton(
              key: Key('admin-photo-${p.id}-remove'),
              tooltip: removed ? l10n.adminPhotoRestore : l10n.adminPhotoRemove,
              visualDensity: VisualDensity.compact,
              icon: Icon(removed ? Icons.undo : Icons.delete_outline, size: 20),
              onPressed: _busy ? null : () => _toggleRemoved(p.id),
            ),
          ],
        ),
      ],
    );
  }
}
