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
  String feedUpdateCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count updates',
      one: '1 update',
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

  @override
  String get placeSearchHint => 'Address or coordinates';

  @override
  String get placeSearchClear => 'Clear';

  @override
  String get placeSearchGo => 'Search';

  @override
  String get placeSearchTooShort => 'Please enter at least 3 characters';

  @override
  String get placeSearchNoResult => 'No place found';

  @override
  String get placeSearchOutside =>
      'These coordinates are outside the supported region (Germany, Austria, Switzerland, Liechtenstein)';

  @override
  String get placeSearchRateLimited =>
      'Too many searches, please try again in a moment';

  @override
  String get placeSearchUnavailable =>
      'Address search is currently unavailable, please try again later';

  @override
  String get placeSearchError => 'Search failed, please try again';

  @override
  String get placeSearchShortLink =>
      'Short links cannot be resolved. Please paste the full link or the coordinates instead.';

  @override
  String get adminOpen => 'Admin';

  @override
  String get adminTitle => 'Admin';

  @override
  String get adminReports => 'Reports';

  @override
  String get adminUsers => 'Users';

  @override
  String get adminSpots => 'Spots';

  @override
  String adminReportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports',
      one: '1 report',
    );
    return '$_temp0';
  }

  @override
  String adminReportedBy(String name, String email) {
    return 'Reported by $name ($email)';
  }

  @override
  String get adminTargetDeleted => 'Deleted';

  @override
  String adminUpdateOn(String title) {
    return 'Update on $title';
  }

  @override
  String get statusActive => 'Active';

  @override
  String get statusHidden => 'Hidden';

  @override
  String get statusLocked => 'Locked';

  @override
  String get statusAll => 'All';

  @override
  String get adminOpenSpot => 'Open spot';

  @override
  String get adminRemoveSpot => 'Remove spot';

  @override
  String get adminRemove => 'Remove';

  @override
  String get adminSearchUsers => 'Search name or email';

  @override
  String get adminSearchSpots => 'Search title';

  @override
  String get adminBadge => 'admin';

  @override
  String adminUserSpots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spots',
      one: '1 spot',
    );
    return '$_temp0';
  }

  @override
  String adminUserReports(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports received',
      one: '1 report received',
    );
    return '$_temp0';
  }

  @override
  String adminJoined(String date) {
    return 'Joined $date';
  }

  @override
  String adminSpotAuthor(String name) {
    return 'by $name';
  }

  @override
  String get adminRemoveTitle => 'Remove spot?';

  @override
  String adminRemoveBody(String title) {
    return '\"$title\" deletes the spot with all its updates, likes and photos permanently.';
  }

  @override
  String get adminSpotRemoved => 'Spot removed';

  @override
  String get adminEdit => 'Edit';

  @override
  String get adminEditUser => 'Edit user';

  @override
  String get adminEditSpot => 'Edit spot';

  @override
  String get adminIsAdmin => 'Admin';

  @override
  String get adminSelfAdminHint => 'You can\'t change your own admin status.';

  @override
  String get adminStatus => 'Status';

  @override
  String get adminCoordinates => 'Coordinates (lat, lon)';

  @override
  String get adminCoordsInvalid =>
      'Could not read these coordinates. Use e.g. 48.137, 11.575 or a map link.';

  @override
  String get adminUserSaved => 'User updated';

  @override
  String get adminSpotSaved => 'Spot updated';

  @override
  String get adminErrInvalidDisplayName => 'Invalid display name';

  @override
  String get adminErrInvalidEmail => 'Invalid email address';

  @override
  String get adminErrEmailTaken => 'This email is already in use';

  @override
  String get adminErrCannotDemoteSelf =>
      'You can\'t remove your own admin rights';

  @override
  String get adminErrLastAdmin => 'There must be at least one admin';

  @override
  String get adminErrInvalidTitle => 'Invalid title';

  @override
  String get adminErrInvalidDescription => 'Invalid description';

  @override
  String get adminErrInvalidCategory => 'Invalid category';

  @override
  String get adminErrInvalidStatus => 'Invalid status';

  @override
  String get adminErrInvalidLocation => 'Invalid location';

  @override
  String get adminDismiss => 'Dismiss';

  @override
  String get adminMoreActions => 'More actions';

  @override
  String get adminDismissAllRestore => 'Dismiss all and restore';

  @override
  String get adminDismissAllKeep => 'Dismiss all (keep hidden)';

  @override
  String get adminDismissAllTitle => 'Dismiss all reports?';

  @override
  String get adminDismissAllRestoreBody =>
      'Removes all reports about this item and makes it visible again.';

  @override
  String get adminDismissAllKeepBody =>
      'Removes all reports about this item. Hidden content stays hidden.';

  @override
  String get adminReportDismissed => 'Report dismissed';

  @override
  String adminReportsDismissed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports dismissed',
      one: '1 report dismissed',
    );
    return '$_temp0';
  }

  @override
  String get adminTargetReview => 'Review';

  @override
  String get adminTargetUpdate => 'Update';

  @override
  String get adminRemoveReview => 'Remove review';

  @override
  String get adminRemoveUpdate => 'Remove update';

  @override
  String get adminRemoveReviewTitle => 'Remove review?';

  @override
  String get adminRemoveUpdateTitle => 'Remove update?';

  @override
  String get adminRemoveReviewBody => 'This deletes this review permanently.';

  @override
  String get adminRemoveUpdateBody => 'This deletes this update permanently.';

  @override
  String get adminReviewRemoved => 'Review removed';

  @override
  String get adminUpdateRemoved => 'Update removed';

  @override
  String adminRatingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get reviewsTitle => 'Reviews';

  @override
  String get reviewNone => 'No reviews yet';

  @override
  String get updatesTitle => 'Updates';

  @override
  String get updatesNone => 'No updates yet';

  @override
  String get mapStreets => 'Map';

  @override
  String get mapSatellite => 'Satellite';

  @override
  String get mapRecenter => 'Back to the spot';

  @override
  String reviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reviews',
      one: '1 review',
    );
    return '$_temp0';
  }

  @override
  String get reviewWrite => 'Write a review';

  @override
  String get reviewEditMine => 'Edit your review';

  @override
  String get reviewYours => 'Your review';

  @override
  String reviewStarLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get reviewBodyHint => 'Your experience (optional)';

  @override
  String get reviewDeleteTitle => 'Delete your review?';

  @override
  String get reviewDeleteConfirm => 'Delete';

  @override
  String get reviewEdited => 'edited';

  @override
  String get reviewLoadMore => 'Load more';

  @override
  String get reviewActionEdit => 'Edit review';

  @override
  String get reviewActionDelete => 'Delete review';

  @override
  String get reviewErrorInvalidRating => 'Please choose 1 to 5 stars';

  @override
  String get reviewErrorInvalidBody => 'The text is too long';

  @override
  String get reviewErrorOwnSpot => 'You cannot review your own spot';

  @override
  String get updateTagLabel => 'Status';

  @override
  String get updateTagNote => 'Note';

  @override
  String get updateTagStillGood => 'Still good';

  @override
  String get updateTagCrowded => 'Crowded';

  @override
  String get updateTagDirty => 'Dirty';

  @override
  String get updateTagClosed => 'Closed';

  @override
  String get updateEditTitle => 'Edit update';

  @override
  String get updateEdited => 'edited';

  @override
  String get updatePost => 'Post';

  @override
  String get updateRemovePhoto => 'Remove photo';

  @override
  String get updateActionEdit => 'Edit update';

  @override
  String get updateActionDelete => 'Delete update';

  @override
  String get updateDeleteTitle => 'Delete this update?';

  @override
  String get updateDeleteConfirm => 'Delete';

  @override
  String get updatePhotosReadOnly => 'Photos cannot be changed afterwards';

  @override
  String get updateErrorInvalidPhoto => 'One of the photos is invalid';

  @override
  String get updateErrorInvalidBody => 'The text is invalid or too long';

  @override
  String get updateErrorInvalidTag => 'Please choose a valid status';

  @override
  String get photoViewerClose => 'Close';

  @override
  String photoViewerPage(int current, int total) {
    return '$current / $total';
  }

  @override
  String get addSpotPhotoUnsupported =>
      'This image format is not supported. Please use JPEG, PNG, WebP or AVIF.';

  @override
  String get addSpotPhotoTooLarge => 'The photo is too large (maximum 8 MB).';

  @override
  String get errorNetwork =>
      'The server cannot be reached. Check your connection and try again.';

  @override
  String errorWithDetail(String message) {
    return 'Something went wrong: $message';
  }

  @override
  String get tagsTitle => 'Tags';

  @override
  String get tagsClear => 'Clear tags';

  @override
  String get editTags => 'Edit tags';

  @override
  String get tagsErrForbidden => 'Only the author or an admin can change tags';

  @override
  String get tagsErrInvalid => 'One of the tags is invalid';

  @override
  String get adminOwner => 'Owner';

  @override
  String get adminChangeOwner => 'Change owner';

  @override
  String get adminPickUser => 'Choose the new owner';

  @override
  String get adminLocked => 'Locked';

  @override
  String get adminLockedHint =>
      'Users can post no updates and change nothing; admins still can.';

  @override
  String get adminErrInvalidOwner => 'This user does not exist';

  @override
  String get spotLockedNotice =>
      'This spot is locked. Only admins can change it.';

  @override
  String get adminEditSpotHere => 'Edit spot (admin)';

  @override
  String get adminLock => 'Lock spot';

  @override
  String get adminUnlock => 'Unlock spot';

  @override
  String get adminSpotLocked => 'Spot locked';

  @override
  String get adminSpotUnlocked => 'Spot unlocked';

  @override
  String get adminEditUpdate => 'Edit update (admin)';

  @override
  String get adminHideUpdate => 'Hide update';

  @override
  String get adminUpdateHidden => 'Update hidden';

  @override
  String get adminTags => 'Tags';

  @override
  String get adminNewTag => 'New tag';

  @override
  String get adminEditTag => 'Edit tag';

  @override
  String get adminTagKey => 'Key (a-z, 0-9, _)';

  @override
  String get adminTagKeyHint =>
      'Used by the app and the API; cannot be changed later';

  @override
  String get adminTagNameDe => 'German name';

  @override
  String get adminTagNameEn => 'English name';

  @override
  String get adminTagIcon => 'Icon';

  @override
  String get adminTagMoveUp => 'Move up';

  @override
  String get adminTagMoveDown => 'Move down';

  @override
  String adminTagSpots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spots',
      one: '1 spot',
      zero: 'no spots',
    );
    return '$_temp0';
  }

  @override
  String get adminDeleteTag => 'Delete tag';

  @override
  String adminDeleteTagTitle(String name) {
    return 'Delete the tag “$name”?';
  }

  @override
  String adminDeleteTagBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'It is removed from $count spots.',
      one: 'It is removed from 1 spot.',
      zero: 'No spot uses it.',
    );
    return '$_temp0';
  }

  @override
  String get adminTagDeleted => 'Tag deleted';

  @override
  String get adminTagSaved => 'Tag saved';

  @override
  String get adminErrTagTaken => 'A tag with this key already exists';

  @override
  String get adminErrTagKey =>
      '2 to 16 characters: a-z, 0-9 and _, starting with a letter';

  @override
  String get adminErrTagName => 'Names must be 1 to 40 characters';
}
