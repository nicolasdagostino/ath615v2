import 'package:intl/intl.dart';

import '../locale/locale_controller.dart';

class AppStrings {
  const AppStrings();

  bool get isEs => localeController.locale.languageCode == 'es';

  String pick(String en, String es) => isEs ? es : en;

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String formatHeaderDate(DateTime date) {
    final locale = localeController.locale.languageCode;
    final dayName = _capitalize(DateFormat('EEEE', locale).format(date));
    final day = DateFormat('d', locale).format(date);
    final month = _capitalize(DateFormat('MMMM', locale).format(date));
    return '$dayName, $day $month';
  }

  String get defaultGymName => 'Athlete 615';

  String get appBrand => pick('ATHLETE LAB', 'ATHLETE LAB');
  String get profileHeaderTitle => pick('PROFILE', 'PERFIL');
  String get profileHeaderSubtitle =>
      pick('Account & settings', 'Cuenta y ajustes');
  String get dashboardHeaderSubtitle =>
      pick('Members & plans', 'Miembros y planes');
  String get all => pick('ALL', 'TODOS');
  String get coach => pick('COACH', 'COACH');
  String get spots => pick('SPOTS', 'PLAZAS');
  String get roster => pick('ROSTER', 'LISTA');
  String get attendance => pick('ATTENDANCE', 'ASISTENCIA');
  String get noBookingsYet => pick('No bookings yet.', 'Aún no hay reservas.');
  String get member => pick('Member', 'Miembro');
  String get workoutOptions => pick('WORKOUT OPTIONS', 'OPCIONES DEL WOD');
  String get athleteInvitationSent =>
      pick('Athlete invitation sent', 'Invitación enviada al atleta');

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

  String get bookingNoCreditsButton => pick('No credits', 'Sin créditos');

  String get bookingNoCreditsRemaining =>
      pick('No credits remaining', 'No te quedan créditos disponibles.');
  String get bookingGenericError =>
      pick('Could not book class.', 'No se pudo reservar la clase.');

  String bookingBookError(Object e) =>
      pick('Book class error: $e', 'Error al reservar clase: $e');
  String bookingCancelError(Object e) =>
      pick('Cancel booking error: $e', 'Error al cancelar reserva: $e');

  String get bookingActiveMembershipRequiredToBook => pick(
    'Active membership required to book classes.',
    'Necesitas una membresía activa para reservar clases.',
  );

  String get bookingLoadingClasses =>
      pick('Loading classes...', 'Cargando clases...');

  String get bookingEmptyTitle =>
      pick('No classes for this day', 'No hay clases este día');

