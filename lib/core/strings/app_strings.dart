class AppStrings {
  const AppStrings();

  String get profileRole => 'Role';
  String get profileGymName => 'Gym name';
  String get profileSaveGymName => 'Save gym name';
  String get profileNewPassword => 'New password';
  String get profileChangePassword => 'Change password';
  String get profileLogout => 'Logout';
  String get profileDeleteAccount => 'Delete account';

  String get passwordUpdated => 'Password updated.';
  String get gymNameUpdated => 'Gym name updated.';
  String updateGymError(Object error) => 'Update gym error: $error';
  String deleteAccountError(Object error) => 'Delete account error: $error';
}

const appStrings = AppStrings();
