// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Stonerspots';

  @override
  String get navMap => 'Karte';

  @override
  String get navFeed => 'Feed';

  @override
  String get navProfile => 'Profil';

  @override
  String get mapTitle => 'Karte';

  @override
  String get feedTitle => 'Feed';

  @override
  String get spotDetailTitle => 'Spot';

  @override
  String get addSpotTitle => 'Spot hinzufügen';

  @override
  String get addSpot => 'Spot hinzufügen';

  @override
  String get login => 'Anmelden';

  @override
  String get register => 'Registrieren';

  @override
  String get logout => 'Abmelden';

  @override
  String get email => 'E-Mail';

  @override
  String get password => 'Passwort';

  @override
  String get displayName => 'Anzeigename';

  @override
  String get adultConfirm => 'Ich bin mindestens 18 Jahre alt';

  @override
  String get noAccountYet => 'Noch kein Konto? Registrieren';

  @override
  String get haveAccount => 'Schon ein Konto? Anmelden';

  @override
  String get passwordTooShort => 'Mindestens 10 Zeichen';

  @override
  String get fieldRequired => 'Pflichtfeld';

  @override
  String get sort => 'Sortieren';

  @override
  String get sortNew => 'Neu';

  @override
  String get sortTop => 'Top';

  @override
  String get sortNearby => 'In der Nähe';

  @override
  String get like => 'Gefällt mir';

  @override
  String get report => 'Melden';

  @override
  String get reportReason => 'Grund';

  @override
  String get postUpdate => 'Update posten';

  @override
  String get openSpot => 'Öffnen';

  @override
  String get openInGoogleMaps => 'In Google Maps öffnen';

  @override
  String get title => 'Titel';

  @override
  String get description => 'Beschreibung';

  @override
  String get addPhotos => 'Fotos hinzufügen';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get duplicateSpot =>
      'Hier gibt es schon einen Spot – öffnen oder trotzdem hinzufügen';

  @override
  String get addAnyway => 'Trotzdem hinzufügen';

  @override
  String get loginRequired => 'Bitte melde dich an';

  @override
  String get errorGeneric => 'Etwas ist schiefgelaufen';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get noResults => 'Nichts gefunden';

  @override
  String get locationDenied => 'Standortzugriff verweigert';

  @override
  String likesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Likes',
      one: '1 Like',
      zero: 'Keine Likes',
    );
    return '$_temp0';
  }

  @override
  String feedUpdateCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Updates',
      one: '1 Update',
    );
    return '$_temp0';
  }

  @override
  String get changePassword => 'Passwort ändern';

  @override
  String get currentPassword => 'Aktuelles Passwort';

  @override
  String get newPassword => 'Neues Passwort';

  @override
  String get repeatNewPassword => 'Neues Passwort wiederholen';

  @override
  String get passwordsDontMatch => 'Passwörter stimmen nicht überein';

  @override
  String get passwordTooLong => 'Höchstens 72 Zeichen';

  @override
  String get passwordChanged => 'Passwort geändert';

  @override
  String get wrongPassword => 'Falsches Passwort';

  @override
  String get deleteAccount => 'Konto löschen';

  @override
  String get deleteAccountWarning =>
      'Dein Konto sowie alle deine Spots, Updates und Fotos werden dauerhaft gelöscht. Das kann nicht rückgängig gemacht werden. Gib zur Bestätigung dein Passwort ein.';

  @override
  String get deleteAccountConfirm => 'Endgültig löschen';

  @override
  String get placeSearchHint => 'Adresse oder Koordinaten';

  @override
  String get placeSearchClear => 'Leeren';

  @override
  String get placeSearchGo => 'Suchen';

  @override
  String get placeSearchTooShort => 'Bitte mindestens 3 Zeichen eingeben';

  @override
  String get placeSearchNoResult => 'Kein Ort gefunden';

  @override
  String get placeSearchOutside =>
      'Diese Koordinaten liegen außerhalb des unterstützten Gebiets (Deutschland, Österreich, Schweiz, Liechtenstein)';

  @override
  String get placeSearchRateLimited =>
      'Zu viele Suchanfragen, bitte gleich noch einmal versuchen';

  @override
  String get placeSearchUnavailable =>
      'Die Adresssuche ist gerade nicht verfügbar, bitte später erneut versuchen';

  @override
  String get placeSearchError => 'Suche fehlgeschlagen, bitte erneut versuchen';

  @override
  String get placeSearchShortLink =>
      'Kurzlinks können nicht aufgelöst werden. Bitte den vollständigen Link oder die Koordinaten einfügen.';

  @override
  String get adminOpen => 'Admin';

  @override
  String get adminTitle => 'Admin';

  @override
  String get adminReports => 'Meldungen';

  @override
  String get adminUsers => 'Nutzer';

  @override
  String get adminSpots => 'Spots';

  @override
  String adminReportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Meldungen',
      one: '1 Meldung',
    );
    return '$_temp0';
  }

  @override
  String adminReportedBy(String name, String email) {
    return 'Gemeldet von $name ($email)';
  }

  @override
  String get adminTargetDeleted => 'Gelöscht';

  @override
  String adminUpdateOn(String title) {
    return 'Update zu $title';
  }

  @override
  String get statusActive => 'Aktiv';

  @override
  String get statusHidden => 'Versteckt';

  @override
  String get statusLocked => 'Gesperrt';

  @override
  String get statusAll => 'Alle';

  @override
  String get adminOpenSpot => 'Spot öffnen';

  @override
  String get adminRemoveSpot => 'Spot entfernen';

  @override
  String get adminRemove => 'Entfernen';

  @override
  String get adminSearchUsers => 'Name oder E-Mail suchen';

  @override
  String get adminSearchSpots => 'Titel suchen';

  @override
  String get adminBadge => 'admin';

  @override
  String adminUserSpots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Spots',
      one: '1 Spot',
    );
    return '$_temp0';
  }

  @override
  String adminUserReports(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Meldungen erhalten',
      one: '1 Meldung erhalten',
    );
    return '$_temp0';
  }

  @override
  String adminJoined(String date) {
    return 'Beigetreten $date';
  }

  @override
  String adminSpotAuthor(String name) {
    return 'von $name';
  }

  @override
  String get adminRemoveTitle => 'Spot entfernen?';

  @override
  String adminRemoveBody(String title) {
    return '„$title“ wird mit allen Updates, Likes und Fotos endgültig gelöscht.';
  }

  @override
  String get adminSpotRemoved => 'Spot entfernt';

  @override
  String get adminEdit => 'Bearbeiten';

  @override
  String get adminEditUser => 'Nutzer bearbeiten';

  @override
  String get adminEditSpot => 'Spot bearbeiten';

  @override
  String get adminIsAdmin => 'Admin';

  @override
  String get adminSelfAdminHint =>
      'Du kannst deinen eigenen Admin-Status nicht ändern.';

  @override
  String get adminStatus => 'Status';

  @override
  String get adminCoordinates => 'Koordinaten (Breite, Länge)';

  @override
  String get adminCoordsInvalid =>
      'Diese Koordinaten konnten nicht gelesen werden. Nutze z. B. 48.137, 11.575 oder einen Kartenlink.';

  @override
  String get adminUserSaved => 'Nutzer aktualisiert';

  @override
  String get adminSpotSaved => 'Spot aktualisiert';

  @override
  String get adminErrInvalidDisplayName =>
      'Ungültiger Anzeigename (1 bis 80 Zeichen, kein @)';

  @override
  String get adminErrInvalidEmail => 'Ungültige E-Mail-Adresse';

  @override
  String get adminErrEmailTaken =>
      'Diese E-Mail-Adresse wird bereits verwendet';

  @override
  String get adminErrCannotDemoteSelf =>
      'Du kannst dir die Admin-Rechte nicht selbst entziehen';

  @override
  String get adminErrLastAdmin => 'Es muss mindestens einen Admin geben';

  @override
  String get adminErrInvalidTitle => 'Ungültiger Titel';

  @override
  String get adminErrInvalidDescription => 'Ungültige Beschreibung';

  @override
  String get adminErrInvalidCategory => 'Ungültige Kategorie';

  @override
  String get adminErrInvalidStatus => 'Ungültiger Status';

  @override
  String get adminErrInvalidLocation => 'Ungültiger Ort';

  @override
  String get adminDismiss => 'Verwerfen';

  @override
  String get adminMoreActions => 'Weitere Aktionen';

  @override
  String get adminDismissAllRestore => 'Alle verwerfen und wiederherstellen';

  @override
  String get adminDismissAllKeep => 'Alle verwerfen (versteckt lassen)';

  @override
  String get adminDismissAllTitle => 'Alle Meldungen verwerfen?';

  @override
  String get adminDismissAllRestoreBody =>
      'Entfernt alle Meldungen zu diesem Inhalt und macht ihn wieder sichtbar.';

  @override
  String get adminDismissAllKeepBody =>
      'Entfernt alle Meldungen zu diesem Inhalt. Versteckte Inhalte bleiben versteckt.';

  @override
  String get adminReportDismissed => 'Meldung verworfen';

  @override
  String adminReportsDismissed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Meldungen verworfen',
      one: '1 Meldung verworfen',
    );
    return '$_temp0';
  }

  @override
  String get adminTargetReview => 'Bewertung';

  @override
  String get adminTargetUpdate => 'Update';

  @override
  String get adminRemoveReview => 'Bewertung entfernen';

  @override
  String get adminRemoveUpdate => 'Update entfernen';

  @override
  String get adminRemoveReviewTitle => 'Bewertung entfernen?';

  @override
  String get adminRemoveUpdateTitle => 'Update entfernen?';

  @override
  String get adminRemoveReviewBody =>
      'Damit wird diese Bewertung endgültig gelöscht.';

  @override
  String get adminRemoveUpdateBody =>
      'Damit wird dieses Update endgültig gelöscht.';

  @override
  String get adminReviewRemoved => 'Bewertung entfernt';

  @override
  String get adminUpdateRemoved => 'Update entfernt';

  @override
  String adminRatingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sterne',
      one: '1 Stern',
    );
    return '$_temp0';
  }

  @override
  String get reviewsTitle => 'Bewertungen';

  @override
  String get reviewNone => 'Noch keine Bewertungen';

  @override
  String get updatesTitle => 'Updates';

  @override
  String get updatesNone => 'Noch keine Updates';

  @override
  String get mapStreets => 'Karte';

  @override
  String get mapSatellite => 'Satellit';

  @override
  String get mapTransit => 'ÖPNV';

  @override
  String get spotCopyLink => 'Link kopieren';

  @override
  String get linkCopied => 'Link kopiert';

  @override
  String get mapRecenter => 'Zurück zum Spot';

  @override
  String reviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bewertungen',
      one: '1 Bewertung',
    );
    return '$_temp0';
  }

  @override
  String get reviewWrite => 'Bewertung schreiben';

  @override
  String get reviewEditMine => 'Deine Bewertung bearbeiten';

  @override
  String get reviewYours => 'Deine Bewertung';

  @override
  String reviewStarLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sterne',
      one: '1 Stern',
    );
    return '$_temp0';
  }

  @override
  String get reviewBodyHint => 'Deine Erfahrung (optional)';

  @override
  String get reviewDeleteTitle => 'Deine Bewertung löschen?';

  @override
  String get reviewDeleteConfirm => 'Löschen';

  @override
  String get reviewEdited => 'bearbeitet';

  @override
  String get reviewLoadMore => 'Mehr laden';

  @override
  String get reviewActionEdit => 'Bewertung bearbeiten';

  @override
  String get reviewActionDelete => 'Bewertung löschen';

  @override
  String get reviewErrorInvalidRating => 'Bitte wähle 1 bis 5 Sterne';

  @override
  String get reviewErrorInvalidBody => 'Der Text ist zu lang';

  @override
  String get reviewErrorOwnSpot =>
      'Du kannst deinen eigenen Spot nicht bewerten';

  @override
  String get updateTagLabel => 'Status';

  @override
  String get updateTagNote => 'Notiz';

  @override
  String get updateTagStillGood => 'Weiterhin gut';

  @override
  String get updateTagCrowded => 'Voll';

  @override
  String get updateTagDirty => 'Dreckig';

  @override
  String get updateTagClosed => 'Gesperrt';

  @override
  String get updateEditTitle => 'Update bearbeiten';

  @override
  String get updateEdited => 'bearbeitet';

  @override
  String get updatePost => 'Posten';

  @override
  String get updateRemovePhoto => 'Foto entfernen';

  @override
  String get updateActionEdit => 'Update bearbeiten';

  @override
  String get updateActionDelete => 'Update löschen';

  @override
  String get updateDeleteTitle => 'Dieses Update löschen?';

  @override
  String get updateDeleteConfirm => 'Löschen';

  @override
  String get updatePhotosReadOnly =>
      'Fotos können nachträglich nicht geändert werden';

  @override
  String get updateErrorInvalidPhoto => 'Eines der Fotos ist ungültig';

  @override
  String get updateErrorInvalidBody => 'Der Text ist ungültig oder zu lang';

  @override
  String get updateErrorInvalidTag => 'Bitte wähle einen gültigen Status';

  @override
  String get photoViewerClose => 'Schließen';

  @override
  String photoViewerPage(int current, int total) {
    return '$current / $total';
  }

  @override
  String get addSpotPhotoUnsupported =>
      'Dieses Bildformat wird nicht unterstützt. Bitte JPEG, PNG, WebP oder AVIF verwenden.';

  @override
  String get addSpotPhotoTooLarge => 'Das Foto ist zu groß (maximal 8 MB).';

  @override
  String get errorNetwork =>
      'Der Server ist nicht erreichbar. Bitte Verbindung prüfen und erneut versuchen.';

  @override
  String errorWithDetail(String message) {
    return 'Etwas ist schiefgelaufen: $message';
  }

  @override
  String get tagsTitle => 'Tags';

  @override
  String get tagsClear => 'Tags zurücksetzen';

  @override
  String get editTags => 'Tags bearbeiten';

  @override
  String get tagsErrForbidden =>
      'Nur der Autor oder ein Admin darf Tags ändern';

  @override
  String get tagsErrInvalid => 'Einer der Tags ist ungültig';

  @override
  String get adminOwner => 'Besitzer';

  @override
  String get adminChangeOwner => 'Besitzer ändern';

  @override
  String get adminPickUser => 'Neuen Besitzer wählen';

  @override
  String get adminLocked => 'Gesperrt';

  @override
  String get adminLockedHint =>
      'Nutzer können keine Updates posten und nichts ändern; Admins schon.';

  @override
  String get adminErrInvalidOwner => 'Diesen Nutzer gibt es nicht';

  @override
  String get spotLockedNotice =>
      'Dieser Spot ist gesperrt. Nur Admins können ihn ändern.';

  @override
  String get adminEditSpotHere => 'Spot bearbeiten (Admin)';

  @override
  String get adminLock => 'Spot sperren';

  @override
  String get adminUnlock => 'Spot entsperren';

  @override
  String get adminSpotLocked => 'Spot gesperrt';

  @override
  String get adminSpotUnlocked => 'Spot entsperrt';

  @override
  String get adminEditUpdate => 'Update bearbeiten (Admin)';

  @override
  String get adminHideUpdate => 'Update ausblenden';

  @override
  String get adminPhotos => 'Fotos';

  @override
  String get adminPhotoRotateLeft => 'Nach links drehen';

  @override
  String get adminPhotoRotateRight => 'Nach rechts drehen';

  @override
  String get adminPhotoRemove => 'Foto entfernen';

  @override
  String get adminPhotoRestore => 'Foto behalten';

  @override
  String get adminUpdateHidden => 'Update ausgeblendet';

  @override
  String get adminTags => 'Tags';

  @override
  String get adminNewTag => 'Neuer Tag';

  @override
  String get adminEditTag => 'Tag bearbeiten';

  @override
  String get adminTagKey => 'Schlüssel (a-z, 0-9, _)';

  @override
  String get adminTagKeyHint =>
      'Wird von App und API benutzt; später nicht änderbar';

  @override
  String get adminTagNameDe => 'Deutscher Name';

  @override
  String get adminTagNameEn => 'Englischer Name';

  @override
  String get adminTagIcon => 'Symbol';

  @override
  String get adminTagMoveUp => 'Nach oben';

  @override
  String get adminTagMoveDown => 'Nach unten';

  @override
  String adminTagSpots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Spots',
      one: '1 Spot',
      zero: 'keine Spots',
    );
    return '$_temp0';
  }

  @override
  String get adminDeleteTag => 'Tag löschen';

  @override
  String adminDeleteTagTitle(String name) {
    return 'Den Tag „$name“ löschen?';
  }

  @override
  String adminDeleteTagBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Er wird von $count Spots entfernt.',
      one: 'Er wird von 1 Spot entfernt.',
      zero: 'Kein Spot benutzt ihn.',
    );
    return '$_temp0';
  }

  @override
  String get adminTagDeleted => 'Tag gelöscht';

  @override
  String get adminTagSaved => 'Tag gespeichert';

  @override
  String get adminErrTagTaken => 'Einen Tag mit diesem Schlüssel gibt es schon';

  @override
  String get adminErrTagKey =>
      '2 bis 16 Zeichen: a-z, 0-9 und _, mit einem Buchstaben am Anfang';

  @override
  String get adminErrTagName => 'Namen müssen 1 bis 40 Zeichen lang sein';

  @override
  String get backToHome => 'Zur Startseite';

  @override
  String get mapMyLocation => 'Mein Standort';

  @override
  String get loginId => 'E-Mail oder Name';

  @override
  String get displayNameHelp => 'Damit kannst du dich auch anmelden; ohne @';

  @override
  String get authErrInvalidCredentials =>
      'Name, E-Mail oder Passwort stimmt nicht';

  @override
  String get authErrNameTaken => 'Dieser Name ist schon vergeben';

  @override
  String get authErrInvalidName =>
      'Der Name muss 1 bis 80 Zeichen lang sein und darf kein @ enthalten';
}
