import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glass.dart';

/// Keeps the user's settings. [SettingsStore.load] persists them on the
/// device; [SettingsStore.memory] keeps them for the session (tests, or when
/// no storage is available).
class SettingsStore {
  SettingsStore.memory() : _prefs = null;

  SettingsStore._(this._prefs);

  /// Settings are read synchronously from then on, so call this once before
  /// [runApp]: the first frame already has them.
  static Future<SettingsStore> load() async {
    try {
      return SettingsStore._(await SharedPreferences.getInstance());
    } catch (_) {
      return SettingsStore.memory();
    }
  }

  final SharedPreferences? _prefs;
  final _session = <String, Object?>{};

  /// The value under [key] if it has type [T], else null.
  T? _get<T>(String key, Object? Function(SharedPreferences p) read) {
    if (_session.containsKey(key)) {
      final v = _session[key];
      return v is T ? v : null;
    }
    try {
      final v = _prefs == null ? null : read(_prefs);
      return v is T ? v : null;
    } catch (_) {
      return null; // something else is stored under this key
    }
  }

  Future<void> _set(
    String key,
    Object? value,
    Future<bool> Function(SharedPreferences p) write,
  ) async {
    _session[key] = value;
    try {
      if (_prefs != null) await write(_prefs);
    } catch (_) {
      // Storage unavailable: it still holds for this session.
    }
  }

  bool? getBool(String key) => _get<bool>(key, (p) => p.getBool(key));

  Future<void> setBool(String key, bool value) =>
      _set(key, value, (p) => p.setBool(key, value));

  String? getString(String key) => _get<String>(key, (p) => p.getString(key));

  /// Stores [value], or removes the key when it is null.
  Future<void> setString(String key, String? value) => _set(
    key,
    value,
    (p) => value == null ? p.remove(key) : p.setString(key, value),
  );

  int? getInt(String key) => _get<int>(key, (p) => p.getInt(key));

  /// Stores [value], or removes the key when it is null.
  Future<void> setInt(String key, int? value) => _set(
    key,
    value,
    (p) => value == null ? p.remove(key) : p.setInt(key, value),
  );
}

/// Overridden in `main` with the loaded store.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore.memory(),
);

/// An on/off setting, off unless [defaultValue] says otherwise.
class BoolSetting extends Notifier<bool> {
  BoolSetting(this.key, {this.defaultValue = false});

  final String key;
  final bool defaultValue;

  @override
  bool build() => ref.watch(settingsStoreProvider).getBool(key) ?? defaultValue;

  void set(bool value) {
    state = value;
    ref.read(settingsStoreProvider).setBool(key, value);
  }
}

final transparencyDisabledProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('disable_transparency'),
);

/// The 3D map shows buildings. On by default; off, the tilted map is drawn
/// without them, which is much lighter on older devices.
final buildings3dProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('map_3d_buildings', defaultValue: true),
);

/// Maps load high-resolution tiles on high-density screens. On by default;
/// off, a quarter of the pixels (and data) for a slightly softer map.
final sharpTilesProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('map_sharp_tiles', defaultValue: true),
);

/// The map jumps instead of flying and tilts without an animation. The
/// system's "remove animations" has the same effect.
final reduceMotionProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('reduce_motion'),
);

/// Applies the settings that every screen follows to the widgets below it:
/// glass ([SolidGlass]) and the maps ([MapSettings]). Goes above the app's
/// [Navigator], so that sheets and pushed pages follow them too.
class SettingsScope extends ConsumerWidget {
  const SettingsScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SolidGlass(
    enabled: ref.watch(transparencyDisabledProvider),
    child: MapSettings(
      sharpTiles: ref.watch(sharpTilesProvider),
      reduceMotion: ref.watch(reduceMotionProvider),
      child: child,
    ),
  );
}

/// How maps below it load and move. Without it they use the defaults: sharp
/// tiles, animated.
class MapSettings extends InheritedWidget {
  const MapSettings({
    super.key,
    required this.sharpTiles,
    required this.reduceMotion,
    required super.child,
  });

  final bool sharpTiles;
  final bool reduceMotion;

  static MapSettings? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapSettings>();

  /// Whether to load high-resolution tiles on a high-density screen.
  static bool sharpTilesOf(BuildContext context) =>
      _of(context)?.sharpTiles ?? true;

  /// Whether to skip map animations: the setting, or the system's.
  static bool reduceMotionOf(BuildContext context) =>
      (_of(context)?.reduceMotion ?? false) ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  bool updateShouldNotify(MapSettings old) =>
      sharpTiles != old.sharpTiles || reduceMotion != old.reduceMotion;
}
