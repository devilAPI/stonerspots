import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/spots/add_spot_controller.dart';
import 'package:app/features/spots/photo_uploader.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/features/spots/updates_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

class FakeSpotApi implements SpotApi {
  final List<bool> forces = [];
  Object? createError;

  @override
  Future<Spot> createSpot(SpotDraft draft, {bool force = false}) async {
    forces.add(force);
    final e = createError;
    if (e != null && !force) throw e;
    return Spot(
        id: 7,
        title: draft.title,
        category: draft.category,
        lat: draft.lat,
        lon: draft.lon);
  }

  @override
  Future<Spot> getSpot(int id) => throw UnimplementedError();
  @override
  Future<LikeResult> setLike(int spotId, {required bool liked}) =>
      throw UnimplementedError();
  @override
  Future<void> report(String t, int id, String r) => throw UnimplementedError();
}

class FakeUploader implements PhotoUploader {
  int calls = 0;
  bool fail = false;

  @override
  Future<UploadedPhoto> upload(XFile file,
      {void Function(double)? onProgress}) async {
    calls++;
    if (fail) throw ApiException(500, 'internal', 'boom');
    return UploadedPhoto(id: calls, url: 'u', thumbUrl: 't');
  }
}

class FakeUpdates implements UpdatesRepository {
  final posted = <List<int>>[];

  @override
  Future<List<FeedItem>> listForSpot(int spotId) async => [];

  @override
  Future<void> post(int spotId,
      {required String body, List<int> photoIds = const []}) async {
    posted.add(photoIds);
  }
}

void main() {
  late FakeSpotApi api;
  late FakeUploader uploader;
  late FakeUpdates updates;
  late ProviderContainer c;

  setUp(() {
    api = FakeSpotApi();
    uploader = FakeUploader();
    updates = FakeUpdates();
    c = ProviderContainer(overrides: [
      spotApiProvider.overrideWithValue(api),
      photoUploaderProvider.overrideWithValue(uploader),
      spotUpdatesRepositoryProvider.overrideWithValue(updates),
    ]);
    addTearDown(c.dispose);
    c.listen(addSpotControllerProvider, (_, _) {});
  });

  AddSpotController ctrl() => c.read(addSpotControllerProvider.notifier);
  AddSpotState st() => c.read(addSpotControllerProvider);

  void fillRequired() {
    ctrl().setTitle('Bench');
    ctrl().setCategory('bench');
    ctrl().setPoint(const LatLng(49.5, 10.5));
  }

  test('submit is disabled until title, category and point are set', () {
    expect(st().canSubmit, isFalse);
    ctrl().setTitle('Bench');
    expect(st().canSubmit, isFalse);
    ctrl().setCategory('bench');
    expect(st().canSubmit, isFalse);
    ctrl().setPoint(const LatLng(49.5, 10.5));
    expect(st().canSubmit, isTrue);
    ctrl().setTitle('   ');
    expect(st().canSubmit, isFalse);
  });

  test('409 duplicate surfaces the existing spot and allows force', () async {
    api.createError =
        ApiException(409, 'possible_duplicate', 'spot nearby id=42');
    fillRequired();
    await ctrl().submit();
    expect(st().duplicate, isTrue);
    expect(st().duplicateSpotId, 42);
    expect(st().createdSpotId, isNull);
    expect(st().title, 'Bench');

    await ctrl().submit(force: true);
    expect(api.forces, [false, true]);
    expect(st().duplicate, isFalse);
    expect(st().createdSpotId, 7);
  });

  test('max 4 photos enforced', () {
    final files = List.generate(6, (i) => XFile('p$i.jpg'));
    expect(ctrl().addPhotos(files), 4);
    expect(st().photos.length, 4);
    expect(ctrl().addPhotos([XFile('x.jpg')]), 0);
    expect(st().photos.length, 4);
  });

  test('upload failure keeps form state', () async {
    fillRequired();
    ctrl().setDescription('nice');
    ctrl().addPhotos([XFile('a.jpg')]);
    uploader.fail = true;
    await ctrl().submit();
    expect(st().error, isA<ApiException>());
    expect(st().submitting, isFalse);
    expect(st().title, 'Bench');
    expect(st().description, 'nice');
    expect(st().photos.length, 1);
    expect(api.forces, isEmpty);

    uploader.fail = false;
    await ctrl().submit();
    expect(st().createdSpotId, 7);
    expect(updates.posted, [
      [2]
    ]);
  });
}
