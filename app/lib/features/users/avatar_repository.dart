import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;
import '../spots/image_compressor.dart';

/// The multipart field `PUT /me/avatar` reads the photo from.
const kAvatarField = 'photo';

/// Profile pictures: the logged-in user's own, or with [userId] someone
/// else's (admins only).
abstract class AvatarRepository {
  /// Compresses [file] like update photos and uploads it as the new
  /// picture; resolves to its URL. [onProgress] gets 0.0 to 1.0.
  Future<String> upload(
    XFile file, {
    int? userId,
    void Function(double)? onProgress,
  });

  /// Removes the picture.
  Future<void> remove({int? userId});
}

String _avatarPath(int? userId) =>
    userId == null ? '/me/avatar' : '/admin/users/$userId/avatar';

class ApiAvatarRepository implements AvatarRepository {
  ApiAvatarRepository(this._api);

  final ApiClient _api;

  @override
  Future<String> upload(
    XFile file, {
    int? userId,
    void Function(double)? onProgress,
  }) async {
    final photo = await prepareForUpload(await file.readAsBytes());
    final form = FormData.fromMap({
      kAvatarField: MultipartFile.fromBytes(
        photo.bytes,
        filename: photo.compressed || file.name.isEmpty
            ? 'avatar.jpg'
            : file.name,
      ),
    });
    final json = await _api.put<Map<String, dynamic>>(
      _avatarPath(userId),
      data: form,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
      // a few MB on a slow mobile uplink; see ApiClient.post
      receiveTimeout: const Duration(minutes: 5),
    );
    return json['avatar_url'] as String;
  }

  @override
  Future<void> remove({int? userId}) async {
    await _api.delete<dynamic>(_avatarPath(userId));
  }
}

final avatarRepositoryProvider = Provider<AvatarRepository>(
  (ref) => ApiAvatarRepository(ref.watch(apiClientProvider)),
);

/// Picks one photo from the gallery; null when cancelled.
typedef AvatarPicker = Future<XFile?> Function();

final avatarPickerProvider = Provider<AvatarPicker>(
  (ref) =>
      () => ImagePicker().pickImage(source: ImageSource.gallery),
);
