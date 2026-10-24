import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import 'photo_uploader.dart';
import 'spot_api.dart';

const int kMaxPhotos = 4;
const List<String> kCategories = [
  'bench',
  'river',
  'lake',
  'viewpoint',
  'forest',
  'park',
  'other',
];

class AddSpotState {
  const AddSpotState({
    this.title = '',
    this.description = '',
    this.category,
    this.point,
    this.photos = const [],
    this.submitting = false,
    this.duplicate = false,
    this.duplicateSpotId,
    this.createdSpotId,
    this.error,
  });

  final String title;
  final String description;
  final String? category;
  final LatLng? point;
  final List<XFile> photos;
  final bool submitting;

  /// A 409 `possible_duplicate` came back; offer "open it" / "add anyway".
  final bool duplicate;
  final int? duplicateSpotId;

  /// Set once the spot exists (success).
  final int? createdSpotId;
  final Object? error;

  bool get canSubmit =>
      !submitting &&
      title.trim().isNotEmpty &&
      category != null &&
      point != null;

  AddSpotState copyWith({
    String? title,
    String? description,
    String? category,
    LatLng? point,
    List<XFile>? photos,
    bool? submitting,
    bool? duplicate,
    int? duplicateSpotId,
    int? createdSpotId,
    Object? error,
    bool clearError = false,
    bool clearDuplicate = false,
  }) => AddSpotState(
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    point: point ?? this.point,
    photos: photos ?? this.photos,
    submitting: submitting ?? this.submitting,
    duplicate: clearDuplicate ? false : (duplicate ?? this.duplicate),
    duplicateSpotId: clearDuplicate
        ? null
        : (duplicateSpotId ?? this.duplicateSpotId),
    createdSpotId: createdSpotId ?? this.createdSpotId,
    error: clearError ? null : (error ?? this.error),
  );
}

final addSpotControllerProvider =
    NotifierProvider.autoDispose<AddSpotController, AddSpotState>(
      AddSpotController.new,
    );

class AddSpotController extends Notifier<AddSpotState> {
  // Photos already uploaded, keyed by the picked file, so a retry (after a
  // failure or "add anyway") does not upload them again.
  final Map<XFile, int> _uploaded = {};

  @override
  AddSpotState build() => const AddSpotState();

  void setTitle(String v) => state = state.copyWith(title: v);
  void setDescription(String v) => state = state.copyWith(description: v);
  void setCategory(String v) => state = state.copyWith(category: v);

  void setPoint(LatLng p) =>
      state = state.copyWith(point: p, clearDuplicate: true);

  /// Adds photos up to [kMaxPhotos]; extras are dropped. Returns how many
  /// were added.
  int addPhotos(List<XFile> files) {
    final room = kMaxPhotos - state.photos.length;
    final added = files.take(room < 0 ? 0 : room).toList();
    if (added.isNotEmpty) {
      state = state.copyWith(photos: [...state.photos, ...added]);
    }
    return added.length;
  }

  void removePhoto(XFile file) {
    _uploaded.remove(file);
    state = state.copyWith(
      photos: state.photos.where((p) => p != file).toList(),
    );
  }

  /// Creates the spot. On 409 `possible_duplicate` the state exposes the
  /// existing spot; call again with [force] to add anyway. All form state is
  /// kept on any failure.
  Future<void> submit({bool force = false}) async {
    if (!state.canSubmit) return;
    state = state.copyWith(
      submitting: true,
      clearError: true,
      clearDuplicate: true,
    );
    try {
      final photoIds = <int>[];
      for (final f in state.photos) {
        _uploaded[f] ??= (await ref.read(photoUploaderProvider).upload(f)).id;
        photoIds.add(_uploaded[f]!);
      }
      final spot = await ref
          .read(spotApiProvider)
          .createSpot(
            SpotDraft(
              title: state.title.trim(),
              description: state.description.trim(),
              category: state.category!,
              lat: state.point!.latitude,
              lon: state.point!.longitude,
              photoIds: photoIds,
            ),
            force: force,
          );
      state = state.copyWith(submitting: false, createdSpotId: spot.id);
    } on ApiException catch (e) {
      if (e.status == 409 && e.code == 'possible_duplicate') {
        state = state.copyWith(
          submitting: false,
          duplicate: true,
          duplicateSpotId: parseDuplicateId(e),
        );
      } else {
        state = state.copyWith(submitting: false, error: e);
      }
    } catch (e) {
      state = state.copyWith(submitting: false, error: e);
    }
  }
}

/// The backend sends the existing spot's id as top-level `existing_id`.
int? parseDuplicateId(ApiException e) =>
    (e.details?['existing_id'] as num?)?.toInt();