  String get bookingEmptyMessage => pick(
    'Try another day or check again later.',
    'Prueba otro día o vuelve a revisar más tarde.',
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

  String get restDayTitle => pick('REST DAY', 'DÍA DE DESCANSO');
  String get restDayMessage => pick(
    "Resting is as important as work. Let your mind and body rest, do some mobility and stretching. Don't be tempted to train if you feel good.",
    'Descansar es tan importante como entrenar. Deja que tu mente y tu cuerpo recuperen, haz movilidad y estiramientos. No caigas en la tentación de entrenar si te sientes bien.',
  );
  String get imageSelected => pick('Image selected', 'Imagen seleccionada');
  String get changeImage => pick('Change image', 'Cambiar imagen');
  String get newImageSelected =>
      pick('New image selected', 'Nueva imagen seleccionada');
  String get currentImage => pick('Current image', 'Imagen actual');
  String get noImage => pick('No image', 'Sin imagen');

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

  String get notificationsClearTitle =>
      pick('Clear notifications?', '¿Vaciar notificaciones?');
  String get notificationsClearMessage => pick(
    'This will remove all notifications from your list.',
    'Esto eliminará todas las notificaciones de tu lista.',
  );
  String get clear => pick('Clear', 'Vaciar');
  String get allCaughtUp => pick('All caught up', 'Todo al día');
  String unreadCount(int count) => count == 1
      ? pick('1 unread', '1 sin leer')
      : pick('$count unread', '$count sin leer');
  String get noNotificationsTitle =>
      pick('No notifications', 'Sin notificaciones');

  String get authLoginTitle => pick('Athlete Lab', 'Athlete Lab');
  String get authLoginSubtitle =>
      pick('Login to your gym account.', 'Accede a tu cuenta del gym.');
  String get authLoginSection => pick('Login', 'Iniciar sesión');
  String get authEmail => pick('Email', 'Email');
  String get authPassword => pick('Password', 'Contraseña');
  String get authLoginButton => pick('Login', 'Entrar');
  String get authForgotPassword =>
      pick('Forgot password?', '¿Olvidaste tu contraseña?');
  String loginError(Object e) => pick('Login error: $e', 'Error al entrar: $e');

  String get authForgotTitle => pick('Forgot password', 'Recuperar contraseña');
  String get authForgotSubtitle => pick(
    'Enter your email and we will send you a reset link.',
    'Escribe tu email y te enviaremos un enlace para restablecerla.',
  );
  String get authResetLink => pick('Reset link', 'Enlace de recuperación');
  String get authSendResetLink => pick('Send reset link', 'Enviar enlace');
  String get authPasswordEmailSent =>
      pick('Password email sent.', 'Email de recuperación enviado.');
  String resetPasswordError(Object e) =>
      pick('Reset error: $e', 'Error al recuperar contraseña: $e');

  String get authSetNewPasswordTitle =>
      pick('Set new password', 'Nueva contraseña');
  String get authSetNewPasswordSubtitleReady =>
      pick('Create your new password.', 'Crea tu nueva contraseña.');
  String get authSetNewPasswordSubtitleWaiting =>
      pick('Opening secure invitation...', 'Abriendo invitación segura...');
  String get authNewPasswordSection => pick('New password', 'Nueva contraseña');
  String get authSavePassword => pick('Save password', 'Guardar contraseña');
  String get authWaitingForSession =>
      pick('Waiting for session...', 'Esperando sesión...');
  String get authSessionNotReady => pick(
    'Session not ready. Please open the email link again.',
    'La sesión no está lista. Abre nuevamente el enlace del email.',
  );
  String passwordUpdateError(Object e) =>
      pick('Password update error: $e', 'Error al actualizar contraseña: $e');

  String get profileLogoutConfirm => pick(
    'Are you sure you want to log out?',
    '¿Seguro que quieres cerrar sesión?',
  );
  String get profileDeleteConfirm => pick(
    'This action cannot be undone. Are you sure?',
    'Esta acción no se puede deshacer. ¿Estás seguro?',
  );
  String get couldNotOpenLink =>
      pick('Could not open link', 'No se pudo abrir el enlace');

  String get classOptions => pick('Class options', 'Opciones de clase');
  String get deleteThisClass =>
      pick('Delete this class', 'Eliminar esta clase');
  String get deleteThisAndFuture =>
      pick('Delete this + future', 'Eliminar esta y futuras');
  String get deleteClassTitle => pick('Delete class?', '¿Eliminar clase?');
  String get deleteFutureClassesTitle =>
      pick('Delete future classes?', '¿Eliminar clases futuras?');

  String get editClass => pick('Edit class', 'Editar clase');
  String get deleteOnlyThisClassMessage => pick(
    'This will permanently delete only this class.',
    'Esto eliminará definitivamente solo esta clase.',
  );
  String get deleteThisAndFutureSubtitle => pick(
    'Delete this class and upcoming repeats.',
    'Eliminar esta clase y las próximas repeticiones.',
  );
  String get deleteThisAndFutureMessage => pick(
    'This will permanently delete this class and all future repeated classes.',
    'Esto eliminará definitivamente esta clase y todas las clases repetidas futuras.',
  );

  String get managePlans => pick('Manage plans', 'Gestionar planes');
  String get plan => pick('Plan', 'Plan');
  String get planName => pick('Plan name', 'Nombre del plan');
  String get planType => pick('Plan type', 'Tipo de plan');
  String get classPack => pick('Class pack', 'Pack de clases');
  String get unlimited => pick('Unlimited', 'Ilimitado');
  String get credits => pick('Credits', 'Créditos');
  String get creditsLower => pick('credits', 'créditos');
  String get createPlan => pick('Create plan', 'Crear plan');
  String get noPlansYet => pick('No plans yet.', 'Aún no hay planes.');

  String get manageProgramsTitle =>
      pick('Manage programs', 'Gestionar programas');
  String get programName => pick('Program name', 'Nombre del programa');
  String get createProgram => pick('Create program', 'Crear programa');
  String get noProgramsYet => pick('No programs yet.', 'Aún no hay programas.');
  String get active => pick('Active', 'Activo');
  String get inactive => pick('Inactive', 'Inactivo');

  String get createClassTitle => pick('Create class', 'Crear clase');
  String get classNeedProgram => pick(
    'Create at least one active program before creating classes.',
    'Crea al menos un programa activo antes de crear clases.',
  );
  String get selectDate => pick('Select date', 'Seleccionar fecha');
  String get selectTime => pick('Select time', 'Seleccionar hora');
  String get time => pick('Time', 'Hora');
  String get repeatWeekly => pick('Repeat weekly', 'Repetir semanalmente');
  String get repeatWeeklyDescription => pick(
    'Creates this class for the next 8 weeks.',
    'Crea esta clase durante las próximas 8 semanas.',
  );
  String get repeatOn => pick('Repeat on', 'Repetir en');
  String get durationMinutes => pick('Duration minutes', 'Duración en minutos');
  String get capacity => pick('Capacity', 'Capacidad');
  String get chooseFutureDateTime =>
      pick('Choose a future date and time.', 'Elige una fecha y hora futuras.');
  String get noClassesOn => pick('No classes on', 'No hay clases el');

  List<String> get weekdayInitials => isEs
      ? ['L', 'M', 'M', 'J', 'V', 'S', 'D']
      : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  String get assignPlan => pick('Assign plan', 'Asignar plan');
  String get selectPlan => pick('Select plan', 'Seleccionar plan');
  String get assign => pick('Assign', 'Asignar');
  String get planAssigned => pick('Plan assigned', 'Plan asignado');
  String assignPlanError(Object e) =>
      pick('Assign plan error: $e', 'Error al asignar plan: $e');
  String get role => pick('Role', 'Rol');
  String get status => pick('Status', 'Estado');
  String get birthDate => pick('Birth date', 'Fecha de nacimiento');
  String get notSet => pick('Not set', 'Sin completar');
  String get recentClasses => pick('Recent classes', 'Clases recientes');
  String get milestone => pick('Milestone', 'Objetivo');
  String get classesAttended => pick('Classes attended', 'Clases asistidas');
  String get classesToGo => pick('to go', 'para llegar');
  String get personalRecords => pick('Personal records', 'Records personales');
  String get addRecord => pick('Add record', 'Añadir record');
  String get viewRecords => pick('View records', 'Ver records');
  String get classHistory => pick('Class history', 'Historial de clases');
  String get viewAllHistory =>
      pick('View all history', 'Ver historial completo');
  String get updateRecord => pick('Update record', 'Actualizar record');
  String get deleteRecordTitle => pick('Delete record?', '¿Eliminar record?');
  String get deleteRecordMsg => pick(
    'This personal record will be deleted.',
    'Este record será eliminado.',
  );
  String get exercise => pick('Exercise', 'Ejercicio');
  String get weightKg => pick('Weight kg', 'Peso kg');
  String get notes => pick('Notes', 'Notas');
  String get recordSaved => pick('Record saved', 'Record guardado');
  String get noRecordsYet => pick('No records yet.', 'Aún no hay records.');
  String saveRecordError(Object e) =>
      pick('Save record error: $e', 'Error al guardar record: $e');
  String deleteRecordError(Object e) =>
      pick('Delete record error: $e', 'Error al eliminar record: $e');
  String get noClasses => pick('No classes', 'Sin clases');
  String get classFallback => pick('Class', 'Clase');

  String get dashboardTitle => pick('Dashboard', 'Panel');
  String get inviteAthlete => pick('Invite athlete', 'Invitar atleta');
  String get inviteAthleteDescription => pick(
    'Send an invitation email to a new athlete.',
    'Envía una invitación por email a un nuevo atleta.',
  );
  String get athleteEmail => pick('Athlete email', 'Email del atleta');
  String get members => pick('Members', 'Miembros');
  String get searchMember => pick('Search member', 'Buscar miembro');
  String get noMembersFound =>
      pick('No members found.', 'No se encontraron miembros.');

  String get membershipTitle => pick('Membership', 'Membresía');
  String get activePlan => pick('Active plan', 'Plan activo');
  String get noActivePlan => pick('No active plan', 'Sin plan activo');
  String get expires => pick('Expires', 'Vence');

  String get assignedCredits => pick('Assigned credits', 'Créditos asignados');
  String get bookedCredits => pick('Booked credits', 'Créditos usados');
  String get cancelledCredits =>
      pick('Cancelled credits', 'Créditos devueltos');

  String get creditHistory => pick('Credit history', 'Historial de créditos');
  String get noCreditHistory =>
      pick('No credit history yet.', 'Aún no hay historial de créditos.');
  String get assigned => pick('Assigned', 'Asignado');
  String get booked => pick('Booked', 'Reservado');
  String get cancelled => pick('Cancelled', 'Cancelado');

  String get profileLanguage => pick('Language', 'Idioma');
  String get profileEnglish => pick('English', 'Inglés');
  String get profileSpanish => pick('Spanish', 'Español');

  String get personalInformation =>
      pick('Personal information', 'Información personal');
  String get editPersonalInformation =>
      pick('Edit personal information', 'Editar información personal');
  String get editMember => pick('Edit member', 'Editar miembro');
  String get memberUpdated => pick('Member updated', 'Miembro actualizado');
  String updateMemberError(Object e) =>
      pick('Update member error: $e', 'Error al actualizar miembro: $e');
  String get fullName => pick('Full name', 'Nombre completo');
  String get phone => pick('Phone', 'Teléfono');
  String get saveChanges => pick('Save changes', 'Guardar cambios');
  String get profileUpdated => pick('Profile updated', 'Perfil actualizado');
  String get updatePhoto => pick('Update photo', 'Actualizar foto');
  String get photoUpdated => pick('Photo updated', 'Foto actualizada');
  String updatePhotoError(Object e) =>
      pick('Update photo error: $e', 'Error al actualizar foto: $e');
  String updateProfileError(Object e) =>
      pick('Update profile error: $e', 'Error al actualizar perfil: $e');

  String get profileRole => pick('Role', 'Rol');
  String get profileGymName => pick('Gym name', 'Nombre del gym');
  String get profileSaveGymName =>
      pick('Save gym name', 'Guardar nombre del gym');
  String get profileNewPassword => pick('New password', 'Nueva contraseña');
  String get profileChangePassword =>
      pick('Change password', 'Cambiar contraseña');
  String get profileLogout => pick('Logout', 'Cerrar sesión');

  String get profilePrivacyPolicy =>
      pick('Privacy Policy', 'Política de privacidad');
  String get profileTerms => pick('Terms of Service', 'Términos de servicio');
  String get profileHelp => pick('Help Center', 'Centro de ayuda');

  String get error => pick('Error', 'Error');
  String get cancel => pick('Cancel', 'Cancelar');
  String get delete => pick('Delete', 'Eliminar');
  String get deleteWorkoutTitle => pick('Delete workout?', '¿Eliminar WOD?');
  String get deleteWorkoutMsg =>
      pick('This cannot be undone.', 'Esta acción no se puede deshacer.');

  String get selectDateTime =>
      pick('Select date and time', 'Selecciona fecha y hora');
  String get selectProgram =>
      pick('Select a program', 'Selecciona un programa');
  String get classFuture => pick(
    'Class date and time must be in the future',
    'La clase debe ser en el futuro',
  );

  String get attended => pick('Attended', 'Asistió');
  String get noShow => pick('No show', 'No asistió');

  String workoutDetailError(Object e) =>
      pick('Workout detail error: $e', 'Error detalle WOD: $e');
  String programsLoadError(Object e) =>
      pick('Programs load error: $e', 'Error cargando programas: $e');
  String createProgramError(Object e) =>
      pick('Create program error: $e', 'Error creando programa: $e');
  String createWorkoutError(Object e) =>
      pick('Create workout error: $e', 'Error creando WOD: $e');
  String attendanceError(Object e) =>
      pick('Attendance error: $e', 'Error en asistencia: $e');
  String loadMembersError(Object e) =>
      pick('Load members error: $e', 'Error cargando miembros: $e');
  String inviteAthleteError(Object e) =>
      pick('Invite athlete error: $e', 'Error invitando atleta: $e');

  String get profileDeleteAccount => pick('Delete account', 'Eliminar cuenta');

  String get passwordUpdated =>
      pick('Password updated.', 'Contraseña actualizada.');
  String get gymNameUpdated =>
      pick('Gym name updated.', 'Nombre del gym actualizado.');
  String updateGymError(Object error) =>
      pick('Update gym error: $error', 'Error al actualizar el gym: $error');
  String deleteAccountError(Object error) => pick(
    'Delete account error: $error',
    'Error al eliminar la cuenta: $error',
  );
}

const appStrings = AppStrings();
