import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/dart.dart';
import 'package:cryptography/cryptography.dart';

/// Checks `ssh-keygen -Y sign` signatures (OpenSSH `PROTOCOL.sshsig`) made
/// with an Ed25519 key. Nothing else is accepted: no other key types, no
/// certificates.
///
/// Blob of the armored signature:
///
///     byte[6]  "SSHSIG"
///     uint32   version (1)
///     string   public key   (string "ssh-ed25519", string key[32])
///     string   namespace
///     string   reserved
///     string   hash algorithm ("sha512" or "sha256")
///     string   signature    (string "ssh-ed25519", string sig[64])
///
/// What the key signed:
///
///     byte[6]  "SSHSIG"
///     string   namespace
///     string   reserved
///     string   hash algorithm
///     string   H(message)
class SshSignatureException implements Exception {
  const SshSignatureException(this.message);

  final String message;

  @override
  String toString() => 'SshSignatureException: $message';
}

const _magic = 'SSHSIG';
const _keyType = 'ssh-ed25519';

/// An Ed25519 public key, from an OpenSSH public key line
/// (`ssh-ed25519 AAAA... comment`).
class SshEd25519PublicKey {
  SshEd25519PublicKey._(this.bytes);

  /// The raw 32 key bytes.
  final Uint8List bytes;

  /// Throws [SshSignatureException] when [line] is not an ssh-ed25519 key.
  factory SshEd25519PublicKey.parse(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts[0] != _keyType) {
      throw const SshSignatureException('not an ssh-ed25519 public key');
    }
    final Uint8List blob;
    try {
      blob = base64.decode(parts[1]);
    } on FormatException {
      throw const SshSignatureException('public key is not base64');
    }
    return SshEd25519PublicKey._(_keyFromBlob(blob));
  }

  /// Null when [line] is empty or not a usable key.
  static SshEd25519PublicKey? tryParse(String? line) {
    if (line == null || line.trim().isEmpty) return null;
    try {
      return SshEd25519PublicKey.parse(line);
    } on SshSignatureException {
      return null;
    }
  }
}

/// The 32 key bytes of an SSH wire-format ssh-ed25519 public key blob.
Uint8List _keyFromBlob(Uint8List blob) {
  final r = _Reader(blob);
  if (r.string() != _keyType) {
    throw const SshSignatureException('public key is not ssh-ed25519');
  }
  final key = r.bytes();
  r.expectEnd();
  if (key.length != 32) {
    throw const SshSignatureException('ed25519 key must be 32 bytes');
  }
  return key;
}

/// Verifies [armored] (`-----BEGIN SSH SIGNATURE-----` ...) over [message]
/// for [key] and [namespace]. Returns normally only for a good signature;
/// throws [SshSignatureException] otherwise.
Future<void> verifySshSignature({
  required Uint8List message,
  required String armored,
  required SshEd25519PublicKey key,
  required String namespace,
}) async {
  final blob = _unarmor(armored);
  final r = _Reader(blob);
  if (ascii.decode(r.raw(6), allowInvalid: true) != _magic) {
    throw const SshSignatureException('not an SSHSIG signature');
  }
  if (r.uint32() != 1) {
    throw const SshSignatureException('unsupported SSHSIG version');
  }
  final signer = _keyFromBlob(r.bytes());
  final ns = r.string();
  final reserved = r.bytes();
  final hashAlg = r.string();
  final sigBlob = r.bytes();
  r.expectEnd();

  if (!_equal(signer, key.bytes)) {
    throw const SshSignatureException('signed with a different key');
  }
  if (ns != namespace) {
    throw SshSignatureException('wrong namespace "$ns"');
  }
  final List<int> digest = switch (hashAlg) {
    'sha512' => crypto.sha512.convert(message).bytes,
    'sha256' => crypto.sha256.convert(message).bytes,
    _ => throw SshSignatureException('unsupported hash "$hashAlg"'),
  };

  final s = _Reader(sigBlob);
  if (s.string() != _keyType) {
    throw const SshSignatureException('signature is not ssh-ed25519');
  }
  final sig = s.bytes();
  s.expectEnd();
  if (sig.length != 64) {
    throw const SshSignatureException('ed25519 signature must be 64 bytes');
  }

  final signed = BytesBuilder(copy: false)
    ..add(ascii.encode(_magic))
    ..add(_string(utf8.encode(namespace)))
    ..add(_string(reserved))
    ..add(_string(ascii.encode(hashAlg)))
    ..add(_string(digest));
  final ok = await DartEd25519().verify(
    signed.takeBytes(),
    signature: Signature(
      sig,
      publicKey: SimplePublicKey(key.bytes, type: KeyPairType.ed25519),
    ),
  );
  if (!ok) throw const SshSignatureException('bad signature');
}

Uint8List _unarmor(String armored) {
  const begin = '-----BEGIN SSH SIGNATURE-----';
  const end = '-----END SSH SIGNATURE-----';
  final text = armored.trim();
  final b = text.indexOf(begin);
  final e = text.indexOf(end);
  if (b != 0 || e < 0 || e + end.length != text.length) {
    throw const SshSignatureException('not an armored SSH signature');
  }
  final body = text.substring(begin.length, e).replaceAll(RegExp(r'\s'), '');
  try {
    return base64.decode(body);
  } on FormatException {
    throw const SshSignatureException('signature is not base64');
  }
}

Uint8List _string(List<int> data) {
  final out = Uint8List(4 + data.length);
  ByteData.sublistView(out).setUint32(0, data.length);
  out.setRange(4, out.length, data);
  return out;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Reads SSH wire-format values; any overrun is a [SshSignatureException].
class _Reader {
  _Reader(this._data);

  final Uint8List _data;
  int _pos = 0;

  Uint8List raw(int n) {
    if (n < 0 || _pos + n > _data.length) {
      throw const SshSignatureException('truncated signature');
    }
    final out = Uint8List.sublistView(_data, _pos, _pos + n);
    _pos += n;
    return out;
  }

  int uint32() => ByteData.sublistView(raw(4)).getUint32(0);

  Uint8List bytes() => raw(uint32());

  String string() {
    try {
      return utf8.decode(bytes());
    } on FormatException {
      throw const SshSignatureException('invalid text in signature');
    }
  }

  void expectEnd() {
    if (_pos != _data.length) {
      throw const SshSignatureException('trailing data in signature');
    }
  }
}
