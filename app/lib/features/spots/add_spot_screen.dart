import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/back_or_home.dart';
import '../../core/location_service.dart';
import '../../core/responsive.dart';
import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'add_spot_controller.dart';
import 'add_spot_errors.dart';
import 'location_picker.dart';
import 'photo_uploader.dart';
import 'place_search.dart';

class AddSpotScreen extends ConsumerStatefulWidget {
  const AddSpotScreen({super.key});

  @override
  ConsumerState<AddSpotScreen> createState() => _AddSpotScreenState();
}

class _AddSpotScreenState extends ConsumerState<AddSpotScreen> {
  late final Future<LatLng?> _location;
  bool _locationDenied = false;

  @override
  void initState() {
    super.initState();
    _location = ref.read(locationServiceProvider).currentPosition().then((p) {
      if (!mounted) return p;
      if (p == null) {
        setState(() => _locationDenied = true);
      } else if (ref.read(addSpotControllerProvider).point == null) {
        ref.read(addSpotControllerProvider.notifier).setPoint(p);
      }
      return p;
    });
  }

  Future<void> _pickPhotos() async {
    final ctrl = ref.read(addSpotControllerProvider.notifier);
    final room = kMaxPhotos - ref.read(addSpotControllerProvider).photos.length;
    if (room <= 0) return;
    final files = await ref.read(photoPickerProvider).pickPhotos(room);
    ctrl.addPhotos(files);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(addSpotControllerProvider);
    final ctrl = ref.read(addSpotControllerProvider.notifier);

    ref.listen(addSpotControllerProvider, (prev, next) {
      if (next.createdSpotId != null && prev?.createdSpotId == null) {
        // replace the form, so back leads to where the user came from
        final to = '/spot/${next.createdSpotId}';
        context.canPop() ? context.pushReplacement(to) : context.go(to);
      }
    });

    final pickerBox = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<LatLng?>(
        future: _location,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return LocationPicker(
            point: s.point,
            initialCenter: snap.data,
            focus: ref.watch(placeSearchControllerProvider).focus,
            onChanged: (p) {
              ctrl.setPoint(p);
              ref.read(placeSearchControllerProvider.notifier).dismiss();
            },
          );
        },
      ),
    );
    final Widget deniedNote = _locationDenied
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.locationDenied,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        : const SizedBox.shrink();
    final form = <Widget>[
      TextField(
        key: const Key('title'),
        decoration: InputDecoration(labelText: l.title),
        onChanged: ctrl.setTitle,
      ),
      const SizedBox(height: 12),
      Text(l.tagsTitle, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      SpotTagSelector(selected: s.tags, onChanged: ctrl.setTags),
      const SizedBox(height: 12),
      TextField(
        key: const Key('description'),
        decoration: InputDecoration(labelText: l.description),
        maxLines: 4,
        onChanged: ctrl.setDescription,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in s.photos)
            InputChip(
              label: Text(
                p.name.isEmpty ? 'photo' : p.name,
                overflow: TextOverflow.ellipsis,
              ),
              avatar: const Icon(Icons.photo),
              onDeleted: () => ctrl.removePhoto(p),
            ),
          if (s.photos.length < kMaxPhotos)
            ActionChip(
              key: const Key('addPhotos'),
              avatar: const Icon(Icons.add_a_photo),
              label: Text(l.addPhotos),
              onPressed: _pickPhotos,
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (s.duplicate)
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.duplicateSpot),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (s.duplicateSpotId != null)
                      OutlinedButton(
                        onPressed: () =>
                            context.push('/spot/${s.duplicateSpotId}'),
                        child: Text(l.openSpot),
                      ),
                    FilledButton(
                      key: const Key('addAnyway'),
                      onPressed: () => ctrl.submit(force: true),
                      child: Text(l.addAnyway),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (s.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            addSpotErrorText(l, s.error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      FilledButton(
        key: const Key('save'),
        onPressed: s.canSubmit ? () => ctrl.submit() : null,
        child: s.submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(l.save),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: Text(l.addSpotTitle),
      ),
      body: context.twoPane
          ? Row(
              key: const Key('addSpotTwoPane'),
              children: [
                // map fills the left half, form scrolls on the right
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const PlaceSearchField(),
                        const SizedBox(height: 8),
                        Expanded(child: pickerBox),
                        deniedNote,
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 6,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: form,
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const PlaceSearchField(),
                const SizedBox(height: 8),
                SizedBox(height: 240, child: pickerBox),
                deniedNote,
                const SizedBox(height: 16),
                ...form,
              ],
            ),
    );
  }
}
