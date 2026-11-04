// Vectors in fixtures/ were made with OpenSSH:
//   ssh-keygen -t ed25519 -f key; ssh-keygen -t ed25519 -f other
//   ssh-keygen -Y sign -f key -n stonerspots-release SHA256SUMS-apps.txt
//   ... -O hashalg=sha256          -> SHA256SUMS-apps.hashalg-sha256.sig
//   ... -n file                    -> SHA256SUMS-apps.wrong-namespace.sig
//   ... -f other                   -> SHA256SUMS-apps.other-key.sig
// The release-channel vectors (update_controller_test) the same way, with a
// key of their own: ssh-keygen -Y sign -f v1key -n stonerspots-release
// SHA256SUMS-apps.v1.0.1.txt, public key release_v1_key.pub.
// Only the public keys are kept.
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/updater/sshsig.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final message = fixtureBytes('SHA256SUMS-apps.txt');
  final key = SshEd25519PublicKey.parse(fixtureText('release_key.pub'));
  final otherKey = SshEd25519PublicKey.parse(fixtureText('other_key.pub'));

  Future<void> verify(
    String sigFile, {
    Uint8List? data,
    SshEd25519PublicKey? withKey,
    String namespace = 'stonerspots-release',
    String? armored,
  }) => verifySshSignature(
    message: data ?? message,
    armored: armored ?? fixtureText(sigFile),
    key: withKey ?? key,
    namespace: namespace,
  );

  final throwsSig = throwsA(isA<SshSignatureException>());

  test('accepts the signature ssh-keygen made (sha512)', () async {
    await verify('SHA256SUMS-apps.txt.sig');
  });

  test('accepts a sha256 signature too', () async {
    await verify('SHA256SUMS-apps.hashalg-sha256.sig');
  });

  test('rejects another namespace', () async {
    await expectLater(verify('SHA256SUMS-apps.wrong-namespace.sig'), throwsSig);
    // and a good signature checked for another namespace
    await expectLater(
      verify('SHA256SUMS-apps.txt.sig', namespace: 'file'),
      throwsSig,
    );
  });

  test('rejects tampered data', () async {
    final tampered = Uint8List.fromList(message);
    tampered[0] ^= 1;
    await expectLater(
      verify('SHA256SUMS-apps.txt.sig', data: tampered),
      throwsSig,
    );
    await expectLater(
      verify(
        'SHA256SUMS-apps.txt.sig',
        data: Uint8List.fromList([...message, 10]),
      ),
      throwsSig,
    );
  });

  test('rejects a signature by another key', () async {
    await expectLater(verify('SHA256SUMS-apps.other-key.sig'), throwsSig);
    await expectLater(
      verify('SHA256SUMS-apps.txt.sig', withKey: otherKey),
      throwsSig,
    );
  });

  test('rejects a signature whose embedded key was swapped', () async {
    // Put the other key into a good signature's blob: the claimed signer
    // no longer matches, and even if it did the Ed25519 check would fail.
    final armored = fixtureText('SHA256SUMS-apps.txt.sig');
    final body = armored
        .split('\n')
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join();
    final blob = base64.decode(body);
    final keyAt = _indexOf(blob, key.bytes);
    expect(keyAt, greaterThan(0));
    blob.setRange(keyAt, keyAt + 32, otherKey.bytes);
    final swapped =
        '-----BEGIN SSH SIGNATURE-----\n${base64.encode(blob)}\n-----END SSH SIGNATURE-----\n';
    await expectLater(
      verify('', armored: swapped, withKey: otherKey),
      throwsSig,
    );
  });

  test('rejects junk', () async {
    await expectLater(verify('', armored: ''), throwsSig);
    await expectLater(verify('', armored: 'hello'), throwsSig);
    await expectLater(
      verify(
        '',
        armored: '-----BEGIN SSH SIGNATURE-----\nU1NIU0lH\n-----END SSH SIGNATURE-----',
      ),
      throwsSig,
    );
    // truncated
    final good = fixtureText('SHA256SUMS-apps.txt.sig').trim().split('\n');
    final cut = [good.first, good[1], good.last].join('\n');
    await expectLater(verify('', armored: cut), throwsSig);
  });

  test('public key lines', () {
    expect(SshEd25519PublicKey.tryParse(null), isNull);
    expect(SshEd25519PublicKey.tryParse(''), isNull);
    expect(SshEd25519PublicKey.tryParse('ssh-rsa AAAAB3NzaC1yc2E='), isNull);
    expect(SshEd25519PublicKey.tryParse('ssh-ed25519 !!!'), isNull);
    // the type inside the blob must match too
    expect(
      SshEd25519PublicKey.tryParse('ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB'),
      isNull,
    );
    final k = SshEd25519PublicKey.tryParse(fixtureText('release_key.pub'));
    expect(k?.bytes.length, 32);
    // comment-less line, as passed in --dart-define
    final parts = fixtureText('release_key.pub').split(' ');
    expect(
      SshEd25519PublicKey.tryParse('${parts[0]} ${parts[1]}')?.bytes,
      k?.bytes,
    );
  });
}

int _indexOf(List<int> hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length && ok; j++) {
      ok = hay[i + j] == needle[j];
    }
    if (ok) return i;
  }
  return -1;
}
