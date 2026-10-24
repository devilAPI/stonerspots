import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';

/// Human-readable reason why adding a spot (or uploading its photos) failed.
/// Known problems get their own text; unknown server errors still show the
/// server's message so the cause is never hidden behind a generic line.
String addSpotErrorText(AppLocalizations l, Object error) {
  if (error is! ApiException) return l.errorGeneric;
  switch (error.code) {
    case 'unsupported_type':
      return l.addSpotPhotoUnsupported;
    case 'too_large':
      return l.addSpotPhotoTooLarge;
    case 'invalid_location':
      return l.placeSearchOutside;
    case 'network_error':
      return l.errorNetwork;
  }
  final msg = error.message.trim();
  return msg.isEmpty ? l.errorGeneric : l.errorWithDetail(msg);
}
