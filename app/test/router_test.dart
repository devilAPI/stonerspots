import 'package:app/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('add-spot requires login, map and feed are public', () {
    expect(
      authRedirect(loggedIn: false, location: '/spot/new'),
      '/login?from=%2Fspot%2Fnew',
    );
    expect(authRedirect(loggedIn: true, location: '/spot/new'), isNull);
    expect(authRedirect(loggedIn: false, location: '/'), isNull);
    expect(authRedirect(loggedIn: false, location: '/feed'), isNull);
    expect(authRedirect(loggedIn: false, location: '/spot/5'), isNull);
  });

  test('admin route guard', () {
    expect(
      authRedirect(loggedIn: false, location: '/admin'),
      '/login?from=%2Fadmin',
    );
    expect(authRedirect(loggedIn: true, location: '/admin'), '/');
    expect(
      authRedirect(loggedIn: true, isAdmin: false, location: '/admin'),
      '/',
    );
    expect(
      authRedirect(loggedIn: true, isAdmin: true, location: '/admin'),
      isNull,
    );
    expect(authRedirect(loggedIn: true, location: '/feed'), isNull);
  });
}
