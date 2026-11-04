import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/legal/legal_info.dart';
import 'package:dio/dio.dart';

/// Operator details as a configured server sends them.
const testLegal = LegalInfo(
  configured: true,
  operatorName: 'Erika Beispiel',
  address: 'c/o Adressdienst\nWeg 2\n10115 Berlin',
  email: 'erika@beispiel.test',
  phone: '+49 30 0',
  responsiblePerson: 'Erika Beispiel',
  country: 'Deutschland',
  privacyContactEmail: 'datenschutz@beispiel.test',
  extra: 'Hobbyprojekt',
);

/// Answers with [info], or throws [error].
class FakeLegal implements LegalRepository {
  FakeLegal({this.info = testLegal, this.error});

  LegalInfo info;
  Object? error;
  int calls = 0;

  @override
  Future<LegalInfo> fetch() async {
    calls++;
    if (error != null) throw error!;
    return info;
  }
}

/// A dio adapter answering every request with [handler].
class JsonAdapter implements HttpClientAdapter {
  JsonAdapter(this.handler);

  final (int, Object) Function(RequestOptions) handler;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    seen.add(o);
    final (status, body) = handler(o);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
