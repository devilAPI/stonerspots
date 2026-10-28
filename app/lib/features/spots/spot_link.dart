import 'package:flutter/foundation.dart';

/// Public address of the web app, used for links shared from the native
/// apps: `--dart-define=WEB_URL=https://.../`.
const String kWebAppUrl = String.fromEnvironment(
  'WEB_URL',
  defaultValue: 'https://devilapi.github.io/stonerspots/',
);

/// Link that opens spot [id] in the web app. In the browser it points at the
/// web app being used (so /dev/ links stay on /dev/), otherwise at
/// [kWebAppUrl]. The web app routes by URL fragment (`#/spot/12`).
Uri spotLink(int id, {Uri? base}) {
  final b = base ?? (kIsWeb ? Uri.base : Uri.parse(kWebAppUrl));
  return Uri(
    scheme: b.scheme,
    host: b.host,
    port: b.hasPort ? b.port : null,
    path: b.path.isEmpty ? '/' : b.path,
    fragment: '/spot/$id',
  );
}
