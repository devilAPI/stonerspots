import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location_service.dart';
import '../map/spots_controller.dart';
import 'nearest_spot.dart';

/// Hands a payload to the Android home screen widgets.
typedef HomeWidgetPush = Future<void> Function(String json);

const _channel = MethodChannel('de.stonerspots.app/home_widget');

Future<void> _pushToAndroid(String json) async {
  try {
    await _channel.invokeMethod<void>('update', json);
  } on PlatformException catch (e) {
    debugPrint('home widget update failed: $e');
  } on MissingPluginException {
    // No native side (widget tests).
  }
}

/// Only Android has these widgets; null everywhere else.
final homeWidgetPushProvider = Provider<HomeWidgetPush?>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? _pushToAndroid
      : null,
);

/// The app's language for the device locale, resolved as in `main.dart`:
/// German unless the device is set to English. The widget's own strings
/// follow the same rule through its Android resources.
String _deviceLanguage() =>
    PlatformDispatcher.instance.locale.languageCode == 'en' ? 'en' : 'de';

/// Keeps the "nearest spot" widget up to date while the app runs. Watch it
/// once at the top of the app.
final homeWidgetSyncProvider = Provider<void>((ref) {
  final push = ref.watch(homeWidgetPushProvider);
  if (push == null) return;
  final tracker = NearestSpotTracker(languageCode: _deviceLanguage);
  String? pushed;
  void send(NearestSpotPayload? payload) {
    final json = payload?.encode();
    if (json == null || json == pushed) return;
    pushed = json;
    push(json);
  }

  ref.listen(lastLocationLookupProvider, (_, lookup) {
    if (lookup != null) send(tracker.onLookup(lookup.position));
  });
  ref.listen(spotsControllerProvider, (_, s) {
    if (s.loading || s.error) return;
    send(tracker.onSpots(s.spots, filtered: s.tags.isNotEmpty));
  });
});
