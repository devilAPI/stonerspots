import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Maps "search" link that drops a pin at the exact coordinates and
/// opens the Maps app when installed (otherwise the browser).
Uri googleMapsUri(double lat, double lon) => Uri.https(
  'www.google.com',
  '/maps/search/',
  {'api': '1', 'query': '$lat,$lon'},
);

/// Opens [uri] outside the app; returns false when nothing could handle it.
typedef UrlLauncher = Future<bool> Function(Uri uri);

final urlLauncherProvider = Provider<UrlLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
