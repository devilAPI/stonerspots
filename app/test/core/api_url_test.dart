import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/api_client.dart';

void main() {
  group('normalizeApiUrl', () {
    test('adds https:// and /api/v1 to a bare domain', () {
      expect(
        normalizeApiUrl('stonerspots.krasserserver.com'),
        'https://stonerspots.krasserserver.com/api/v1',
      );
    });

    test('adds /api/v1 when only the origin is given', () {
      expect(
        normalizeApiUrl('https://api.example.com'),
        'https://api.example.com/api/v1',
      );
      expect(
        normalizeApiUrl('https://api.example.com/'),
        'https://api.example.com/api/v1',
      );
    });

    test('keeps a complete URL, minus a trailing slash', () {
      expect(
        normalizeApiUrl('http://localhost:8080/api/v1'),
        'http://localhost:8080/api/v1',
      );
      expect(
        normalizeApiUrl('https://api.example.com/api/v1/'),
        'https://api.example.com/api/v1',
      );
    });

    test('keeps a custom path (reverse proxy prefix)', () {
      expect(
        normalizeApiUrl('https://example.com/stonerspots/api/v1'),
        'https://example.com/stonerspots/api/v1',
      );
    });

    test('bare IP with port gets https', () {
      expect(normalizeApiUrl('10.0.0.5:8080'), 'https://10.0.0.5:8080/api/v1');
    });

    test('trims whitespace (e.g. a newline pasted into the secret)', () {
      expect(
        normalizeApiUrl(' api.example.com\n'),
        'https://api.example.com/api/v1',
      );
    });
  });
}
