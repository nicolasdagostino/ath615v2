import '../locale/locale_controller.dart';

class AppStrings {
  const AppStrings();

  bool get isEs => localeController.locale.languageCode == 'es';

  String pick(String en, String es) => isEs ? es : en;

  String get defaultGymName => 'Athlete 615';

  String get navWorkout => pick('Workout', 'WOD');
  String get navBooking => pick('Booking', 'Reservas');
  String get navExplore => pick('Explore', 'Explorar');
  String get navProfile => pick('Profile', 'Perfil');
  String get navDashboard => pick('Dashboard', 'Panel');

  String get bookingTitle => pick('Booking', 'Reservas');
  String get bookingBook => pick('Book', 'Reservar');
  String get bookingCancel => pick('Cancel', 'Cancelar');
  String get bookingBooked => pick('Booked', 'Reservada');
  String get bookingFull => pick('Full', 'Completa');
  String get bookingMembershipRequired =>
      pick('Membership required', 'Membresía requerida');
  String get bookingInProgress => pick('Class in progress', 'Clase en curso');
  String get bookingFinished => pick('Finished', 'Finalizada');

  String get bookingConfirmed =>
      pick('Booking confirmed', 'Reserva confirmada');
  String get bookingCancelled => pick('Booking cancelled', 'Reserva cancelada');
  String get bookingClassFull =>
      pick('Class is full', 'La clase está completa');
  String get bookingTooLateCancel =>
      pick('Too late to cancel', 'Demasiado tarde para cancelar');
  String get bookingActiveMembershipRequired =>
      pick('Active membership required', 'Membresía activa requerida');

  String bookingLoadError(Object e) =>
      pick('Booking load error: $e', 'Error cargando reservas: $e');
  String bookingBookError(Object e) =>
      pick('Book class error: $e', 'Error al reservar clase: $e');
  String bookingCancelError(Object e) =>
      pick('Cancel booking error: $e', 'Error al cancelar reserva: $e');

  String get bookingActiveMembershipRequiredToBook => pick(
    'Active membership required to book classes.',
    'Necesitas una membresía activa para reservar clases.',
  );

  String get workoutsTitle => pick('Workouts', 'WODs');

  String get workoutCreateTitle => pick('Create workout', 'Crear WOD');
  String get workoutNeedProgram => pick(
    'Create at least one active program before creating workouts.',
    'Crea al menos un programa activo antes de crear WODs.',
  );
  String get workoutProgram => pick('Program', 'Programa');
  String get workoutDate => pick('Date', 'Fecha');
  String get workoutSelectImage => pick('Select image', 'Seleccionar imagen');
  String get workoutDescription =>
      pick('Workout description', 'Descripción del WOD');
  String get workoutWriteWod => pick('Write the WOD...', 'Escribe el WOD...');
  String get workoutCreate => pick('Create workout', 'Crear WOD');

  String get workoutFallbackTitle => pick('Workout', 'WOD');
  String get workoutEdit => pick('Edit', 'Editar');
  String get workoutDelete => pick('Delete', 'Eliminar');
  String get workoutPostScore => pick('Post score', 'Sube tu resultado');
  String get workoutFirstComment =>
      pick('Be the first to comment', 'Sé el primero en comentar');
  String workoutCommentCount(int count) => count == 1
      ? pick('1 comment', '1 comentario')
      : pick('$count comments', '$count comentarios');
  String workoutLikesCount(int count) => count == 1
      ? pick('1 like', '1 me gusta')
      : pick('$count likes', '$count me gusta');
  String get workoutNotFound =>
      pick('Workout not found.', 'WOD no encontrado.');
  String get workoutPostScoreComments =>
      pick('Post score / comments', 'Resultado / comentarios');
  String get workoutCommentHint => pick('How did it go?', '¿Cómo te fue?');
  String get workoutNoComments =>
      pick('No comments yet.', 'Aún no hay comentarios.');
  String get userFallbackName => pick('User', 'Usuario');

  String get workoutEditTitle => pick('Edit workout', 'Editar WOD');
  String get workoutSaveChanges => pick('Save changes', 'Guardar cambios');
  String workoutUpdateError(Object e) =>
      pick('Update workout error: $e', 'Error al actualizar WOD: $e');

  String get workoutsPrograms => pick('Programs', 'Programas');
  String get workoutsDeleteTitle => pick('Delete workout?', '¿Eliminar WOD?');
  String get workoutsDeleteMessage =>
      pick('This cannot be undone.', 'Esta acción no se puede deshacer.');
  String get workoutsNoToday =>
      pick('No workouts for today yet.', 'Todavía no hay WODs para hoy.');
  String workoutsLoadError(Object e) =>
      pick('Workouts load error: $e', 'Error cargando WODs: $e');
  String workoutsDeleteError(Object e) =>
      pick('Delete workout error: $e', 'Error al eliminar WOD: $e');

  String get exploreTitle => pick('Explore', 'Explorar');
  String get exploreSearchWorkouts =>
      pick('Search workouts...', 'Buscar WODs...');
  String get exploreAllPrograms => pick('All programs', 'Todos los programas');
  String get exploreNoWorkoutsFound =>
      pick('No workouts found.', 'No se encontraron WODs.');
  String exploreLoadError(Object e) =>
      pick('Explore load error: $e', 'Error cargando explorar: $e');
  String exploreDeleteWorkoutError(Object e) =>
      pick('Delete workout error: $e', 'Error al eliminar WOD: $e');

  String get notificationsTitle => pick('Notifications', 'Notificaciones');
  String get notificationsMarkRead => pick('Mark read', 'Marcar como leídas');
  String get notificationsEmpty =>
      pick('No notifications yet.', 'Aún no hay notificaciones.');
  String get notificationFallbackTitle => pick('Notification', 'Notificación');
  String notificationSent(String date) => pick('Sent $date', 'Enviado $date');
  String notificationScheduled(String date) =>
      pick('Scheduled $date', 'Programado $date');
  String notificationsLoadError(Object e) =>
      pick('Notifications error: $e', 'Error en notificaciones: $e');
  String notificationsMarkReadError(Object e) =>
      pick('Mark read error: $e', 'Error al marcar como leídas: $e');

  String get profileLanguage => pick('Language', 'Idioma');
  String get profileEnglish => pick('English', 'Inglés');
  String get profileSpanish => pick('Spanish', 'Español');

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
