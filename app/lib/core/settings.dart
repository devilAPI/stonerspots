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
  final _session = <String, bool>{};

  bool? getBool(String key) {
    final session = _session[key];
    if (session != null) return session;
    try {
      return _prefs?.getBool(key);
    } catch (_) {
      return null; // something else is stored under this key
    }
  }

  Future<void> setBool(String key, bool value) async {
    _session[key] = value;
    try {
      await _prefs?.setBool(key, value);
    } catch (_) {
      // Storage unavailable: it still holds for this session.
    }
  }
}

/// Overridden in `main` with the loaded store.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore.memory(),
);

/// An on/off setting, off by default.
class BoolSetting extends Notifier<bool> {
  BoolSetting(this.key);

  final String key;

  @override
  bool build() => ref.watch(settingsStoreProvider).getBool(key) ?? false;

  void set(bool value) {
    state = value;
    ref.read(settingsStoreProvider).setBool(key, value);
  }
}

final transparencyDisabledProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('disable_transparency'),
);

/// Applies the transparency setting to all glass below it. Goes above the
/// app's [Navigator], so that sheets and pushed pages follow it too.
class GlassSettingScope extends ConsumerWidget {
  const GlassSettingScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SolidGlass(
    enabled: ref.watch(transparencyDisabledProvider),
    child: child,
  );
}
