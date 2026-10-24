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
  String get categoryBench => 'Bank';

  @override
  String get categoryRiver => 'Fluss';

  @override
  String get categoryLake => 'See';

  @override
  String get categoryViewpoint => 'Aussichtspunkt';

  @override
  String get categoryForest => 'Wald';

  @override
  String get categoryPark => 'Park';

  @override
  String get categoryOther => 'Sonstiges';

  @override
  String get categoryAll => 'Alle';

  @override
  String get category => 'Kategorie';

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
}
