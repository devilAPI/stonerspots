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
  String get spotShare => 'Teilen';

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
  String get mapSearch => 'Spots suchen';

  @override
  String get mapSearchHint => 'Name eines Spots';

  @override
  String get mapSearchClose => 'Suche schließen';

  @override
  String get mapSearchClear => 'Leeren';

  @override
  String get mapSearchTooShort => 'Mindestens 2 Zeichen eingeben';

  @override
  String get mapSearchNoResult => 'Kein Spot mit diesem Namen gefunden';

  @override
  String get mapSearchError => 'Suche fehlgeschlagen';

  @override
  String get weatherTitle => 'Wetter';

  @override
  String weatherWind(String speed) {
    return 'Wind $speed km/h';
  }

  @override
  String weatherRainChance(int percent) {
    return 'Regen $percent %';
  }

  @override
  String weatherPrecipitation(String amount) {
    return '$amount mm';
  }

  @override
  String get weatherNextHours => 'Nächste Stunden';

  @override
  String get weatherAttribution => 'Wetter: Open-Meteo.com';

  @override
  String get weatherClear => 'Klar';

  @override
  String get weatherMainlyClear => 'Überwiegend klar';

  @override
  String get weatherPartlyCloudy => 'Teils bewölkt';

  @override
  String get weatherOvercast => 'Bedeckt';

  @override
  String get weatherFog => 'Nebel';

  @override
  String get weatherDrizzle => 'Nieselregen';

  @override
  String get weatherFreezingDrizzle => 'Gefrierender Nieselregen';

  @override
  String get weatherRainLight => 'Leichter Regen';

  @override
  String get weatherRain => 'Regen';

  @override
  String get weatherRainHeavy => 'Starker Regen';

  @override
  String get weatherFreezingRain => 'Gefrierender Regen';

  @override
  String get weatherSnowLight => 'Leichter Schneefall';

  @override
  String get weatherSnow => 'Schneefall';

  @override
  String get weatherSnowHeavy => 'Starker Schneefall';

  @override
  String get weatherSnowGrains => 'Schneegriesel';

  @override
  String get weatherShowers => 'Regenschauer';

  @override
  String get weatherShowersHeavy => 'Starke Regenschauer';

  @override
  String get weatherSnowShowers => 'Schneeschauer';

  @override
  String get weatherThunderstorm => 'Gewitter';

  @override
  String get weatherThunderstormHail => 'Gewitter mit Hagel';

  @override
  String get weatherUnknown => 'Unbekannt';

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

  @override
  String get adminActions => 'Aktionen';

  @override
  String adminSelected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get adminSelectAll => 'Alle geladenen auswählen';

  @override
  String get adminClearSelection => 'Auswahl aufheben';

  @override
  String get adminSelect => 'Auswählen';

  @override
  String get adminBan => 'Sperren';

  @override
  String get adminUnban => 'Entsperren';

  @override
  String get adminBanned => 'gesperrt';

  @override
  String get adminDelete => 'Löschen';

  @override
  String get adminHide => 'Verbergen';

  @override
  String get adminShow => 'Anzeigen';

  @override
  String get adminBulkLock => 'Sperren';

  @override
  String get adminBulkUnlock => 'Entsperren';

  @override
  String get adminAddTag => 'Tag hinzufügen';

  @override
  String get adminRemoveTag => 'Tag entfernen';

  @override
  String get adminChooseTag => 'Tag wählen';

  @override
  String adminDeleteUsersTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nutzer löschen?',
      one: '1 Nutzer löschen?',
    );
    return '$_temp0';
  }

  @override
  String get adminDeleteUsersBody =>
      'Die Konten werden mit all ihren Spots, Fotos, Bewertungen und Updates gelöscht. Das lässt sich nicht rückgängig machen.';

  @override
  String adminDeleteSpotsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Spots löschen?',
      one: '1 Spot löschen?',
    );
    return '$_temp0';
  }

  @override
  String get adminDeleteSpotsBody =>
      'Die Spots werden mit allen Fotos, Updates, Bewertungen und Meldungen gelöscht. Das lässt sich nicht rückgängig machen.';

  @override
  String adminBulkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geändert',
      one: '1 geändert',
    );
    return '$_temp0';
  }

  @override
  String adminBulkDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gelöscht',
      one: '1 gelöscht',
    );
    return '$_temp0';
  }

  @override
  String adminBulkSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count übersprungen (du, Admins oder schon weg)',
      one: '1 übersprungen (du, ein Admin oder schon weg)',
    );
    return '$_temp0';
  }

  @override
  String get authErrBanned => 'Dieses Konto ist gesperrt';

  @override
  String get adminBackend => 'Backend';

  @override
  String adminBackendVersion(String version) {
    return 'Installiert: $version';
  }

  @override
  String get adminVersionUnknown =>
      'Version unbekannt (nicht mit install-backend.sh installiert)';

  @override
  String get adminUpdateRelease => 'Backend auf neueste Version';

  @override
  String get adminUpdateDev => 'Backend auf neuesten Dev-Build';

  @override
  String get adminUpdateConfirmTitle => 'Backend aktualisieren?';

  @override
  String get adminUpdateConfirmRelease =>
      'Der Server lädt die neueste Version, installiert sie und startet neu. Die App ist ein paar Sekunden nicht erreichbar.';

  @override
  String get adminUpdateConfirmDev =>
      'Der Server lädt den neuesten Dev-Build (kann instabil sein), installiert ihn und startet neu. Die App ist ein paar Sekunden nicht erreichbar.';

  @override
  String get adminUpdate => 'Aktualisieren';

  @override
  String get adminUpdatesDisabled =>
      'Updates von hier sind auf diesem Server aus. Einmal install-backend.sh auf dem Server ausführen, um sie einzurichten.';

  @override
  String get adminUpdatePending => 'Update angefordert, warte auf den Server…';

  @override
  String get adminUpdateRunning =>
      'Wird aktualisiert… der Server startet am Ende neu';

  @override
  String get adminServerRestarting => 'Server startet neu…';

  @override
  String adminUpdateDone(String from, String to) {
    return 'Aktualisiert: $from → $to';
  }

  @override
  String adminUpdateUpToDate(String version) {
    return 'Schon aktuell ($version)';
  }

  @override
  String get adminUpdateFailed =>
      'Das letzte Update ist fehlgeschlagen; siehe Log';

  @override
  String adminUpdateFinishedAt(String time) {
    return 'Fertig $time';
  }

  @override
  String get adminUpdateLog => 'Log';

  @override
  String get adminUpdateRequestFailed =>
      'Das Update konnte nicht angefordert werden';

  @override
  String get adminEditUpdates => 'Updates bearbeiten';

  @override
  String get adminPickUpdate => 'Welches Update bearbeiten?';

  @override
  String get adminShowUserSpots => 'Spots anzeigen';

  @override
  String adminSpotsOf(String name) {
    return 'Spots von $name';
  }

  @override
  String get adminUpdateSaved => 'Update gespeichert';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsDisableTransparency => 'Transparenz deaktivieren';

  @override
  String get settingsDisableTransparencyHint =>
      'Einfarbige Flächen statt Glas. Schont Grafikleistung und Akku.';

  @override
  String get saved => 'Gespeichert';

  @override
  String get savedFavourites => 'Favoriten';

  @override
  String get savedToFavourites => 'In Favoriten gespeichert';

  @override
  String get savedChangeList => 'Liste ändern';

  @override
  String get savedPickLists => 'In Listen speichern';

  @override
  String get savedNewList => 'Neue Liste';

  @override
  String get savedListName => 'Name der Liste';

  @override
  String get savedRenameList => 'Umbenennen';

  @override
  String get savedDelete => 'Löschen';

  @override
  String get savedDeleteTitle => 'Liste löschen?';

  @override
  String savedDeleteBody(String name) {
    return '„$name“ wird gelöscht. Die Spots darin bleiben erhalten.';
  }

  @override
  String get savedNameTaken => 'Du hast schon eine Liste mit diesem Namen';

  @override
  String get savedListLimit => 'Du hast die maximale Anzahl an Listen erreicht';

  @override
  String get savedEmpty =>
      'Noch nichts gespeichert. Tippe bei einem Spot auf das Lesezeichen, um ihn hier zu sammeln.';

  @override
  String get savedListEmpty => 'Diese Liste ist noch leer';

  @override
  String get savedListGone => 'Diese Liste gibt es nicht mehr';

  @override
  String get savedRemoveSpot => 'Aus der Liste entfernen';

  @override
  String savedSpotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Spots',
      one: '1 Spot',
      zero: 'Keine Spots',
    );
    return '$_temp0';
  }

  @override
  String get feedFollowing => 'Folge ich';

  @override
  String get feedFollowingEmpty =>
      'Noch keine Updates von Leuten, denen du folgst';

  @override
  String get userFollow => 'Folgen';

  @override
  String get userUnfollow => 'Entfolgen';

  @override
  String userJoined(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMM(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Dabei seit $dateString';
  }

  @override
  String get userStatSpots => 'Spots';

  @override
  String get userStatUpdates => 'Updates';

  @override
  String get userStatFollowers => 'Follower';

  @override
  String get userStatFollowing => 'Folgt';

  @override
  String get userTabSpots => 'Spots';

  @override
  String get userTabUpdates => 'Updates';

  @override
  String get userNoSpots => 'Noch keine Spots';

  @override
  String get userNoUpdates => 'Noch keine Updates';

  @override
  String get userGone => 'Dieses Profil gibt es nicht';

  @override
  String get commentsTitle => 'Kommentare';

  @override
  String get commentsEmpty => 'Noch keine Kommentare. Schreib den ersten!';

  @override
  String get commentsLoadMore => 'Weitere Kommentare';

  @override
  String get commentsQuota =>
      'Du hast heute schon sehr viel kommentiert. Versuch es morgen wieder.';

  @override
  String get commentHint => 'Kommentar schreiben …';

  @override
  String get commentSend => 'Senden';

  @override
  String get commentLoginToWrite => 'Zum Kommentieren anmelden';

  @override
  String get commentMore => 'Mehr';

  @override
  String get commentDelete => 'Kommentar löschen';

  @override
  String get commentDeleteTitle => 'Kommentar löschen?';

  @override
  String get commentDeleteConfirm => 'Löschen';

  @override
  String get commentReported => 'Danke, wir schauen uns den Kommentar an';

  @override
  String get adminTargetComment => 'Kommentar';

  @override
  String adminCommentOn(String title) {
    return 'Kommentar zu $title';
  }

  @override
  String get adminRemoveComment => 'Kommentar entfernen';

  @override
  String get adminRemoveCommentTitle => 'Kommentar entfernen?';

  @override
  String get adminRemoveCommentBody =>
      'Damit wird dieser Kommentar endgültig gelöscht.';

  @override
  String get adminCommentRemoved => 'Kommentar entfernt';

  @override
  String get close => 'Schließen';

  @override
  String get activityTitle => 'Aktivität';

  @override
  String activityTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aktivität, $count neu',
      one: 'Aktivität, 1 neu',
      zero: 'Aktivität',
    );
    return '$_temp0';
  }

  @override
  String get activityEmpty =>
      'Noch nichts passiert. Hier siehst du, wenn dir jemand folgt, deine Updates kommentiert oder deine Spots mag oder bewertet.';

  @override
  String activityFollow(String name) {
    return '$name folgt dir jetzt';
  }

  @override
  String activityComment(String name, String spot, String text) {
    return '$name hat dein Update bei $spot kommentiert: $text';
  }

  @override
  String activityLike(String name, String spot) {
    return '$name gefällt $spot';
  }

  @override
  String activityReview(String name, String spot) {
    return '$name hat $spot bewertet';
  }

  @override
  String get settingsAbout => 'Über Stonerspots';

  @override
  String get whatsNewTitle => 'Neu in 2.0';

  @override
  String get whatsNewProfilesTitle => 'Profile und Folgen';

  @override
  String get whatsNewProfilesBody =>
      'Tippe auf einen Namen, um das Profil zu sehen und der Person zu folgen.';

  @override
  String get whatsNewFollowingTitle => 'Feed „Folge ich“';

  @override
  String get whatsNewFollowingBody =>
      'Zeigt im Feed nur Updates von Leuten, denen du folgst.';

  @override
  String get whatsNewCommentsTitle => 'Kommentare';

  @override
  String get whatsNewCommentsBody =>
      'Bei jedem Spot mitreden, im eigenen Bereich für Kommentare.';

  @override
  String get whatsNewActivityTitle => 'Aktivität';

  @override
  String get whatsNewActivityBody =>
      'Die Glocke im Profil zeigt, wer dir folgt, kommentiert, deine Spots mag oder bewertet.';

  @override
  String get whatsNewSearchTitle => 'Spot-Suche';

  @override
  String get whatsNewSearchBody =>
      'Spots auf der Karte nach Namen finden (Strg+K).';

  @override
  String get whatsNewWeatherTitle => 'Wetter';

  @override
  String get whatsNewWeatherBody =>
      'Spot-Seiten zeigen das aktuelle Wetter und die nächsten Stunden.';

  @override
  String get profileAccountMenu => 'Konto';

  @override
  String get spotAddedBy => 'Hinzugefügt von';

  @override
  String get deletedAccount => 'Gelöschtes Konto';

  @override
  String get avatarChange => 'Profilbild ändern';

  @override
  String get avatarChoose => 'Foto auswählen';

  @override
  String get avatarRemove => 'Foto entfernen';

  @override
  String get adminRemoveAvatar => 'Profilbild entfernen';

  @override
  String adminRemoveAvatarBody(String name) {
    return 'Das Profilbild von $name wird gelöscht.';
  }

  @override
  String get adminAvatarRemoved => 'Profilbild entfernt';

  @override
  String get liked => 'Gefällt dir';

  @override
  String commentsShowAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Kommentare anzeigen',
      one: '1 Kommentar anzeigen',
    );
    return '$_temp0';
  }

  @override
  String get commentsShowLess => 'Weniger anzeigen';

  @override
  String get mapNorthUp => 'Nach Norden ausrichten';

  @override
  String activitySpotComment(String name, String spot, String text) {
    return '$name hat deinen Spot $spot kommentiert: $text';
  }

  @override
  String get commentsLocked =>
      'Dieser Spot ist gesperrt, Kommentare sind geschlossen';

  @override
  String get commentsSpotGone => 'Diesen Spot gibt es nicht mehr';

  @override
  String get commentGone => 'Diesen Kommentar gibt es nicht mehr';

  @override
  String updateAvailableTitle(String tag) {
    return 'Update verfügbar ($tag)';
  }

  @override
  String updateInstalledVersion(String version) {
    return 'Installiert: $version';
  }

  @override
  String get updateNow => 'Jetzt aktualisieren';

  @override
  String get updateLater => 'Später';

  @override
  String get updateSkip => 'Diese Version überspringen';

  @override
  String get updateOpenReleasePage => 'Release-Seite öffnen';

  @override
  String get updateNoKeyHint =>
      'Dieser Build kann Updates nicht verifizieren und installiert deshalb nichts selbst. Lade das Update von der Release-Seite.';

  @override
  String get updateNotWritableHint =>
      'Der Ordner der App ist nicht beschreibbar. Lade das Update von der Release-Seite.';

  @override
  String get updatePermissionHint =>
      'Erlaube Stonerspots in den Einstellungen, Apps zu installieren, und tippe dann noch mal auf „Jetzt aktualisieren“.';

  @override
  String get updateOpenSettings => 'Einstellungen öffnen';

  @override
  String updateDownloading(int percent) {
    return 'Wird heruntergeladen … $percent %';
  }

  @override
  String get updateVerifying => 'Signatur und Prüfsumme werden geprüft …';

  @override
  String get updateInstalling => 'Wird installiert …';

  @override
  String get updateHandedOff =>
      'Bestätige die Installation im Dialog des Systems.';

  @override
  String get updateErrorSignature =>
      'Die Signatur des Updates stimmt nicht. Es wurde nichts installiert.';

  @override
  String get updateErrorChecksum =>
      'Die Datei passt nicht zur signierten Prüfsumme. Es wurde nichts installiert.';

  @override
  String get updateErrorMissing =>
      'Dieses Release hat keine Datei für dieses Gerät.';

  @override
  String get updateErrorDownload => 'Download fehlgeschlagen.';

  @override
  String get updateErrorInstall =>
      'Installation fehlgeschlagen. Die bisherige Version bleibt.';

  @override
  String get updateRetry => 'Erneut versuchen';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsAutoUpdate => 'Automatisch nach Updates suchen';

  @override
  String get settingsAutoUpdateHint =>
      'Beim Start, höchstens alle 6 Stunden, bei GitHub.';

  @override
  String get settingsCheckUpdates => 'Nach Updates suchen';

  @override
  String get updateStatusChecking => 'Suche …';

  @override
  String updateStatusUpToDate(String version) {
    return 'Aktuell ($version)';
  }

  @override
  String updateStatusAvailable(String tag) {
    return 'Update verfügbar: $tag';
  }

  @override
  String get updateStatusRateLimited =>
      'GitHub bittet um eine Pause. Versuch es später noch mal.';

  @override
  String get updateStatusOffline => 'GitHub ist gerade nicht erreichbar.';

  @override
  String get settingsNoUpdateChannel =>
      'Dieser Build sucht nicht nach Updates.';

  @override
  String get twoFactorTitle => 'Zwei-Faktor-Anmeldung (2FA)';

  @override
  String get twoFactorOn => 'Aktiv';

  @override
  String get twoFactorOff => 'Aus';

  @override
  String get twoFactorIntro =>
      'Schütze deine Admin-Rechte mit Codes aus einer Authenticator-App (z. B. Aegis, 2FAS oder Google Authenticator).';

  @override
  String get twoFactorEnable => '2FA einrichten';

  @override
  String get twoFactorScan =>
      '1. Scanne den QR-Code mit deiner Authenticator-App oder gib den Schlüssel von Hand ein.';

  @override
  String get twoFactorSecret => 'Schlüssel';

  @override
  String get twoFactorCopy => 'Schlüssel kopieren';

  @override
  String get twoFactorCopied => 'Schlüssel kopiert';

  @override
  String get twoFactorEnterCode =>
      '2. Gib den 6-stelligen Code ein, den die App jetzt zeigt.';

  @override
  String get twoFactorCode => 'Code';

  @override
  String get twoFactorConfirm => 'Bestätigen';

  @override
  String get twoFactorEnabledInfo =>
      '2FA ist jetzt aktiv. Ab sofort fragt die App bei jeder Admin-Aktion nach einem Code. Ein eingegebener Code gilt 15 Minuten lang für alle Admin-Aktionen.';

  @override
  String get twoFactorActiveHint =>
      'Admin-Aktionen brauchen einen Code aus deiner Authenticator-App. Ein eingegebener Code gilt 15 Minuten lang.';

  @override
  String get twoFactorDisable => '2FA ausschalten';

  @override
  String get twoFactorDisableText =>
      'Bestätige mit deinem Passwort und einem aktuellen Code aus der Authenticator-App.';

  @override
  String get twoFactorDisabled => '2FA ist ausgeschaltet.';

  @override
  String get twoFactorErrInvalid => 'Falscher Code. Versuch es noch mal.';

  @override
  String get twoFactorErrReused =>
      'Dieser Code wurde schon benutzt. Warte auf den nächsten.';

  @override
  String get twoFactorErrDigits => 'Der Code hat 6 Ziffern.';

  @override
  String get twoFactorErrRateLimited =>
      'Zu viele Versuche. Warte ein paar Minuten.';

  @override
  String get twoFactorErrNoSecret =>
      'Die Einrichtung ist abgelaufen. Starte sie neu.';

  @override
  String get twoFactorErrAlreadyOn => '2FA ist schon aktiv.';

  @override
  String get twoFactorErrNotOn => '2FA ist nicht aktiv.';

  @override
  String get adminCodeTitle => 'Admin-Bestätigung';

  @override
  String get adminCodePrompt =>
      'Gib den 6-stelligen Code aus deiner Authenticator-App ein. Er gilt dann 15 Minuten lang für alle Admin-Aktionen.';

  @override
  String get adminCodeExpired =>
      'Deine Admin-Sitzung ist abgelaufen. Gib einen neuen Code aus deiner Authenticator-App ein.';
}
