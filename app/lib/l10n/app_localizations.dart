import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Stonerspots'**
  String get appTitle;

  /// No description provided for @navMap.
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get navMap;

  /// No description provided for @navFeed.
  ///
  /// In de, this message translates to:
  /// **'Feed'**
  String get navFeed;

  /// No description provided for @navProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get navProfile;

  /// No description provided for @mapTitle.
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get mapTitle;

  /// No description provided for @feedTitle.
  ///
  /// In de, this message translates to:
  /// **'Feed'**
  String get feedTitle;

  /// No description provided for @spotDetailTitle.
  ///
  /// In de, this message translates to:
  /// **'Spot'**
  String get spotDetailTitle;

  /// No description provided for @addSpotTitle.
  ///
  /// In de, this message translates to:
  /// **'Spot hinzufügen'**
  String get addSpotTitle;

  /// No description provided for @addSpot.
  ///
  /// In de, this message translates to:
  /// **'Spot hinzufügen'**
  String get addSpot;

  /// No description provided for @login.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get login;

  /// No description provided for @register.
  ///
  /// In de, this message translates to:
  /// **'Registrieren'**
  String get register;

  /// No description provided for @logout.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get logout;

  /// No description provided for @email.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get email;

  /// No description provided for @password.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get password;

  /// No description provided for @displayName.
  ///
  /// In de, this message translates to:
  /// **'Anzeigename'**
  String get displayName;

  /// No description provided for @adultConfirm.
  ///
  /// In de, this message translates to:
  /// **'Ich bin mindestens 18 Jahre alt'**
  String get adultConfirm;

  /// No description provided for @noAccountYet.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Konto? Registrieren'**
  String get noAccountYet;

  /// No description provided for @haveAccount.
  ///
  /// In de, this message translates to:
  /// **'Schon ein Konto? Anmelden'**
  String get haveAccount;

  /// No description provided for @passwordTooShort.
  ///
  /// In de, this message translates to:
  /// **'Mindestens 10 Zeichen'**
  String get passwordTooShort;

  /// No description provided for @fieldRequired.
  ///
  /// In de, this message translates to:
  /// **'Pflichtfeld'**
  String get fieldRequired;

  /// No description provided for @sort.
  ///
  /// In de, this message translates to:
  /// **'Sortieren'**
  String get sort;

  /// No description provided for @sortNew.
  ///
  /// In de, this message translates to:
  /// **'Neu'**
  String get sortNew;

  /// No description provided for @sortTop.
  ///
  /// In de, this message translates to:
  /// **'Top'**
  String get sortTop;

  /// No description provided for @sortNearby.
  ///
  /// In de, this message translates to:
  /// **'In der Nähe'**
  String get sortNearby;

  /// No description provided for @like.
  ///
  /// In de, this message translates to:
  /// **'Gefällt mir'**
  String get like;

  /// No description provided for @report.
  ///
  /// In de, this message translates to:
  /// **'Melden'**
  String get report;

  /// No description provided for @reportReason.
  ///
  /// In de, this message translates to:
  /// **'Grund'**
  String get reportReason;

  /// No description provided for @postUpdate.
  ///
  /// In de, this message translates to:
  /// **'Update posten'**
  String get postUpdate;

  /// No description provided for @openSpot.
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get openSpot;

  /// No description provided for @openInGoogleMaps.
  ///
  /// In de, this message translates to:
  /// **'In Google Maps öffnen'**
  String get openInGoogleMaps;

  /// No description provided for @title.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get title;

  /// No description provided for @description.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get description;

  /// No description provided for @addPhotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos hinzufügen'**
  String get addPhotos;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @duplicateSpot.
  ///
  /// In de, this message translates to:
  /// **'Hier gibt es schon einen Spot – öffnen oder trotzdem hinzufügen'**
  String get duplicateSpot;

  /// No description provided for @addAnyway.
  ///
  /// In de, this message translates to:
  /// **'Trotzdem hinzufügen'**
  String get addAnyway;

  /// No description provided for @loginRequired.
  ///
  /// In de, this message translates to:
  /// **'Bitte melde dich an'**
  String get loginRequired;

  /// No description provided for @errorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen'**
  String get errorGeneric;

  /// No description provided for @retry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get retry;

  /// No description provided for @noResults.
  ///
  /// In de, this message translates to:
  /// **'Nichts gefunden'**
  String get noResults;

  /// No description provided for @locationDenied.
  ///
  /// In de, this message translates to:
  /// **'Standortzugriff verweigert'**
  String get locationDenied;

  /// No description provided for @likesCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Keine Likes} =1{1 Like} other{{count} Likes}}'**
  String likesCount(int count);

  /// No description provided for @feedUpdateCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Update} other{{count} Updates}}'**
  String feedUpdateCount(int count);

  /// No description provided for @changePassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort ändern'**
  String get changePassword;

  /// No description provided for @currentPassword.
  ///
  /// In de, this message translates to:
  /// **'Aktuelles Passwort'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In de, this message translates to:
  /// **'Neues Passwort'**
  String get newPassword;

  /// No description provided for @repeatNewPassword.
  ///
  /// In de, this message translates to:
  /// **'Neues Passwort wiederholen'**
  String get repeatNewPassword;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In de, this message translates to:
  /// **'Passwörter stimmen nicht überein'**
  String get passwordsDontMatch;

  /// No description provided for @passwordTooLong.
  ///
  /// In de, this message translates to:
  /// **'Höchstens 72 Zeichen'**
  String get passwordTooLong;

  /// No description provided for @passwordChanged.
  ///
  /// In de, this message translates to:
  /// **'Passwort geändert'**
  String get passwordChanged;

  /// No description provided for @wrongPassword.
  ///
  /// In de, this message translates to:
  /// **'Falsches Passwort'**
  String get wrongPassword;

  /// No description provided for @deleteAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get deleteAccount;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto sowie alle deine Spots, Updates und Fotos werden dauerhaft gelöscht. Das kann nicht rückgängig gemacht werden. Gib zur Bestätigung dein Passwort ein.'**
  String get deleteAccountWarning;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In de, this message translates to:
  /// **'Endgültig löschen'**
  String get deleteAccountConfirm;

  /// No description provided for @placeSearchHint.
  ///
  /// In de, this message translates to:
  /// **'Adresse oder Koordinaten'**
  String get placeSearchHint;

  /// No description provided for @placeSearchClear.
  ///
  /// In de, this message translates to:
  /// **'Leeren'**
  String get placeSearchClear;

  /// No description provided for @placeSearchGo.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get placeSearchGo;

  /// No description provided for @placeSearchTooShort.
  ///
  /// In de, this message translates to:
  /// **'Bitte mindestens 3 Zeichen eingeben'**
  String get placeSearchTooShort;

  /// No description provided for @placeSearchNoResult.
  ///
  /// In de, this message translates to:
  /// **'Kein Ort gefunden'**
  String get placeSearchNoResult;

  /// No description provided for @placeSearchOutside.
  ///
  /// In de, this message translates to:
  /// **'Diese Koordinaten liegen außerhalb des unterstützten Gebiets (Deutschland, Österreich, Schweiz, Liechtenstein)'**
  String get placeSearchOutside;

  /// No description provided for @placeSearchRateLimited.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Suchanfragen, bitte gleich noch einmal versuchen'**
  String get placeSearchRateLimited;

  /// No description provided for @placeSearchUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Die Adresssuche ist gerade nicht verfügbar, bitte später erneut versuchen'**
  String get placeSearchUnavailable;

  /// No description provided for @placeSearchError.
  ///
  /// In de, this message translates to:
  /// **'Suche fehlgeschlagen, bitte erneut versuchen'**
  String get placeSearchError;

  /// No description provided for @placeSearchShortLink.
  ///
  /// In de, this message translates to:
  /// **'Kurzlinks können nicht aufgelöst werden. Bitte den vollständigen Link oder die Koordinaten einfügen.'**
  String get placeSearchShortLink;

  /// No description provided for @adminOpen.
  ///
  /// In de, this message translates to:
  /// **'Admin'**
  String get adminOpen;

  /// No description provided for @adminTitle.
  ///
  /// In de, this message translates to:
  /// **'Admin'**
  String get adminTitle;

  /// No description provided for @adminReports.
  ///
  /// In de, this message translates to:
  /// **'Meldungen'**
  String get adminReports;

  /// No description provided for @adminUsers.
  ///
  /// In de, this message translates to:
  /// **'Nutzer'**
  String get adminUsers;

  /// No description provided for @adminSpots.
  ///
  /// In de, this message translates to:
  /// **'Spots'**
  String get adminSpots;

  /// No description provided for @adminReportCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Meldung} other{{count} Meldungen}}'**
  String adminReportCount(int count);

  /// No description provided for @adminReportedBy.
  ///
  /// In de, this message translates to:
  /// **'Gemeldet von {name} ({email})'**
  String adminReportedBy(String name, String email);

  /// No description provided for @adminTargetDeleted.
  ///
  /// In de, this message translates to:
  /// **'Gelöscht'**
  String get adminTargetDeleted;

  /// No description provided for @adminUpdateOn.
  ///
  /// In de, this message translates to:
  /// **'Update zu {title}'**
  String adminUpdateOn(String title);

  /// No description provided for @statusActive.
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get statusActive;

  /// No description provided for @statusHidden.
  ///
  /// In de, this message translates to:
  /// **'Versteckt'**
  String get statusHidden;

  /// No description provided for @statusLocked.
  ///
  /// In de, this message translates to:
  /// **'Gesperrt'**
  String get statusLocked;

  /// No description provided for @statusAll.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get statusAll;

  /// No description provided for @adminOpenSpot.
  ///
  /// In de, this message translates to:
  /// **'Spot öffnen'**
  String get adminOpenSpot;

  /// No description provided for @adminRemoveSpot.
  ///
  /// In de, this message translates to:
  /// **'Spot entfernen'**
  String get adminRemoveSpot;

  /// No description provided for @adminRemove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get adminRemove;

  /// No description provided for @adminSearchUsers.
  ///
  /// In de, this message translates to:
  /// **'Name oder E-Mail suchen'**
  String get adminSearchUsers;

  /// No description provided for @adminSearchSpots.
  ///
  /// In de, this message translates to:
  /// **'Titel suchen'**
  String get adminSearchSpots;

  /// No description provided for @adminBadge.
  ///
  /// In de, this message translates to:
  /// **'admin'**
  String get adminBadge;

  /// No description provided for @adminUserSpots.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Spot} other{{count} Spots}}'**
  String adminUserSpots(int count);

  /// No description provided for @adminUserReports.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Meldung erhalten} other{{count} Meldungen erhalten}}'**
  String adminUserReports(int count);

  /// No description provided for @adminJoined.
  ///
  /// In de, this message translates to:
  /// **'Beigetreten {date}'**
  String adminJoined(String date);

  /// No description provided for @adminSpotAuthor.
  ///
  /// In de, this message translates to:
  /// **'von {name}'**
  String adminSpotAuthor(String name);

  /// No description provided for @adminRemoveTitle.
  ///
  /// In de, this message translates to:
  /// **'Spot entfernen?'**
  String get adminRemoveTitle;

  /// No description provided for @adminRemoveBody.
  ///
  /// In de, this message translates to:
  /// **'„{title}“ wird mit allen Updates, Likes und Fotos endgültig gelöscht.'**
  String adminRemoveBody(String title);

  /// No description provided for @adminSpotRemoved.
  ///
  /// In de, this message translates to:
  /// **'Spot entfernt'**
  String get adminSpotRemoved;

  /// No description provided for @adminEdit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get adminEdit;

  /// No description provided for @adminEditUser.
  ///
  /// In de, this message translates to:
  /// **'Nutzer bearbeiten'**
  String get adminEditUser;

  /// No description provided for @adminEditSpot.
  ///
  /// In de, this message translates to:
  /// **'Spot bearbeiten'**
  String get adminEditSpot;

  /// No description provided for @adminIsAdmin.
  ///
  /// In de, this message translates to:
  /// **'Admin'**
  String get adminIsAdmin;

  /// No description provided for @adminSelfAdminHint.
  ///
  /// In de, this message translates to:
  /// **'Du kannst deinen eigenen Admin-Status nicht ändern.'**
  String get adminSelfAdminHint;

  /// No description provided for @adminStatus.
  ///
  /// In de, this message translates to:
  /// **'Status'**
  String get adminStatus;

  /// No description provided for @adminCoordinates.
  ///
  /// In de, this message translates to:
  /// **'Koordinaten (Breite, Länge)'**
  String get adminCoordinates;

  /// No description provided for @adminCoordsInvalid.
  ///
  /// In de, this message translates to:
  /// **'Diese Koordinaten konnten nicht gelesen werden. Nutze z. B. 48.137, 11.575 oder einen Kartenlink.'**
  String get adminCoordsInvalid;

  /// No description provided for @adminUserSaved.
  ///
  /// In de, this message translates to:
  /// **'Nutzer aktualisiert'**
  String get adminUserSaved;

  /// No description provided for @adminSpotSaved.
  ///
  /// In de, this message translates to:
  /// **'Spot aktualisiert'**
  String get adminSpotSaved;

  /// No description provided for @adminErrInvalidDisplayName.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Anzeigename (1 bis 80 Zeichen, kein @)'**
  String get adminErrInvalidDisplayName;

  /// No description provided for @adminErrInvalidEmail.
  ///
  /// In de, this message translates to:
  /// **'Ungültige E-Mail-Adresse'**
  String get adminErrInvalidEmail;

  /// No description provided for @adminErrEmailTaken.
  ///
  /// In de, this message translates to:
  /// **'Diese E-Mail-Adresse wird bereits verwendet'**
  String get adminErrEmailTaken;

  /// No description provided for @adminErrCannotDemoteSelf.
  ///
  /// In de, this message translates to:
  /// **'Du kannst dir die Admin-Rechte nicht selbst entziehen'**
  String get adminErrCannotDemoteSelf;

  /// No description provided for @adminErrLastAdmin.
  ///
  /// In de, this message translates to:
  /// **'Es muss mindestens einen Admin geben'**
  String get adminErrLastAdmin;

  /// No description provided for @adminErrInvalidTitle.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Titel'**
  String get adminErrInvalidTitle;

  /// No description provided for @adminErrInvalidDescription.
  ///
  /// In de, this message translates to:
  /// **'Ungültige Beschreibung'**
  String get adminErrInvalidDescription;

  /// No description provided for @adminErrInvalidCategory.
  ///
  /// In de, this message translates to:
  /// **'Ungültige Kategorie'**
  String get adminErrInvalidCategory;

  /// No description provided for @adminErrInvalidStatus.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Status'**
  String get adminErrInvalidStatus;

  /// No description provided for @adminErrInvalidLocation.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Ort'**
  String get adminErrInvalidLocation;

  /// No description provided for @adminDismiss.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get adminDismiss;

  /// No description provided for @adminMoreActions.
  ///
  /// In de, this message translates to:
  /// **'Weitere Aktionen'**
  String get adminMoreActions;

  /// No description provided for @adminDismissAllRestore.
  ///
  /// In de, this message translates to:
  /// **'Alle verwerfen und wiederherstellen'**
  String get adminDismissAllRestore;

  /// No description provided for @adminDismissAllKeep.
  ///
  /// In de, this message translates to:
  /// **'Alle verwerfen (versteckt lassen)'**
  String get adminDismissAllKeep;

  /// No description provided for @adminDismissAllTitle.
  ///
  /// In de, this message translates to:
  /// **'Alle Meldungen verwerfen?'**
  String get adminDismissAllTitle;

  /// No description provided for @adminDismissAllRestoreBody.
  ///
  /// In de, this message translates to:
  /// **'Entfernt alle Meldungen zu diesem Inhalt und macht ihn wieder sichtbar.'**
  String get adminDismissAllRestoreBody;

  /// No description provided for @adminDismissAllKeepBody.
  ///
  /// In de, this message translates to:
  /// **'Entfernt alle Meldungen zu diesem Inhalt. Versteckte Inhalte bleiben versteckt.'**
  String get adminDismissAllKeepBody;

  /// No description provided for @adminReportDismissed.
  ///
  /// In de, this message translates to:
  /// **'Meldung verworfen'**
  String get adminReportDismissed;

  /// No description provided for @adminReportsDismissed.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Meldung verworfen} other{{count} Meldungen verworfen}}'**
  String adminReportsDismissed(int count);

  /// No description provided for @adminTargetReview.
  ///
  /// In de, this message translates to:
  /// **'Bewertung'**
  String get adminTargetReview;

  /// No description provided for @adminTargetUpdate.
  ///
  /// In de, this message translates to:
  /// **'Update'**
  String get adminTargetUpdate;

  /// No description provided for @adminRemoveReview.
  ///
  /// In de, this message translates to:
  /// **'Bewertung entfernen'**
  String get adminRemoveReview;

  /// No description provided for @adminRemoveUpdate.
  ///
  /// In de, this message translates to:
  /// **'Update entfernen'**
  String get adminRemoveUpdate;

  /// No description provided for @adminRemoveReviewTitle.
  ///
  /// In de, this message translates to:
  /// **'Bewertung entfernen?'**
  String get adminRemoveReviewTitle;

  /// No description provided for @adminRemoveUpdateTitle.
  ///
  /// In de, this message translates to:
  /// **'Update entfernen?'**
  String get adminRemoveUpdateTitle;

  /// No description provided for @adminRemoveReviewBody.
  ///
  /// In de, this message translates to:
  /// **'Damit wird diese Bewertung endgültig gelöscht.'**
  String get adminRemoveReviewBody;

  /// No description provided for @adminRemoveUpdateBody.
  ///
  /// In de, this message translates to:
  /// **'Damit wird dieses Update endgültig gelöscht.'**
  String get adminRemoveUpdateBody;

  /// No description provided for @adminReviewRemoved.
  ///
  /// In de, this message translates to:
  /// **'Bewertung entfernt'**
  String get adminReviewRemoved;

  /// No description provided for @adminUpdateRemoved.
  ///
  /// In de, this message translates to:
  /// **'Update entfernt'**
  String get adminUpdateRemoved;

  /// No description provided for @adminRatingStars.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Stern} other{{count} Sterne}}'**
  String adminRatingStars(int count);

  /// No description provided for @reviewsTitle.
  ///
  /// In de, this message translates to:
  /// **'Bewertungen'**
  String get reviewsTitle;

  /// No description provided for @reviewNone.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Bewertungen'**
  String get reviewNone;

  /// No description provided for @updatesTitle.
  ///
  /// In de, this message translates to:
  /// **'Updates'**
  String get updatesTitle;

  /// No description provided for @updatesNone.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Updates'**
  String get updatesNone;

  /// No description provided for @mapStreets.
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get mapStreets;

  /// No description provided for @mapSatellite.
  ///
  /// In de, this message translates to:
  /// **'Satellit'**
  String get mapSatellite;

  /// No description provided for @mapTransit.
  ///
  /// In de, this message translates to:
  /// **'ÖPNV'**
  String get mapTransit;

  /// No description provided for @spotShare.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get spotShare;

  /// No description provided for @linkCopied.
  ///
  /// In de, this message translates to:
  /// **'Link kopiert'**
  String get linkCopied;

  /// No description provided for @mapRecenter.
  ///
  /// In de, this message translates to:
  /// **'Zurück zum Spot'**
  String get mapRecenter;

  /// No description provided for @reviewCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Bewertung} other{{count} Bewertungen}}'**
  String reviewCount(int count);

  /// No description provided for @reviewWrite.
  ///
  /// In de, this message translates to:
  /// **'Bewertung schreiben'**
  String get reviewWrite;

  /// No description provided for @reviewEditMine.
  ///
  /// In de, this message translates to:
  /// **'Deine Bewertung bearbeiten'**
  String get reviewEditMine;

  /// No description provided for @reviewYours.
  ///
  /// In de, this message translates to:
  /// **'Deine Bewertung'**
  String get reviewYours;

  /// No description provided for @reviewStarLabel.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Stern} other{{count} Sterne}}'**
  String reviewStarLabel(int count);

  /// No description provided for @reviewBodyHint.
  ///
  /// In de, this message translates to:
  /// **'Deine Erfahrung (optional)'**
  String get reviewBodyHint;

  /// No description provided for @reviewDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Deine Bewertung löschen?'**
  String get reviewDeleteTitle;

  /// No description provided for @reviewDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get reviewDeleteConfirm;

  /// No description provided for @reviewEdited.
  ///
  /// In de, this message translates to:
  /// **'bearbeitet'**
  String get reviewEdited;

  /// No description provided for @reviewLoadMore.
  ///
  /// In de, this message translates to:
  /// **'Mehr laden'**
  String get reviewLoadMore;

  /// No description provided for @reviewActionEdit.
  ///
  /// In de, this message translates to:
  /// **'Bewertung bearbeiten'**
  String get reviewActionEdit;

  /// No description provided for @reviewActionDelete.
  ///
  /// In de, this message translates to:
  /// **'Bewertung löschen'**
  String get reviewActionDelete;

  /// No description provided for @reviewErrorInvalidRating.
  ///
  /// In de, this message translates to:
  /// **'Bitte wähle 1 bis 5 Sterne'**
  String get reviewErrorInvalidRating;

  /// No description provided for @reviewErrorInvalidBody.
  ///
  /// In de, this message translates to:
  /// **'Der Text ist zu lang'**
  String get reviewErrorInvalidBody;

  /// No description provided for @reviewErrorOwnSpot.
  ///
  /// In de, this message translates to:
  /// **'Du kannst deinen eigenen Spot nicht bewerten'**
  String get reviewErrorOwnSpot;

  /// No description provided for @updateTagLabel.
  ///
  /// In de, this message translates to:
  /// **'Status'**
  String get updateTagLabel;

  /// No description provided for @updateTagNote.
  ///
  /// In de, this message translates to:
  /// **'Notiz'**
  String get updateTagNote;

  /// No description provided for @updateTagStillGood.
  ///
  /// In de, this message translates to:
  /// **'Weiterhin gut'**
  String get updateTagStillGood;

  /// No description provided for @updateTagCrowded.
  ///
  /// In de, this message translates to:
  /// **'Voll'**
  String get updateTagCrowded;

  /// No description provided for @updateTagDirty.
  ///
  /// In de, this message translates to:
  /// **'Dreckig'**
  String get updateTagDirty;

  /// No description provided for @updateTagClosed.
  ///
  /// In de, this message translates to:
  /// **'Gesperrt'**
  String get updateTagClosed;

  /// No description provided for @updateEditTitle.
  ///
  /// In de, this message translates to:
  /// **'Update bearbeiten'**
  String get updateEditTitle;

  /// No description provided for @updateEdited.
  ///
  /// In de, this message translates to:
  /// **'bearbeitet'**
  String get updateEdited;

  /// No description provided for @updatePost.
  ///
  /// In de, this message translates to:
  /// **'Posten'**
  String get updatePost;

  /// No description provided for @updateRemovePhoto.
  ///
  /// In de, this message translates to:
  /// **'Foto entfernen'**
  String get updateRemovePhoto;

  /// No description provided for @updateActionEdit.
  ///
  /// In de, this message translates to:
  /// **'Update bearbeiten'**
  String get updateActionEdit;

  /// No description provided for @updateActionDelete.
  ///
  /// In de, this message translates to:
  /// **'Update löschen'**
  String get updateActionDelete;

  /// No description provided for @updateDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Dieses Update löschen?'**
  String get updateDeleteTitle;

  /// No description provided for @updateDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get updateDeleteConfirm;

  /// No description provided for @updatePhotosReadOnly.
  ///
  /// In de, this message translates to:
  /// **'Fotos können nachträglich nicht geändert werden'**
  String get updatePhotosReadOnly;

  /// No description provided for @updateErrorInvalidPhoto.
  ///
  /// In de, this message translates to:
  /// **'Eines der Fotos ist ungültig'**
  String get updateErrorInvalidPhoto;

  /// No description provided for @updateErrorInvalidBody.
  ///
  /// In de, this message translates to:
  /// **'Der Text ist ungültig oder zu lang'**
  String get updateErrorInvalidBody;

  /// No description provided for @updateErrorInvalidTag.
  ///
  /// In de, this message translates to:
  /// **'Bitte wähle einen gültigen Status'**
  String get updateErrorInvalidTag;

  /// No description provided for @photoViewerClose.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get photoViewerClose;

  /// No description provided for @photoViewerPage.
  ///
  /// In de, this message translates to:
  /// **'{current} / {total}'**
  String photoViewerPage(int current, int total);

  /// No description provided for @addSpotPhotoUnsupported.
  ///
  /// In de, this message translates to:
  /// **'Dieses Bildformat wird nicht unterstützt. Bitte JPEG, PNG, WebP oder AVIF verwenden.'**
  String get addSpotPhotoUnsupported;

  /// No description provided for @addSpotPhotoTooLarge.
  ///
  /// In de, this message translates to:
  /// **'Das Foto ist zu groß (maximal 8 MB).'**
  String get addSpotPhotoTooLarge;

  /// No description provided for @errorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Der Server ist nicht erreichbar. Bitte Verbindung prüfen und erneut versuchen.'**
  String get errorNetwork;

  /// No description provided for @errorWithDetail.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen: {message}'**
  String errorWithDetail(String message);

  /// No description provided for @tagsTitle.
  ///
  /// In de, this message translates to:
  /// **'Tags'**
  String get tagsTitle;

  /// No description provided for @tagsClear.
  ///
  /// In de, this message translates to:
  /// **'Tags zurücksetzen'**
  String get tagsClear;

  /// No description provided for @editTags.
  ///
  /// In de, this message translates to:
  /// **'Tags bearbeiten'**
  String get editTags;

  /// No description provided for @tagsErrForbidden.
  ///
  /// In de, this message translates to:
  /// **'Nur der Autor oder ein Admin darf Tags ändern'**
  String get tagsErrForbidden;

  /// No description provided for @tagsErrInvalid.
  ///
  /// In de, this message translates to:
  /// **'Einer der Tags ist ungültig'**
  String get tagsErrInvalid;

  /// No description provided for @adminOwner.
  ///
  /// In de, this message translates to:
  /// **'Besitzer'**
  String get adminOwner;

  /// No description provided for @adminChangeOwner.
  ///
  /// In de, this message translates to:
  /// **'Besitzer ändern'**
  String get adminChangeOwner;

  /// No description provided for @adminPickUser.
  ///
  /// In de, this message translates to:
  /// **'Neuen Besitzer wählen'**
  String get adminPickUser;

  /// No description provided for @adminLocked.
  ///
  /// In de, this message translates to:
  /// **'Gesperrt'**
  String get adminLocked;

  /// No description provided for @adminLockedHint.
  ///
  /// In de, this message translates to:
  /// **'Nutzer können keine Updates posten und nichts ändern; Admins schon.'**
  String get adminLockedHint;

  /// No description provided for @adminErrInvalidOwner.
  ///
  /// In de, this message translates to:
  /// **'Diesen Nutzer gibt es nicht'**
  String get adminErrInvalidOwner;

  /// No description provided for @spotLockedNotice.
  ///
  /// In de, this message translates to:
  /// **'Dieser Spot ist gesperrt. Nur Admins können ihn ändern.'**
  String get spotLockedNotice;

  /// No description provided for @adminEditSpotHere.
  ///
  /// In de, this message translates to:
  /// **'Spot bearbeiten (Admin)'**
  String get adminEditSpotHere;

  /// No description provided for @adminLock.
  ///
  /// In de, this message translates to:
  /// **'Spot sperren'**
  String get adminLock;

  /// No description provided for @adminUnlock.
  ///
  /// In de, this message translates to:
  /// **'Spot entsperren'**
  String get adminUnlock;

  /// No description provided for @adminSpotLocked.
  ///
  /// In de, this message translates to:
  /// **'Spot gesperrt'**
  String get adminSpotLocked;

  /// No description provided for @adminSpotUnlocked.
  ///
  /// In de, this message translates to:
  /// **'Spot entsperrt'**
  String get adminSpotUnlocked;

  /// No description provided for @adminEditUpdate.
  ///
  /// In de, this message translates to:
  /// **'Update bearbeiten (Admin)'**
  String get adminEditUpdate;

  /// No description provided for @adminHideUpdate.
  ///
  /// In de, this message translates to:
  /// **'Update ausblenden'**
  String get adminHideUpdate;

  /// No description provided for @adminPhotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get adminPhotos;

  /// No description provided for @adminPhotoRotateLeft.
  ///
  /// In de, this message translates to:
  /// **'Nach links drehen'**
  String get adminPhotoRotateLeft;

  /// No description provided for @adminPhotoRotateRight.
  ///
  /// In de, this message translates to:
  /// **'Nach rechts drehen'**
  String get adminPhotoRotateRight;

  /// No description provided for @adminPhotoRemove.
  ///
  /// In de, this message translates to:
  /// **'Foto entfernen'**
  String get adminPhotoRemove;

  /// No description provided for @adminPhotoRestore.
  ///
  /// In de, this message translates to:
  /// **'Foto behalten'**
  String get adminPhotoRestore;

  /// No description provided for @adminUpdateHidden.
  ///
  /// In de, this message translates to:
  /// **'Update ausgeblendet'**
  String get adminUpdateHidden;

  /// No description provided for @adminTags.
  ///
  /// In de, this message translates to:
  /// **'Tags'**
  String get adminTags;

  /// No description provided for @adminNewTag.
  ///
  /// In de, this message translates to:
  /// **'Neuer Tag'**
  String get adminNewTag;

  /// No description provided for @adminEditTag.
  ///
  /// In de, this message translates to:
  /// **'Tag bearbeiten'**
  String get adminEditTag;

  /// No description provided for @adminTagKey.
  ///
  /// In de, this message translates to:
  /// **'Schlüssel (a-z, 0-9, _)'**
  String get adminTagKey;

  /// No description provided for @adminTagKeyHint.
  ///
  /// In de, this message translates to:
  /// **'Wird von App und API benutzt; später nicht änderbar'**
  String get adminTagKeyHint;

  /// No description provided for @adminTagNameDe.
  ///
  /// In de, this message translates to:
  /// **'Deutscher Name'**
  String get adminTagNameDe;

  /// No description provided for @adminTagNameEn.
  ///
  /// In de, this message translates to:
  /// **'Englischer Name'**
  String get adminTagNameEn;

  /// No description provided for @adminTagIcon.
  ///
  /// In de, this message translates to:
  /// **'Symbol'**
  String get adminTagIcon;

  /// No description provided for @adminTagMoveUp.
  ///
  /// In de, this message translates to:
  /// **'Nach oben'**
  String get adminTagMoveUp;

  /// No description provided for @adminTagMoveDown.
  ///
  /// In de, this message translates to:
  /// **'Nach unten'**
  String get adminTagMoveDown;

  /// No description provided for @adminTagSpots.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{keine Spots} =1{1 Spot} other{{count} Spots}}'**
  String adminTagSpots(int count);

  /// No description provided for @adminDeleteTag.
  ///
  /// In de, this message translates to:
  /// **'Tag löschen'**
  String get adminDeleteTag;

  /// No description provided for @adminDeleteTagTitle.
  ///
  /// In de, this message translates to:
  /// **'Den Tag „{name}“ löschen?'**
  String adminDeleteTagTitle(String name);

  /// No description provided for @adminDeleteTagBody.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Kein Spot benutzt ihn.} =1{Er wird von 1 Spot entfernt.} other{Er wird von {count} Spots entfernt.}}'**
  String adminDeleteTagBody(int count);

  /// No description provided for @adminTagDeleted.
  ///
  /// In de, this message translates to:
  /// **'Tag gelöscht'**
  String get adminTagDeleted;

  /// No description provided for @adminTagSaved.
  ///
  /// In de, this message translates to:
  /// **'Tag gespeichert'**
  String get adminTagSaved;

  /// No description provided for @adminErrTagTaken.
  ///
  /// In de, this message translates to:
  /// **'Einen Tag mit diesem Schlüssel gibt es schon'**
  String get adminErrTagTaken;

  /// No description provided for @adminErrTagKey.
  ///
  /// In de, this message translates to:
  /// **'2 bis 16 Zeichen: a-z, 0-9 und _, mit einem Buchstaben am Anfang'**
  String get adminErrTagKey;

  /// No description provided for @adminErrTagName.
  ///
  /// In de, this message translates to:
  /// **'Namen müssen 1 bis 40 Zeichen lang sein'**
  String get adminErrTagName;

  /// No description provided for @backToHome.
  ///
  /// In de, this message translates to:
  /// **'Zur Startseite'**
  String get backToHome;

  /// No description provided for @mapMyLocation.
  ///
  /// In de, this message translates to:
  /// **'Mein Standort'**
  String get mapMyLocation;

  /// No description provided for @loginId.
  ///
  /// In de, this message translates to:
  /// **'E-Mail oder Name'**
  String get loginId;

  /// No description provided for @displayNameHelp.
  ///
  /// In de, this message translates to:
  /// **'Damit kannst du dich auch anmelden; ohne @'**
  String get displayNameHelp;

  /// No description provided for @authErrInvalidCredentials.
  ///
  /// In de, this message translates to:
  /// **'Name, E-Mail oder Passwort stimmt nicht'**
  String get authErrInvalidCredentials;

  /// No description provided for @authErrNameTaken.
  ///
  /// In de, this message translates to:
  /// **'Dieser Name ist schon vergeben'**
  String get authErrNameTaken;

  /// No description provided for @authErrInvalidName.
  ///
  /// In de, this message translates to:
  /// **'Der Name muss 1 bis 80 Zeichen lang sein und darf kein @ enthalten'**
  String get authErrInvalidName;

  /// No description provided for @adminActions.
  ///
  /// In de, this message translates to:
  /// **'Aktionen'**
  String get adminActions;

  /// No description provided for @adminSelected.
  ///
  /// In de, this message translates to:
  /// **'{count} ausgewählt'**
  String adminSelected(int count);

  /// No description provided for @adminSelectAll.
  ///
  /// In de, this message translates to:
  /// **'Alle geladenen auswählen'**
  String get adminSelectAll;

  /// No description provided for @adminClearSelection.
  ///
  /// In de, this message translates to:
  /// **'Auswahl aufheben'**
  String get adminClearSelection;

  /// No description provided for @adminSelect.
  ///
  /// In de, this message translates to:
  /// **'Auswählen'**
  String get adminSelect;

  /// No description provided for @adminBan.
  ///
  /// In de, this message translates to:
  /// **'Sperren'**
  String get adminBan;

  /// No description provided for @adminUnban.
  ///
  /// In de, this message translates to:
  /// **'Entsperren'**
  String get adminUnban;

  /// No description provided for @adminBanned.
  ///
  /// In de, this message translates to:
  /// **'gesperrt'**
  String get adminBanned;

  /// No description provided for @adminDelete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get adminDelete;

  /// No description provided for @adminHide.
  ///
  /// In de, this message translates to:
  /// **'Verbergen'**
  String get adminHide;

  /// No description provided for @adminShow.
  ///
  /// In de, this message translates to:
  /// **'Anzeigen'**
  String get adminShow;

  /// No description provided for @adminBulkLock.
  ///
  /// In de, this message translates to:
  /// **'Sperren'**
  String get adminBulkLock;

  /// No description provided for @adminBulkUnlock.
  ///
  /// In de, this message translates to:
  /// **'Entsperren'**
  String get adminBulkUnlock;

  /// No description provided for @adminAddTag.
  ///
  /// In de, this message translates to:
  /// **'Tag hinzufügen'**
  String get adminAddTag;

  /// No description provided for @adminRemoveTag.
  ///
  /// In de, this message translates to:
  /// **'Tag entfernen'**
  String get adminRemoveTag;

  /// No description provided for @adminChooseTag.
  ///
  /// In de, this message translates to:
  /// **'Tag wählen'**
  String get adminChooseTag;

  /// No description provided for @adminDeleteUsersTitle.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Nutzer löschen?} other{{count} Nutzer löschen?}}'**
  String adminDeleteUsersTitle(int count);

  /// No description provided for @adminDeleteUsersBody.
  ///
  /// In de, this message translates to:
  /// **'Die Konten werden mit all ihren Spots, Fotos, Bewertungen und Updates gelöscht. Das lässt sich nicht rückgängig machen.'**
  String get adminDeleteUsersBody;

  /// No description provided for @adminDeleteSpotsTitle.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Spot löschen?} other{{count} Spots löschen?}}'**
  String adminDeleteSpotsTitle(int count);

  /// No description provided for @adminDeleteSpotsBody.
  ///
  /// In de, this message translates to:
  /// **'Die Spots werden mit allen Fotos, Updates, Bewertungen und Meldungen gelöscht. Das lässt sich nicht rückgängig machen.'**
  String get adminDeleteSpotsBody;

  /// No description provided for @adminBulkDone.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 geändert} other{{count} geändert}}'**
  String adminBulkDone(int count);

  /// No description provided for @adminBulkDeleted.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 gelöscht} other{{count} gelöscht}}'**
  String adminBulkDeleted(int count);

  /// No description provided for @adminBulkSkipped.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 übersprungen (du, ein Admin oder schon weg)} other{{count} übersprungen (du, Admins oder schon weg)}}'**
  String adminBulkSkipped(int count);

  /// No description provided for @authErrBanned.
  ///
  /// In de, this message translates to:
  /// **'Dieses Konto ist gesperrt'**
  String get authErrBanned;

  /// No description provided for @adminBackend.
  ///
  /// In de, this message translates to:
  /// **'Backend'**
  String get adminBackend;

  /// No description provided for @adminBackendVersion.
  ///
  /// In de, this message translates to:
  /// **'Installiert: {version}'**
  String adminBackendVersion(String version);

  /// No description provided for @adminVersionUnknown.
  ///
  /// In de, this message translates to:
  /// **'Version unbekannt (nicht mit install-backend.sh installiert)'**
  String get adminVersionUnknown;

  /// No description provided for @adminUpdateRelease.
  ///
  /// In de, this message translates to:
  /// **'Backend auf neueste Version'**
  String get adminUpdateRelease;

  /// No description provided for @adminUpdateDev.
  ///
  /// In de, this message translates to:
  /// **'Backend auf neuesten Dev-Build'**
  String get adminUpdateDev;

  /// No description provided for @adminUpdateConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Backend aktualisieren?'**
  String get adminUpdateConfirmTitle;

  /// No description provided for @adminUpdateConfirmRelease.
  ///
  /// In de, this message translates to:
  /// **'Der Server lädt die neueste Version, installiert sie und startet neu. Die App ist ein paar Sekunden nicht erreichbar.'**
  String get adminUpdateConfirmRelease;

  /// No description provided for @adminUpdateConfirmDev.
  ///
  /// In de, this message translates to:
  /// **'Der Server lädt den neuesten Dev-Build (kann instabil sein), installiert ihn und startet neu. Die App ist ein paar Sekunden nicht erreichbar.'**
  String get adminUpdateConfirmDev;

  /// No description provided for @adminUpdate.
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get adminUpdate;

  /// No description provided for @adminUpdatesDisabled.
  ///
  /// In de, this message translates to:
  /// **'Updates von hier sind auf diesem Server aus. Einmal install-backend.sh auf dem Server ausführen, um sie einzurichten.'**
  String get adminUpdatesDisabled;

  /// No description provided for @adminUpdatePending.
  ///
  /// In de, this message translates to:
  /// **'Update angefordert, warte auf den Server…'**
  String get adminUpdatePending;

  /// No description provided for @adminUpdateRunning.
  ///
  /// In de, this message translates to:
  /// **'Wird aktualisiert… der Server startet am Ende neu'**
  String get adminUpdateRunning;

  /// No description provided for @adminServerRestarting.
  ///
  /// In de, this message translates to:
  /// **'Server startet neu…'**
  String get adminServerRestarting;

  /// No description provided for @adminUpdateDone.
  ///
  /// In de, this message translates to:
  /// **'Aktualisiert: {from} → {to}'**
  String adminUpdateDone(String from, String to);

  /// No description provided for @adminUpdateUpToDate.
  ///
  /// In de, this message translates to:
  /// **'Schon aktuell ({version})'**
  String adminUpdateUpToDate(String version);

  /// No description provided for @adminUpdateFailed.
  ///
  /// In de, this message translates to:
  /// **'Das letzte Update ist fehlgeschlagen; siehe Log'**
  String get adminUpdateFailed;

  /// No description provided for @adminUpdateFinishedAt.
  ///
  /// In de, this message translates to:
  /// **'Fertig {time}'**
  String adminUpdateFinishedAt(String time);

  /// No description provided for @adminUpdateLog.
  ///
  /// In de, this message translates to:
  /// **'Log'**
  String get adminUpdateLog;

  /// No description provided for @adminUpdateRequestFailed.
  ///
  /// In de, this message translates to:
  /// **'Das Update konnte nicht angefordert werden'**
  String get adminUpdateRequestFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
