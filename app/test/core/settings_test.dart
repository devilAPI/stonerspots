import 'package:app/core/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer containerWith(SettingsStore store) {
  final c = ProviderContainer(
    overrides: [settingsStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('transparency stays on by default, without any platform storage', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(transparencyDisabledProvider), isFalse);
    c.read(transparencyDisabledProvider.notifier).set(true);
    expect(c.read(transparencyDisabledProvider), isTrue);
  });

  test('the setting survives a restart of the app', () async {
    SharedPreferences.setMockInitialValues({});
    final first = containerWith(await SettingsStore.load());
    expect(first.read(transparencyDisabledProvider), isFalse);
    first.read(transparencyDisabledProvider.notifier).set(true);
    await pumpEventQueue();

    // A new launch: nothing is left in memory but the platform store.
    SharedPreferences.resetStatic();
    final second = containerWith(await SettingsStore.load());
    expect(second.read(transparencyDisabledProvider), isTrue);

    second.read(transparencyDisabledProvider.notifier).set(false);
    await pumpEventQueue();
    SharedPreferences.resetStatic();
    final third = containerWith(await SettingsStore.load());
    expect(third.read(transparencyDisabledProvider), isFalse);
  });

  test('a stored value of the wrong type counts as not set', () async {
    SharedPreferences.setMockInitialValues({
      'disable_transparency': 'not a bool',
    });
    final c = containerWith(await SettingsStore.load());
    expect(c.read(transparencyDisabledProvider), isFalse);
  });
}
