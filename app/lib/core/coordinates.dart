import 'package:latlong2/latlong.dart';

/// Rough DACH bounding box, same as the backend's region check.
const double kRegionMinLat = 45.8;
const double kRegionMaxLat = 55.1;
const double kRegionMinLon = 5.8;
const double kRegionMaxLon = 17.2;

bool inSupportedRegion(LatLng p) =>
    p.latitude >= kRegionMinLat &&
    p.latitude <= kRegionMaxLat &&
    p.longitude >= kRegionMinLon &&
    p.longitude <= kRegionMaxLon;

/// True for short map links that can only be resolved online.
bool isShortMapLink(String input) {
  final s = input.trim().toLowerCase();
  return s.contains('maps.app.goo.gl') || s.contains('goo.gl/maps');
}

typedef _Raw = ({double lat, double lon, bool explicitAxes});

/// Parses coordinates typed or pasted by a user: decimal degrees (dot or
/// comma), hemisphere letters, degrees/minutes/seconds, Google Maps and
/// OpenStreetMap links and `geo:` URIs. Returns null when [input] is not
/// clearly a coordinate pair. A pair given as lon/lat is swapped when only the
/// swapped pair lies in the supported region.
LatLng? parseCoordinates(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final lower = s.toLowerCase();
  final _Raw? raw;
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    raw = _fromUrl(s);
  } else if (lower.startsWith('geo:')) {
    raw = _fromPlain(s.substring(4).split('?').first);
  } else {
    raw = _fromPlain(s);
  }
  if (raw == null) return null;
  bool valid(double a, double b) => a.abs() <= 90 && b.abs() <= 180;
  final direct = valid(raw.lat, raw.lon) ? LatLng(raw.lat, raw.lon) : null;
  if (raw.explicitAxes) return direct;
  final swapped = valid(raw.lon, raw.lat) ? LatLng(raw.lon, raw.lat) : null;
  if (direct == null) {
    return swapped != null && inSupportedRegion(swapped) ? swapped : null;
  }
  if (!inSupportedRegion(direct) &&
      swapped != null &&
      inSupportedRegion(swapped)) {
    return swapped;
  }
  return direct;
}

const _num = r'\d+(?:[.,]\d+)?';
const _value =
    '(?:(?<d@>$_num)\\s*°\\s*(?:(?<m@>$_num)\\s*\'\\s*(?:(?<s@>$_num)\\s*(?:"|\'\')?)?)?'
    '|(?<x@>$_num)\\s*°?)';
const _hemi = '[NSEWO]';

String _comp(String n, bool prefixed) => prefixed
    ? '(?<p$n>$_hemi)\\s*(?<neg$n>-)?${_value.replaceAll('@', n)}'
    : '(?<neg$n>-)?${_value.replaceAll('@', n)}'
          '(?:\\s*(?<t$n>$_hemi)(?![\\p{L}\\d]))?';

final List<RegExp> _pairs = [
  for (final p1 in [false, true])
    for (final p2 in [false, true])
      RegExp(
        '^${_comp('1', p1)}(?:\\s*[,;]\\s*|\\s+)${_comp('2', p2)}\$',
        caseSensitive: false,
        unicode: true,
      ),
];

double _n(String? s) => double.parse(s!.replaceAll(',', '.'));

_Raw? _fromPlain(String input) {
  var s = input
      .replaceAll(RegExp('[\u2032\u2019\u2018`\u00b4]'), "'")
      .replaceAll(RegExp('[\u2033\u201d\u201c]'), '"')
      .replaceAll('\u00ba', '\u00b0')
      .trim();
  if (s.startsWith('(') && s.endsWith(')')) {
    s = s.substring(1, s.length - 1).trim();
  }
  RegExpMatch? m;
  for (final re in _pairs) {
    m = re.firstMatch(s);
    if (m != null) break;
  }
  if (m == null) return null;
  final match = m;

  ({double v, String? h}) comp(String n) {
    String? g(String k) =>
        match.groupNames.contains(k) ? match.namedGroup(k) : null;
    final v = g('x$n') != null
        ? _n(g('x$n'))
        : _n(g('d$n')) +
              (g('m$n') == null ? 0 : _n(g('m$n')) / 60) +
              (g('s$n') == null ? 0 : _n(g('s$n')) / 3600);
    final h = (g('p$n') ?? g('t$n'))?.toUpperCase();
    final neg = g('neg$n') != null || h == 'S' || h == 'W';
    return (v: neg ? -v : v, h: h);
  }

  final a = comp('1');
  final b = comp('2');
  bool isLat(String? h) => h == 'N' || h == 'S';
  bool isLon(String? h) => h == 'E' || h == 'W' || h == 'O';
  if (a.h == null && b.h == null) {
    return (lat: a.v, lon: b.v, explicitAxes: false);
  }
  if ((a.h == null || isLat(a.h)) && (b.h == null || isLon(b.h))) {
    return (lat: a.v, lon: b.v, explicitAxes: true);
  }
  if ((a.h == null || isLon(a.h)) && (b.h == null || isLat(b.h))) {
    return (lat: b.v, lon: a.v, explicitAxes: true);
  }
  return null;
}

final RegExp _bang = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)');
final RegExp _at = RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)');
final RegExp _osmMap = RegExp(
  r'map=\d+(?:\.\d+)?/(-?\d+(?:\.\d+)?)/(-?\d+(?:\.\d+)?)',
);

_Raw? _fromUrl(String s) {
  final uri = Uri.tryParse(s);
  if (uri == null || isShortMapLink(s)) return null;
  final host = uri.host.toLowerCase();
  _Raw? pair(String a, String b) {
    final la = double.tryParse(a);
    final lo = double.tryParse(b);
    return la == null || lo == null
        ? null
        : (lat: la, lon: lo, explicitAxes: true);
  }

  if (host.contains('google.')) {
    final bang = _bang.firstMatch(s);
    if (bang != null) return pair(bang.group(1)!, bang.group(2)!);
    final at = _at.firstMatch(uri.path);
    if (at != null) return pair(at.group(1)!, at.group(2)!);
    for (final key in ['q', 'll', 'query', 'center', 'destination', 'daddr']) {
      final v = uri.queryParameters[key];
      if (v != null) {
        final r = _fromPlain(v);
        if (r != null) return (lat: r.lat, lon: r.lon, explicitAxes: true);
      }
    }
    return null;
  }
  if (host.contains('openstreetmap.')) {
    final q = uri.queryParameters;
    if (q['mlat'] != null && q['mlon'] != null) {
      return pair(q['mlat']!, q['mlon']!);
    }
    final m = _osmMap.firstMatch(uri.fragment);
    if (m != null) return pair(m.group(1)!, m.group(2)!);
    return null;
  }
  return null;
}
