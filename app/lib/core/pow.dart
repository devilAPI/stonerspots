import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Solves a registration proof-of-work challenge from the server: finds a
/// nonce such that SHA-256(`challenge:nonce`) has as many leading zero
/// bits as the difficulty (4th field of the challenge). Runs off the UI
/// thread where the platform allows it.
Future<String> solvePow(String challenge) => compute(_solve, challenge);

String _solve(String challenge) {
  final difficulty = int.parse(challenge.split(':')[3]);
  for (var i = 0; ; i++) {
    final nonce = i.toRadixString(16);
    final hash = sha256.convert('$challenge:$nonce'.codeUnits).bytes;
    if (_leadingZeroBits(hash) >= difficulty) return nonce;
  }
}

int _leadingZeroBits(List<int> bytes) {
  var n = 0;
  for (final b in bytes) {
    if (b == 0) {
      n += 8;
      continue;
    }
    return n + 8 - b.bitLength;
  }
  return n;
}
