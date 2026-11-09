import 'dart:convert';
import 'dart:typed_data';

/// A minimal reader for Mapbox Vector Tiles (protobuf, spec 2.1): only what
/// the 3D buildings need - one layer's polygon features, their geometry in
/// tile coordinates and their properties.

/// One polygon feature: its rings in tile coordinates (x, y interleaved;
/// y down, 0..[MvtLayer.extent]) and its properties.
class MvtFeature {
  const MvtFeature(this.rings, this.properties);

  /// Each ring closed implicitly (last point != first). Exterior rings have
  /// a positive surveyor's area in tile coordinates, holes a negative one.
  final List<Int32List> rings;
  final Map<String, Object?> properties;
}

class MvtLayer {
  const MvtLayer(this.name, this.extent, this.features);
  final String name;
  final int extent;
  final List<MvtFeature> features;
}

class _Reader {
  _Reader(this.b, [this.pos = 0, int? end]) : end = end ?? b.length;
  final Uint8List b;
  int pos;
  final int end;

  bool get more => pos < end;

  int varint() {
    var result = 0, shift = 0;
    while (true) {
      final byte = b[pos++];
      // stays exact up to 2^53, plenty for tile data
      result += (byte & 0x7f) * _pow2(shift);
      if (byte < 0x80) return result;
      shift += 7;
    }
  }

  static int _pow2(int s) => s < 31 ? 1 << s : (1 << 30) * (1 << (s - 30));

  /// A length-delimited field: a reader over just its bytes.
  _Reader sub() {
    final len = varint();
    final r = _Reader(b, pos, pos + len);
    pos += len;
    return r;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        varint();
      case 1:
        pos += 8;
      case 2:
        // not `pos += varint()`: that reads pos before varint() moves it
        final len = varint();
        pos += len;
      case 5:
        pos += 4;
      default:
        throw const FormatException('bad wire type');
    }
  }

  List<int> packed() {
    final r = sub();
    final out = <int>[];
    while (r.more) {
      out.add(r.varint());
    }
    return out;
  }
}

int _zigzag(int n) => (n & 1) == 0 ? n >> 1 : -((n + 1) >> 1);

/// The layer [name] of the tile [bytes], or null when the tile has none.
/// Only polygon features are returned.
MvtLayer? readMvtLayer(Uint8List bytes, String name) {
  final tile = _Reader(bytes);
  while (tile.more) {
    final key = tile.varint();
    if (key >> 3 == 3 && key & 7 == 2) {
      final layer = _readLayer(tile.sub(), name);
      if (layer != null) return layer;
    } else {
      tile.skip(key & 7);
    }
  }
  return null;
}

MvtLayer? _readLayer(_Reader r, String want) {
  // the name usually comes first; read the rest only for the wanted layer
  final start = r.pos;
  String? name;
  while (r.more) {
    final key = r.varint();
    if (key >> 3 == 1 && key & 7 == 2) {
      final s = r.sub();
      name = _utf8(s.b, s.pos, s.end);
      break;
    }
    r.skip(key & 7);
  }
  if (name != want) return null;
  r.pos = start;

  var extent = 4096;
  final keys = <String>[];
  final values = <Object?>[];
  final raw = <_Reader>[];
  while (r.more) {
    final key = r.varint();
    switch ((key >> 3, key & 7)) {
      case (2, 2):
        raw.add(r.sub());
      case (3, 2):
        final s = r.sub();
        keys.add(_utf8(s.b, s.pos, s.end));
      case (4, 2):
        values.add(_readValue(r.sub()));
      case (5, 0):
        extent = r.varint();
      default:
        r.skip(key & 7);
    }
  }
  final features = <MvtFeature>[];
  for (final f in raw) {
    final feature = _readFeature(f, keys, values);
    if (feature != null) features.add(feature);
  }
  return MvtLayer(want, extent, features);
}

String _utf8(Uint8List b, int start, int end) {
  for (var i = start; i < end; i++) {
    if (b[i] >= 0x80) {
      return utf8.decode(
        Uint8List.sublistView(b, start, end),
        allowMalformed: true,
      );
    }
  }
  return String.fromCharCodes(b, start, end); // ASCII fast path
}

Object? _readValue(_Reader r) {
  Object? v;
  while (r.more) {
    final key = r.varint();
    switch ((key >> 3, key & 7)) {
      case (1, 2):
        final s = r.sub();
        v = _utf8(s.b, s.pos, s.end);
      case (2, 5):
        v = ByteData.sublistView(
          r.b,
          r.pos,
          r.pos + 4,
        ).getFloat32(0, Endian.little);
        r.pos += 4;
      case (3, 1):
        v = ByteData.sublistView(
          r.b,
          r.pos,
          r.pos + 8,
        ).getFloat64(0, Endian.little);
        r.pos += 8;
      case (4, 0) || (5, 0):
        v = r.varint();
      case (6, 0):
        v = _zigzag(r.varint());
      case (7, 0):
        v = r.varint() != 0;
      default:
        r.skip(key & 7);
    }
  }
  return v;
}

MvtFeature? _readFeature(_Reader r, List<String> keys, List<Object?> values) {
  var type = 0;
  List<int> tags = const [], geometry = const [];
  while (r.more) {
    final key = r.varint();
    switch ((key >> 3, key & 7)) {
      case (2, 2):
        tags = r.packed();
      case (3, 0):
        type = r.varint();
      case (4, 2):
        geometry = r.packed();
      default:
        r.skip(key & 7);
    }
  }
  if (type != 3) return null; // polygons only
  final props = <String, Object?>{};
  for (var i = 0; i + 1 < tags.length; i += 2) {
    if (tags[i] < keys.length && tags[i + 1] < values.length) {
      props[keys[tags[i]]] = values[tags[i + 1]];
    }
  }
  final rings = <Int32List>[];
  var x = 0, y = 0, i = 0;
  List<int>? ring;
  while (i < geometry.length) {
    final cmd = geometry[i] & 7, count = geometry[i] >> 3;
    i++;
    if (cmd == 1 || cmd == 2) {
      for (var k = 0; k < count && i + 1 < geometry.length; k++) {
        x += _zigzag(geometry[i++]);
        y += _zigzag(geometry[i++]);
        if (cmd == 1) {
          ring = [x, y];
        } else {
          ring
            ?..add(x)
            ..add(y);
        }
      }
    } else if (cmd == 7) {
      if (ring != null && ring.length >= 6) rings.add(Int32List.fromList(ring));
      ring = null;
    } else {
      return null;
    }
  }
  return rings.isEmpty ? null : MvtFeature(rings, props);
}
