import 'package:app/core/pow.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('solvePow finds a nonce with the required leading zero bits', () async {
    const challenge = '1:register:00ff:12:1700000000:600:sig';
    final nonce = await solvePow(challenge);
    final hash = sha256.convert('$challenge:$nonce'.codeUnits).bytes;
    // 12 bits: first byte zero, high nibble of the second zero
    expect(hash[0], 0);
    expect(hash[1] >> 4, 0);
  });
}
