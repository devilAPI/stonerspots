import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;

class UploadedPhoto {
  const UploadedPhoto({
    required this.id,
    required this.url,
    required this.thumbUrl,
  });

  final int id;
  final String url;
  final String thumbUrl;
}

abstract class PhotoUploader {
  /// [onProgress] receives values from 0.0 to 1.0.
  Future<UploadedPhoto> upload(XFile file, {void Function(double)? onProgress});
}

class ApiPhotoUploader implements PhotoUploader {
  ApiPhotoUploader(this._api);

  final ApiClient _api;

  @override
  Future<UploadedPhoto> upload(
    XFile file, {
    void Function(double)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: file.name.isEmpty ? 'photo.jpg' : file.name,
      ),
    });
    final json = await _api.post<Map<String, dynamic>>(
      '/photos',
      data: form,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );
    return UploadedPhoto(
      id: json['id'] as int,
      url: json['url'] as String,
      thumbUrl: (json['thumb_url'] ?? json['url']) as String,
    );
  }
}

final photoUploaderProvider = Provider<PhotoUploader>(
  (ref) => ApiPhotoUploader(ref.watch(apiClientProvider)),
);

/// Injectable wrapper around image_picker.
abstract class PhotoPicker {
  Future<List<XFile>> pickPhotos(int maxCount);
}

class ImagePickerPhotoPicker implements PhotoPicker {
  @override
  Future<List<XFile>> pickPhotos(int maxCount) =>
      ImagePicker().pickMultiImage(limit: maxCount < 2 ? 2 : maxCount);
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => ImagePickerPhotoPicker(),
);
