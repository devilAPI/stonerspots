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

  /// No description provided for @categoryBench.
  ///
  /// In de, this message translates to:
  /// **'Bank'**
  String get categoryBench;

  /// No description provided for @categoryRiver.
  ///
  /// In de, this message translates to:
  /// **'Fluss'**
  String get categoryRiver;

  /// No description provided for @categoryLake.
  ///
  /// In de, this message translates to:
  /// **'See'**
  String get categoryLake;

  /// No description provided for @categoryViewpoint.
  ///
  /// In de, this message translates to:
  /// **'Aussichtspunkt'**
  String get categoryViewpoint;

  /// No description provided for @categoryForest.
  ///
  /// In de, this message translates to:
  /// **'Wald'**
  String get categoryForest;

  /// No description provided for @categoryPark.
  ///
  /// In de, this message translates to:
  /// **'Park'**
  String get categoryPark;

  /// No description provided for @categoryOther.
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get categoryOther;

  /// No description provided for @categoryAll.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get categoryAll;

  /// No description provided for @category.
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get category;

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
