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
  String get invalidLocation => 'These coordinates are not valid';

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
  String get adminErrInvalidDisplayName =>
      'Invalid display name (1 to 80 characters, no @)';

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
  String get mapTransit => 'Public transport';

  @override
  String get spotShare => 'Share';

  @override
  String get linkCopied => 'Link copied';

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
  String get adminDeleteSpot => 'Delete spot';

  @override
  String get adminSpotDeleted => 'Spot deleted';

  @override
  String get adminSpotLocked => 'Spot locked';

  @override
  String get adminSpotUnlocked => 'Spot unlocked';

  @override
  String get adminEditUpdate => 'Edit update (admin)';

  @override
  String get adminHideUpdate => 'Hide update';

  @override
  String get adminPhotos => 'Photos';

  @override
  String get adminPhotoRotateLeft => 'Rotate left';

  @override
  String get adminPhotoRotateRight => 'Rotate right';

  @override
  String get adminPhotoRemove => 'Remove photo';

  @override
  String get adminPhotoRestore => 'Keep photo';

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

  @override
  String get backToHome => 'Back to the map';

  @override
  String get mapMyLocation => 'My location';

  @override
  String get mapSearch => 'Search spots';

  @override
  String get mapSearchHint => 'Name of a spot';

  @override
  String get mapSearchClose => 'Close search';

  @override
  String get mapSearchClear => 'Clear';

  @override
  String get mapSearchTooShort => 'Type at least 2 characters';

  @override
  String get mapSearchNoResult => 'No spot with that name';

  @override
  String get mapSearchError => 'Search failed';

  @override
  String get weatherTitle => 'Weather';

  @override
  String weatherWind(String speed) {
    return 'Wind $speed km/h';
  }

  @override
  String weatherRainChance(int percent) {
    return 'Rain $percent%';
  }

  @override
  String weatherPrecipitation(String amount) {
    return '$amount mm';
  }

  @override
  String get weatherNextHours => 'Next hours';

  @override
  String get weatherAttribution => 'Weather: Open-Meteo.com';

  @override
  String get weatherClear => 'Clear';

  @override
  String get weatherMainlyClear => 'Mainly clear';

  @override
  String get weatherPartlyCloudy => 'Partly cloudy';

  @override
  String get weatherOvercast => 'Overcast';

  @override
  String get weatherFog => 'Fog';

  @override
  String get weatherDrizzle => 'Drizzle';

  @override
  String get weatherFreezingDrizzle => 'Freezing drizzle';

  @override
  String get weatherRainLight => 'Light rain';

  @override
  String get weatherRain => 'Rain';

  @override
  String get weatherRainHeavy => 'Heavy rain';

  @override
  String get weatherFreezingRain => 'Freezing rain';

  @override
  String get weatherSnowLight => 'Light snow';

  @override
  String get weatherSnow => 'Snow';

  @override
  String get weatherSnowHeavy => 'Heavy snow';

  @override
  String get weatherSnowGrains => 'Snow grains';

  @override
  String get weatherShowers => 'Rain showers';

  @override
  String get weatherShowersHeavy => 'Heavy rain showers';

  @override
  String get weatherSnowShowers => 'Snow showers';

  @override
  String get weatherThunderstorm => 'Thunderstorm';

  @override
  String get weatherThunderstormHail => 'Thunderstorm with hail';

  @override
  String get weatherUnknown => 'Unknown';

  @override
  String get loginId => 'Email or name';

  @override
  String get displayNameHelp => 'You can also log in with it; no @';

  @override
  String get authErrInvalidCredentials => 'Wrong name, email or password';

  @override
  String get authErrNameTaken => 'This name is already taken';

  @override
  String get authErrInvalidName =>
      'The name must be 1 to 80 characters without @';

  @override
  String get adminActions => 'Actions';

  @override
  String adminSelected(int count) {
    return '$count selected';
  }

  @override
  String get adminSelectAll => 'Select all loaded';

  @override
  String get adminClearSelection => 'Clear selection';

  @override
  String get adminSelect => 'Select';

  @override
  String get adminBan => 'Ban';

  @override
  String get adminUnban => 'Unban';

  @override
  String get adminBanned => 'banned';

  @override
  String get adminDelete => 'Delete';

  @override
  String get adminHide => 'Hide';

  @override
  String get adminShow => 'Show';

  @override
  String get adminBulkLock => 'Lock';

  @override
  String get adminBulkUnlock => 'Unlock';

  @override
  String get adminAddTag => 'Add tag';

  @override
  String get adminRemoveTag => 'Remove tag';

  @override
  String get adminChooseTag => 'Choose a tag';

  @override
  String adminDeleteUsersTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count users?',
      one: 'Delete 1 user?',
    );
    return '$_temp0';
  }

  @override
  String get adminDeleteUsersBody =>
      'The accounts are deleted with all their spots, photos, reviews and updates. This cannot be undone.';

  @override
  String adminDeleteSpotsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count spots?',
      one: 'Delete 1 spot?',
    );
    return '$_temp0';
  }

  @override
  String get adminDeleteSpotsBody =>
      'The spots are deleted with all their photos, updates, reviews and reports. This cannot be undone.';

  @override
  String adminBulkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changed',
      one: '1 changed',
    );
    return '$_temp0';
  }

  @override
  String adminBulkDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deleted',
      one: '1 deleted',
    );
    return '$_temp0';
  }

  @override
  String adminBulkSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count skipped (you, admins or already gone)',
      one: '1 skipped (you, an admin or already gone)',
    );
    return '$_temp0';
  }

  @override
  String get authErrBanned => 'This account is banned';

  @override
  String get adminBackend => 'Backend';

  @override
  String adminBackendVersion(String version) {
    return 'Installed: $version';
  }

  @override
  String get adminVersionUnknown =>
      'Version unknown (not installed with install-backend.sh)';

  @override
  String get adminUpdateRelease => 'Update backend to newest';

  @override
  String get adminUpdateDev => 'Update backend to newest dev';

  @override
  String get adminUpdateConfirmTitle => 'Update the backend?';

  @override
  String get adminUpdateConfirmRelease =>
      'The server downloads the newest release, installs it and restarts. The app is unavailable for a few seconds.';

  @override
  String get adminUpdateConfirmDev =>
      'The server downloads the newest dev build (may be unstable), installs it and restarts. The app is unavailable for a few seconds.';

  @override
  String get adminUpdate => 'Update';

  @override
  String get adminUpdatesDisabled =>
      'Updates from here are off on this server. Run install-backend.sh on the server once to set them up.';

  @override
  String get adminUpdatePending => 'Update requested, waiting for the server…';

  @override
  String get adminUpdateRunning => 'Updating… the server restarts at the end';

  @override
  String get adminServerRestarting => 'Server is restarting…';

  @override
  String adminUpdateDone(String from, String to) {
    return 'Updated: $from → $to';
  }

  @override
  String adminUpdateUpToDate(String version) {
    return 'Already up to date ($version)';
  }

  @override
  String get adminUpdateFailed => 'The last update failed; see the log';

  @override
  String adminUpdateFinishedAt(String time) {
    return 'Finished $time';
  }

  @override
  String get adminUpdateLog => 'Log';

  @override
  String get adminUpdateRequestFailed => 'The update could not be requested';

  @override
  String get adminEditUpdates => 'Edit updates';

  @override
  String get adminPickUpdate => 'Which update?';

  @override
  String get adminShowUserSpots => 'Show spots';

  @override
  String adminSpotsOf(String name) {
    return 'Spots by $name';
  }

  @override
  String get adminUpdateSaved => 'Update saved';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsDisableTransparency => 'Disable transparency';

  @override
  String get settingsDisableTransparencyHint =>
      'Solid surfaces instead of glass. Easier on the GPU and battery.';

  @override
  String get settingsRealGlass => 'Real glass';

  @override
  String get settingsRealGlassHint =>
      'Glass bends what is behind it. Off, it is frosted, which is easier on the GPU and battery.';

  @override
  String get settingsReduceMotion => 'Reduce motion';

  @override
  String get settingsReduceMotionHint =>
      'The map jumps instead of flying and tilts without animation.';

  @override
  String get settingsMap => 'Map';

  @override
  String get settingsBuildings3d => '3D buildings';

  @override
  String get settingsBuildings3dHint =>
      'Buildings on the tilted map. Turn off on older devices for a smoother map.';

  @override
  String get settingsSharpTiles => 'Sharp map';

  @override
  String get settingsSharpTilesHint =>
      'High-resolution map tiles on sharp screens. Off loads a quarter of the data.';

  @override
  String get saved => 'Saved';

  @override
  String get savedFavourites => 'Favourites';

  @override
  String get savedToFavourites => 'Saved to Favourites';

  @override
  String get savedChangeList => 'Change list';

  @override
  String get savedPickLists => 'Save to lists';

  @override
  String get savedNewList => 'New list';

  @override
  String get savedListName => 'List name';

  @override
  String get savedRenameList => 'Rename';

  @override
  String get savedDelete => 'Delete';

  @override
  String get savedDeleteTitle => 'Delete list?';

  @override
  String savedDeleteBody(String name) {
    return '“$name” will be deleted. The spots in it are kept.';
  }

  @override
  String get savedNameTaken => 'You already have a list with this name';

  @override
  String get savedListLimit => 'You have reached the maximum number of lists';

  @override
  String get savedEmpty =>
      'Nothing saved yet. Tap the bookmark on a spot to keep it here.';

  @override
  String get savedListEmpty => 'This list is still empty';

  @override
  String get savedListGone => 'This list no longer exists';

  @override
  String get savedRemoveSpot => 'Remove from list';

  @override
  String savedSpotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spots',
      one: '1 spot',
      zero: 'No spots',
    );
    return '$_temp0';
  }

  @override
  String get feedFollowing => 'Following';

  @override
  String get feedFollowingEmpty => 'No updates from people you follow yet';

  @override
  String get userFollow => 'Follow';

  @override
  String get userUnfollow => 'Unfollow';

  @override
  String userJoined(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMM(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Joined $dateString';
  }

  @override
  String get userStatSpots => 'Spots';

  @override
  String get userStatUpdates => 'Updates';

  @override
  String get userStatFollowers => 'Followers';

  @override
  String get userStatFollowing => 'Following';

  @override
  String get userTabSpots => 'Spots';

  @override
  String get userTabUpdates => 'Updates';

  @override
  String get userNoSpots => 'No spots yet';

  @override
  String get userNoUpdates => 'No updates yet';

  @override
  String get userGone => 'This profile does not exist';

  @override
  String get commentsTitle => 'Comments';

  @override
  String get commentsEmpty => 'No comments yet. Be the first!';

  @override
  String get commentsLoadMore => 'More comments';

  @override
  String get commentsQuota =>
      'You have commented a lot today. Please try again tomorrow.';

  @override
  String get commentHint => 'Write a comment …';

  @override
  String get commentSend => 'Send';

  @override
  String get commentLoginToWrite => 'Log in to comment';

  @override
  String get commentMore => 'More';

  @override
  String get commentDelete => 'Delete comment';

  @override
  String get commentDeleteTitle => 'Delete comment?';

  @override
  String get commentDeleteConfirm => 'Delete';

  @override
  String get commentReported => 'Thanks, we will look at this comment';

  @override
  String get adminTargetComment => 'Comment';

  @override
  String adminCommentOn(String title) {
    return 'Comment on $title';
  }

  @override
  String get adminRemoveComment => 'Remove comment';

  @override
  String get adminRemoveCommentTitle => 'Remove comment?';

  @override
  String get adminRemoveCommentBody => 'This deletes this comment permanently.';

  @override
  String get adminCommentRemoved => 'Comment removed';

  @override
  String get close => 'Close';

  @override
  String get activityTitle => 'Activity';

  @override
  String activityTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Activity, $count new',
      one: 'Activity, 1 new',
      zero: 'Activity',
    );
    return '$_temp0';
  }

  @override
  String get activityEmpty =>
      'Nothing yet. Here you see when someone follows you, comments on your updates or likes or rates your spots.';

  @override
  String activityFollow(String name) {
    return '$name started following you';
  }

  @override
  String activityComment(String name, String spot, String text) {
    return '$name commented on your update at $spot: $text';
  }

  @override
  String activityLike(String name, String spot) {
    return '$name liked $spot';
  }

  @override
  String activityReview(String name, String spot) {
    return '$name rated $spot';
  }

  @override
  String get settingsAbout => 'About Stonerspots';

  @override
  String get whatsNewTitle => 'What\'s new in 1.0';

  @override
  String get whatsNewSearchTitle => 'Map, search & compass';

  @override
  String get whatsNewSearchBody =>
      'Browse spots on the map, find them by name (Ctrl+K), and tap the compass to turn the map back to north.';

  @override
  String get whatsNewSpotsTitle => 'Spots';

  @override
  String get whatsNewSpotsBody =>
      'Every spot has photos, the weather for the next hours, reviews, comments and updates from people who were there.';

  @override
  String get whatsNewFollowingTitle => 'Feed & Following';

  @override
  String get whatsNewFollowingBody =>
      'The feed shows the newest updates, or only those of people you follow.';

  @override
  String get whatsNewProfilesTitle => 'Profiles & following';

  @override
  String get whatsNewProfilesBody =>
      'Give yourself a profile picture, tap a name to see someone\'s profile and follow them.';

  @override
  String get whatsNewActivityTitle => 'Activity';

  @override
  String get whatsNewActivityBody =>
      'The bell on your profile shows who followed you, commented, or liked or rated your spots.';

  @override
  String get whatsNewSavedTitle => 'Saved lists';

  @override
  String get whatsNewSavedBody =>
      'Save spots to your own lists to find them again.';

  @override
  String get whatsNewAdminTitle => 'Admin tools';

  @override
  String get whatsNewAdminBody =>
      'Admins handle reports, ban users, edit or hide content, manage tags and update the server, protected by two-factor codes.';

  @override
  String get whatsNewUpdatesTitle => 'Automatic updates';

  @override
  String get whatsNewUpdatesBody =>
      'The Android and desktop apps find new versions themselves and install them only when they are signed.';

  @override
  String get profileAccountMenu => 'Account';

  @override
  String get spotAddedBy => 'Added by';

  @override
  String get deletedAccount => 'Deleted account';

  @override
  String get avatarChange => 'Change profile picture';

  @override
  String get avatarCropTitle => 'Crop picture';

  @override
  String get avatarCropUse => 'Use';

  @override
  String get avatarCropZoom => 'Zoom';

  @override
  String get avatarChoose => 'Choose photo';

  @override
  String get avatarView => 'Show picture';

  @override
  String get avatarRemove => 'Remove photo';

  @override
  String get adminRemoveAvatar => 'Remove profile picture';

  @override
  String adminRemoveAvatarBody(String name) {
    return 'The profile picture of $name will be deleted.';
  }

  @override
  String get adminAvatarRemoved => 'Profile picture removed';

  @override
  String get liked => 'Liked';

  @override
  String commentsShowAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Show all $count comments',
      one: 'Show 1 comment',
    );
    return '$_temp0';
  }

  @override
  String get commentsShowLess => 'Show less';

  @override
  String get mapNorthUp => 'Turn north up';

  @override
  String activitySpotComment(String name, String spot, String text) {
    return '$name commented on your spot $spot: $text';
  }

  @override
  String get commentsLocked => 'This spot is locked, comments are closed';

  @override
  String get commentsSpotGone => 'This spot no longer exists';

  @override
  String get commentGone => 'This comment no longer exists';

  @override
  String updateAvailableTitle(String tag) {
    return 'Update available ($tag)';
  }

  @override
  String updateInstalledVersion(String version) {
    return 'Installed: $version';
  }

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Later';

  @override
  String get updateSkip => 'Skip this version';

  @override
  String get updateOpenReleasePage => 'Open release page';

  @override
  String get updateNoKeyHint =>
      'This build can\'t verify updates, so it installs nothing itself. Get the update from the release page.';

  @override
  String get updateNotWritableHint =>
      'The app\'s folder isn\'t writable. Get the update from the release page.';

  @override
  String get updatePermissionHint =>
      'Allow Stonerspots to install apps in the settings, then tap “Update now” again.';

  @override
  String get updateOpenSettings => 'Open settings';

  @override
  String updateDownloading(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateVerifying => 'Checking signature and checksum…';

  @override
  String get updateInstalling => 'Installing…';

  @override
  String get updateHandedOff =>
      'Confirm the installation in the system dialog.';

  @override
  String get updateErrorSignature =>
      'The update\'s signature doesn\'t check out. Nothing was installed.';

  @override
  String get updateErrorChecksum =>
      'The file doesn\'t match the signed checksum. Nothing was installed.';

  @override
  String get updateErrorMissing => 'This release has no file for this device.';

  @override
  String get updateErrorDownload => 'Download failed.';

  @override
  String get updateErrorInstall =>
      'Installation failed. The current version stays.';

  @override
  String get updateRetry => 'Try again';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsAutoUpdate => 'Check for updates automatically';

  @override
  String get settingsAutoUpdateHint =>
      'At start, at most every 6 hours, on GitHub.';

  @override
  String get settingsCheckUpdates => 'Check for updates';

  @override
  String get updateStatusChecking => 'Checking…';

  @override
  String updateStatusUpToDate(String version) {
    return 'Up to date ($version)';
  }

  @override
  String updateStatusAvailable(String tag) {
    return 'Update available: $tag';
  }

  @override
  String get updateStatusRateLimited =>
      'GitHub asks for a break. Try again later.';

  @override
  String get updateStatusOffline => 'Can\'t reach GitHub right now.';

  @override
  String get settingsNoUpdateChannel =>
      'This build doesn\'t check for updates.';

  @override
  String get twoFactorTitle => 'Two-factor authentication (2FA)';

  @override
  String get twoFactorOn => 'On';

  @override
  String get twoFactorOff => 'Off';

  @override
  String get twoFactorIntro =>
      'Protect your admin rights with codes from an authenticator app (e.g. Aegis, 2FAS or Google Authenticator).';

  @override
  String get twoFactorEnable => 'Set up 2FA';

  @override
  String get twoFactorScan =>
      '1. Scan the QR code with your authenticator app, or enter the key by hand.';

  @override
  String get twoFactorSecret => 'Key';

  @override
  String get twoFactorCopy => 'Copy key';

  @override
  String get twoFactorCopied => 'Key copied';

  @override
  String get twoFactorEnterCode =>
      '2. Enter the 6-digit code the app shows now.';

  @override
  String get twoFactorCode => 'Code';

  @override
  String get twoFactorConfirm => 'Confirm';

  @override
  String get twoFactorEnabledInfo =>
      '2FA is on now. From now on the app asks for a code on every admin action. A code you enter is good for all admin actions for 15 minutes.';

  @override
  String get twoFactorActiveHint =>
      'Admin actions need a code from your authenticator app. A code you enter is good for 15 minutes.';

  @override
  String get twoFactorDisable => 'Turn off 2FA';

  @override
  String get twoFactorDisableText =>
      'Confirm with your password and a current code from your authenticator app.';

  @override
  String get twoFactorDisabled => '2FA is off.';

  @override
  String get twoFactorErrInvalid => 'Wrong code. Try again.';

  @override
  String get twoFactorErrReused =>
      'This code was used already. Wait for the next one.';

  @override
  String get twoFactorErrDigits => 'The code has 6 digits.';

  @override
  String get twoFactorErrRateLimited =>
      'Too many attempts. Wait a few minutes.';

  @override
  String get twoFactorErrNoSecret => 'The setup has expired. Start it again.';

  @override
  String get twoFactorErrAlreadyOn => '2FA is on already.';

  @override
  String get twoFactorErrNotOn => '2FA is not on.';

  @override
  String get adminCodeTitle => 'Admin confirmation';

  @override
  String get adminCodePrompt =>
      'Enter the 6-digit code from your authenticator app. It is then good for all admin actions for 15 minutes.';

  @override
  String get adminCodeExpired =>
      'Your admin session has expired. Enter a new code from your authenticator app.';

  @override
  String get settingsLegal => 'Legal';

  @override
  String get legalImprint => 'Legal notice';

  @override
  String get legalPrivacy => 'Privacy policy';

  @override
  String get legalRules => 'Community rules';

  @override
  String get legalImprintHeading =>
      'Information pursuant to § 5 DDG (German Digital Services Act)';

  @override
  String get legalContact => 'Contact';

  @override
  String get legalEmail => 'Email';

  @override
  String get legalPhone => 'Phone';

  @override
  String get legalResponsible =>
      'Responsible for the content pursuant to § 18 (2) MStV';

  @override
  String get legalNotConfigured =>
      'The operator of this server has not set up the legal notice yet.';

  @override
  String get legalNotConfiguredPrivacy =>
      'The operator of this server has not set up their contact details yet. The text below describes what the app and the server do with your data.';

  @override
  String get legalController => 'Controller';

  @override
  String get legalPrivacyContact => 'Contact for privacy questions';

  @override
  String get registerConsent =>
      'By registering you accept the [community rules] and confirm that you have read the [privacy policy].';

  @override
  String get exportData => 'Download my data';

  @override
  String get exportPreparing => 'Putting your data together …';

  @override
  String exportSaved(String path) {
    return 'Saved to $path';
  }

  @override
  String exportDownloaded(String name) {
    return 'Download started: $name';
  }

  @override
  String get exportFailed => 'That did not work. Please try again later.';

  @override
  String get exportRateLimited =>
      'You can download your data at most three times a day. Please try again later.';

  @override
  String get zonesTitle => 'No-consumption zones';

  @override
  String get zonesShow => 'Show no-consumption zones';

  @override
  String get zonesHide => 'Hide no-consumption zones';

  @override
  String get zonesInfo => 'About the zones';

  @override
  String get zonesZoomHint => 'Zoom in to see zones';

  @override
  String get zonesLoadFailed => 'Zones could not be loaded';

  @override
  String get zonesAttribution => 'Zones: © OpenStreetMap contributors';

  @override
  String get zonesDisclaimerData =>
      'Zones are computed from OpenStreetMap data, which can be incomplete or wrong, e.g. missing kindergartens or youth facilities, or facilities mapped only as a point.';

  @override
  String get zonesDisclaimerDistance =>
      'They are drawn 100 m around the whole site. The law measures from the entrance area and only where the facility is in sight, so the real zone can be smaller, or larger where data is missing.';

  @override
  String get zonesDisclaimerMissing =>
      'Not shown: cannabis clubs (Anbauvereinigungen), presence of minors, state or municipal bans (e.g. Bavaria: festivals, beer gardens, parks), and the rules of other countries. Only the German rule (§ 5 KCanG) is shown, and only in Germany.';

  @override
  String get zonesDisclaimerLaw =>
      'No legal advice: you are responsible for following the law.';

  @override
  String get zonesDisclaimerOk => 'Got it';

  @override
  String get zonesSource =>
      'Data: © OpenStreetMap contributors (ODbL), via Overpass.';

  @override
  String get zonesStaleNote =>
      'The data could not be refreshed just now and may be out of date.';

  @override
  String get zoneKindSchool => 'School';

  @override
  String get zoneKindKindergarten => 'Kindergarten';

  @override
  String get zoneKindChildcare => 'Childcare';

  @override
  String get zoneKindYouth => 'Children\'s or youth facility';

  @override
  String get zoneKindPlayground => 'Playground';

  @override
  String get zoneKindSports => 'Sports facility';

  @override
  String get zoneKindExplicit => 'Explicit ban';

  @override
  String get zoneKindPedestrian => 'Pedestrian zone';

  @override
  String zoneTitleNamed(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String zoneTapRadius(String title) {
    return '$title — 100 m no-consumption zone';
  }

  @override
  String zoneTapExplicit(String title) {
    return '$title — marked in OSM as a place where cannabis is banned';
  }

  @override
  String zoneTapPedestrianNow(String title) {
    return '$title — no consumption 7 am–8 pm, banned right now';
  }

  @override
  String zoneTapPedestrianLater(String title) {
    return '$title — no consumption 7 am–8 pm, allowed right now';
  }

  @override
  String zoneStatusForbiddenAt(String kind, String metres) {
    return 'In a no-consumption zone ($kind, $metres m)';
  }

  @override
  String zoneStatusForbiddenIn(String kind) {
    return 'In a no-consumption zone ($kind)';
  }

  @override
  String get zoneStatusPedestrian =>
      'Pedestrian zone: no consumption 7 am–8 pm';

  @override
  String get zoneStatusClear => 'No zone';

  @override
  String get zoneStatusUnknown => 'Zones could not be checked';

  @override
  String get zoneStatusChecking => 'Checking zones …';

  @override
  String get addSpotZoneTitle => 'No-consumption zone';

  @override
  String addSpotZoneWarning(String reason) {
    return 'This place is in a no-consumption zone ($reason). Smoking weed there is banned by § 5 KCanG. Add it anyway?';
  }

  @override
  String addSpotZonePedestrian(String reason) {
    return 'This place is in a pedestrian zone ($reason). Smoking weed there is banned from 7 am to 8 pm. Add it anyway?';
  }

  @override
  String addSpotZoneExplicit(String reason) {
    return 'This place is marked in OpenStreetMap as a place where cannabis is banned ($reason). Add it anyway?';
  }

  @override
  String get addSpotZoneNote =>
      'The zones come from OpenStreetMap and can be wrong.';

  @override
  String get devBuildTitle => 'You are using a development build';

  @override
  String get devBuildBody =>
      'This version is built from the newest, untested changes. Things can break, look different every day or lose data. For everyday use, take the stable version.';

  @override
  String get devBuildOpenStableWeb => 'Open stable version';

  @override
  String get devBuildLatestRelease => 'Latest stable release';

  @override
  String get devBuildSnooze => 'Don\'t show again for 30 days';

  @override
  String get settingsUpdateChannel => 'Update channel';

  @override
  String get updateChannelRelease => 'Stable';

  @override
  String get updateChannelDev => 'Dev';

  @override
  String get settingsUpdateChannelHint =>
      'Dev builds have the newest changes and can be broken.';

  @override
  String get updateChannelAndroidDowngrade =>
      'Android only installs the stable version once it is newer than this dev build. To switch right away, uninstall the app first.';

  @override
  String get map3d => '3D view';

  @override
  String get satelliteCredit => 'Satellite images: Esri World Imagery';

  @override
  String get zonesLoading => 'Loading zones…';
}
