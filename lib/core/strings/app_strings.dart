class AppStrings {
  const AppStrings();

  String get defaultGymName => 'Athlete 615';

  String get navWorkout => 'Workout';
  String get navBooking => 'Booking';
  String get navExplore => 'Explore';
  String get navProfile => 'Profile';
  String get navDashboard => 'Dashboard';

  String get bookingTitle => 'Booking';
  String get bookingBook => 'Book';
  String get bookingCancel => 'Cancel';
  String get bookingBooked => 'Booked';
  String get bookingFull => 'Full';
  String get bookingMembershipRequired => 'Membership required';
  String get bookingInProgress => 'Class in progress';
  String get bookingFinished => 'Finished';

  String get bookingConfirmed => 'Booking confirmed';
  String get bookingCancelled => 'Booking cancelled';
  String get bookingClassFull => 'Class is full';
  String get bookingTooLateCancel => 'Too late to cancel';
  String get bookingActiveMembershipRequired => 'Active membership required';

  String bookingLoadError(Object e) => 'Booking load error: $e';
  String bookingBookError(Object e) => 'Book class error: $e';
  String bookingCancelError(Object e) => 'Cancel booking error: $e';

  String get bookingActiveMembershipRequiredToBook =>
      'Active membership required to book classes.';

  String get workoutsTitle => 'Workouts';

  String get workoutCreateTitle => 'Create workout';
  String get workoutNeedProgram =>
      'Create at least one active program before creating workouts.';
  String get workoutProgram => 'Program';
  String get workoutDate => 'Date';
  String get workoutSelectImage => 'Select image';
  String get workoutDescription => 'Workout description';
  String get workoutWriteWod => 'Write the WOD...';
  String get workoutCreate => 'Create workout';

  String get workoutEditTitle => 'Edit workout';
  String get workoutSaveChanges => 'Save changes';
  String workoutUpdateError(Object e) => 'Update workout error: $e';

  String get workoutsPrograms => 'Programs';
  String get workoutsDeleteTitle => 'Delete workout?';
  String get workoutsDeleteMessage => 'This cannot be undone.';
  String get workoutsNoToday => 'No workouts for today yet.';
  String workoutsLoadError(Object e) => 'Workouts load error: $e';
  String workoutsDeleteError(Object e) => 'Delete workout error: $e';

  String get exploreTitle => 'Explore';
  String get exploreSearchWorkouts => 'Search workouts...';
  String get exploreAllPrograms => 'All programs';
  String get exploreNoWorkoutsFound => 'No workouts found.';
  String exploreLoadError(Object e) => 'Explore load error: $e';
  String exploreDeleteWorkoutError(Object e) => 'Delete workout error: $e';

  String get notificationsTitle => 'Notifications';
  String get notificationsMarkRead => 'Mark read';
  String get notificationsEmpty => 'No notifications yet.';
  String get notificationFallbackTitle => 'Notification';
  String notificationSent(String date) => 'Sent $date';
  String notificationScheduled(String date) => 'Scheduled $date';
  String notificationsLoadError(Object e) => 'Notifications error: $e';
  String notificationsMarkReadError(Object e) => 'Mark read error: $e';

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
