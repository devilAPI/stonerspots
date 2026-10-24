import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/coordinates.dart';
import '../../l10n/app_localizations.dart';
import '../spots/add_spot_controller.dart' show kCategories;
import '../spots/add_spot_screen.dart' show categoryLabel;
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
  late String _category = kCategories.contains(widget.spot.category)
      ? widget.spot.category
      : 'other';
  late String _status = widget.spot.status == 'hidden' ? 'hidden' : 'active';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _coords.dispose();
    super.dispose();
  }

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
    final patch = AdminSpotPatch(
      title: title != s.title ? title : null,
      description: description != s.description ? description : null,
      category: _category != s.category ? _category : null,
      status: _status != s.status ? _status : null,
      lat: point?.latitude,
      lon: point?.longitude,
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
        DropdownButtonFormField<String>(
          key: const Key('edit-spot-category'),
          initialValue: _category,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.category),
          items: [
            for (final c in kCategories)
              DropdownMenuItem(value: c, child: Text(categoryLabel(l10n, c))),
          ],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        Text(l10n.adminStatus, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const Key('edit-spot-status-active'),
              label: Text(l10n.statusActive),
              selected: _status == 'active',
              onSelected: (_) => setState(() => _status = 'active'),
            ),
            ChoiceChip(
              key: const Key('edit-spot-status-hidden'),
              label: Text(l10n.statusHidden),
              selected: _status == 'hidden',
              onSelected: (_) => setState(() => _status = 'hidden'),
            ),
          ],
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
