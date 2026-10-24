import 'dart:async';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/spots/photo_uploader.dart';
import 'package:app/features/spots/updates_repository.dart';
import 'package:image_picker/image_picker.dart';

XFile fakeFile(String name) =>
    XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name, path: name);

FeedItem feedItem({
  int id = 7,
  String body = 'hello',
  UpdateTag tag = UpdateTag.note,
  int authorId = 1,
  List<PhotoRef> photos = const [],
  DateTime? editedAt,
}) => FeedItem(
  id: id,
  body: body,
  photos: photos,
  createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  author: Author(id: authorId, displayName: 'Ann'),
  spot: const Spot(id: 5, title: 'Lake bench', lat: 1, lon: 2),
  tag: tag,
  editedAt: editedAt,
);

class FakeUpdates implements UpdatesRepository {
  FakeUpdates({List<FeedItem>? items}) : items = items ?? [];

  final List<FeedItem> items;
  final posted = <({String body, List<int> photoIds, UpdateTag tag})>[];
  final edits = <({int id, String? body, UpdateTag? tag})>[];
  final deleted = <int>[];
  Object? postError;
  Object? editError;
  int listCalls = 0;

  @override
  Future<List<FeedItem>> listForSpot(int spotId) async {
    listCalls++;
    return List.of(items);
  }

  @override
  Future<void> post(
    int spotId, {
    required String body,
    List<int> photoIds = const [],
    UpdateTag tag = UpdateTag.note,
  }) async {
    if (postError != null) throw postError!;
    posted.add((body: body, photoIds: photoIds, tag: tag));
  }

  @override
  Future<void> edit(int id, {String? body, UpdateTag? tag}) async {
    if (editError != null) throw editError!;
    edits.add((id: id, body: body, tag: tag));
  }

  @override
  Future<void> delete(int id) async {
    deleted.add(id);
  }
}

class FakePicker implements PhotoPicker {
  FakePicker(this.files);

  final List<XFile> files;
  final requestedMax = <int>[];

  @override
  Future<List<XFile>> pickPhotos(int maxCount) async {
    requestedMax.add(maxCount);
    return files;
  }
}

class FakeUploader implements PhotoUploader {
  final uploads = <String>[];

  /// File names that fail once.
  final failOnce = <String>{};

  /// When set, uploads wait for it after reporting 50% progress.
  Completer<void>? gate;

  @override
  Future<UploadedPhoto> upload(
    XFile file, {
    void Function(double)? onProgress,
  }) async {
    uploads.add(file.name);
    onProgress?.call(0.5);
    if (gate != null) await gate!.future;
    if (failOnce.remove(file.name)) {
      throw ApiException(500, 'internal', 'boom');
    }
    onProgress?.call(1);
    return UploadedPhoto(id: 100 + uploads.length, url: 'u', thumbUrl: 't');
  }
}
