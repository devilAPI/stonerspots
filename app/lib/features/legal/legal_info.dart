import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';

/// The operator of the server, from `GET /legal` (the `legal:` section of
/// the server's config.yaml). Nothing of it is in the app or the repository.
class LegalInfo {
  const LegalInfo({
    required this.configured,
    this.operatorName = '',
    this.address = '',
    this.email = '',
    this.phone = '',
    this.responsiblePerson = '',
    this.country = '',
    this.privacyContactEmail = '',
    this.extra = '',
  });

  /// Nothing set up (or the server could not be asked).
  static const none = LegalInfo(configured: false);

  factory LegalInfo.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] is String ? j[k] as String : '').trim();
    final info = LegalInfo(
      configured: j['configured'] == true,
      operatorName: s('operator_name'),
      address: s('address'),
      email: s('email'),
      phone: s('phone'),
      responsiblePerson: s('responsible_person'),
      country: s('country'),
      privacyContactEmail: s('privacy_contact_email'),
      extra: s('extra'),
    );
    // A server that says yes but leaves out the essentials is not trusted
    // either: no half-filled legal notice.
    final complete =
        info.operatorName.isNotEmpty &&
        info.address.isNotEmpty &&
        info.email.isNotEmpty;
    return complete ? info : none;
  }

  /// Name, address and email are there.
  final bool configured;
  final String operatorName;

  /// Postal address, one line per line.
  final String address;
  final String email;
  final String phone;
  final String responsiblePerson;
  final String country;
  final String privacyContactEmail;
  final String extra;

  /// Who is responsible for the content: [responsiblePerson], else the
  /// operator (older servers might not send it).
  String get responsible =>
      responsiblePerson.isNotEmpty ? responsiblePerson : operatorName;

  /// Where privacy requests go: [privacyContactEmail], else [email].
  String get privacyEmail =>
      privacyContactEmail.isNotEmpty ? privacyContactEmail : email;
}

abstract class LegalRepository {
  Future<LegalInfo> fetch();
}

class ApiLegalRepository implements LegalRepository {
  ApiLegalRepository(this._api);

  final ApiClient _api;

  @override
  Future<LegalInfo> fetch() async =>
      LegalInfo.fromJson(await _api.get<Map<String, dynamic>>('/legal'));
}

final legalRepositoryProvider = Provider<LegalRepository>(
  (ref) => ApiLegalRepository(ref.watch(apiClientProvider)),
);

/// The operator details; an error when the server could not be asked (the
/// pages then say so and offer to try again, so no automatic retries).
final legalInfoProvider = FutureProvider<LegalInfo>(
  (ref) => ref.watch(legalRepositoryProvider).fetch(),
  retry: (_, _) => null,
);
