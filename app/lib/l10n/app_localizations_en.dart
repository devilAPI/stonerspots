// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Stonerspots';

  @override
  String get navMap => 'Map';

  @override
  String get navFeed => 'Feed';

  @override
  String get navProfile => 'Profile';

  @override
  String get mapTitle => 'Map';

  @override
  String get feedTitle => 'Feed';

  @override
  String get spotDetailTitle => 'Spot';

  @override
  String get addSpotTitle => 'Add spot';

  @override
  String get addSpot => 'Add spot';

  @override
  String get login => 'Log in';

  @override
  String get register => 'Register';

  @override
  String get logout => 'Log out';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get displayName => 'Display name';

  @override
  String get adultConfirm => 'I am at least 18 years old';

  @override
  String get noAccountYet => 'No account yet? Register';

  @override
  String get haveAccount => 'Already have an account? Log in';

  @override
  String get passwordTooShort => 'At least 10 characters';

  @override
  String get fieldRequired => 'Required';

  @override
  String get categoryBench => 'Bench';

  @override
  String get categoryRiver => 'River';

  @override
  String get categoryLake => 'Lake';

  @override
  String get categoryViewpoint => 'Viewpoint';

  @override
  String get categoryForest => 'Forest';

  @override
  String get categoryPark => 'Park';

  @override
  String get categoryOther => 'Other';

  @override
  String get categoryAll => 'All';

  @override
  String get category => 'Category';

  @override
  String get sort => 'Sort';

  @override
  String get sortNew => 'New';

  @override
  String get sortTop => 'Top';

  @override
  String get sortNearby => 'Nearby';

  @override
  String get like => 'Like';

  @override
  String get report => 'Report';

  @override
  String get reportReason => 'Reason';

  @override
  String get postUpdate => 'Post update';

  @override
  String get openSpot => 'Open';

  @override
  String get openInGoogleMaps => 'Open in Google Maps';

  @override
  String get title => 'Title';

  @override
  String get description => 'Description';

  @override
  String get addPhotos => 'Add photos';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get duplicateSpot =>
      'There\'s already a spot here — open it or add anyway';

  @override
  String get addAnyway => 'Add anyway';

  @override
  String get loginRequired => 'Please log in first';

  @override
  String get errorGeneric => 'Something went wrong';

  @override
  String get retry => 'Retry';

  @override
  String get noResults => 'Nothing found';

  @override
  String get locationDenied => 'Location permission denied';

  @override
  String likesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count likes',
      one: '1 like',
      zero: 'No likes',
    );
    return '$_temp0';
  }

  @override
  String get changePassword => 'Change password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get repeatNewPassword => 'Repeat new password';

  @override
  String get passwordsDontMatch => 'Passwords do not match';

  @override
  String get passwordTooLong => 'At most 72 characters';

  @override
  String get passwordChanged => 'Password changed';

  @override
  String get wrongPassword => 'Wrong password';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountWarning =>
      'Your account and all your spots, updates and photos will be permanently deleted. This cannot be undone. Enter your password to confirm.';

  @override
  String get deleteAccountConfirm => 'Delete permanently';
}
