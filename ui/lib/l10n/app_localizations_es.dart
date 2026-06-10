// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Lumen';

  @override
  String get journal => 'Diario';

  @override
  String get notes => 'Notas';

  @override
  String get tasks => 'Tareas';

  @override
  String get kanban => 'Kanban';

  @override
  String get mindMap => 'Mapa Mental';

  @override
  String get settings => 'Ajustes';

  @override
  String get lock => 'Bloquear';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get search => 'Buscar';

  @override
  String get searchHint => 'Buscar entradas...';

  @override
  String get all => 'Todo';

  @override
  String get addEntry => 'Añadir Entrada';

  @override
  String get importStoic => 'Importar de Stoic';

  @override
  String get selectStoicExport =>
      'Seleccionar exportación de Stoic (dir. o .zip)';

  @override
  String get enterPassword => 'Introducir Contraseña';

  @override
  String get password => 'Contraseña';

  @override
  String get startImport => 'Iniciar Importación';

  @override
  String get importComplete => 'Importación Completa';

  @override
  String importedEntries(int count) {
    return 'Se importaron $count entradas';
  }

  @override
  String get done => 'Hecho';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get confirmDelete => '¿Eliminar esta entrada?';

  @override
  String get typeQueryToSearch => 'Escribe una consulta para buscar';

  @override
  String get noResultsFound => 'No se encontraron resultados';

  @override
  String get untitled => '(sin título)';

  @override
  String get focusMode => 'Modo enfoque (Ctrl+.)';

  @override
  String get searchShortcut => 'Buscar (Ctrl+F)';

  @override
  String get newEntry => 'Nueva Entrada';

  @override
  String get selectKind => 'Seleccionar tipo';

  @override
  String get entryBody => 'Cuerpo de la entrada';

  @override
  String get author => 'Autor';

  @override
  String get created => 'Creado';

  @override
  String get statusTodo => 'pendiente';

  @override
  String get statusInProgress => 'en_progreso';

  @override
  String get statusDone => 'completado';

  @override
  String get enterPasswordToDecrypt =>
      'Esta entrada está encriptada. Introduce la contraseña para descifrar.';

  @override
  String get currentUser => 'Current User';

  @override
  String get userManagement => 'User Management';

  @override
  String get switchUser => 'Switch User';

  @override
  String get registerNewUser => 'Register New User';

  @override
  String get admin => 'Admin';

  @override
  String get member => 'Member';

  @override
  String get vaultPassword => 'Vault Password';

  @override
  String get newUsername => 'New Username';

  @override
  String get register => 'Register';

  @override
  String get account => 'Account';

  @override
  String get security => 'Security';

  @override
  String get setPassword => 'Set Password';

  @override
  String get changePassword => 'Change Password';

  @override
  String get lockOnStart => 'Lock on Start';

  @override
  String get general => 'General';

  @override
  String get theme => 'Theme';

  @override
  String get notifications => 'Notifications';

  @override
  String get sync => 'Sync';

  @override
  String get syncSettings => 'Sync Settings';

  @override
  String get data => 'Data';

  @override
  String get exportImport => 'Export / Import';

  @override
  String get advanced => 'Advanced';

  @override
  String get developerMode => 'Developer Mode';

  @override
  String get resetApp => 'Reset App';

  @override
  String get welcomeToLumen => 'Welcome to Lumen';

  @override
  String get lumenDescription =>
      'A digital sanctuary for your thoughts. Private, encrypted, and offline-first.';

  @override
  String get discoverFeatures => 'Discover Features';

  @override
  String get whyLumen => 'Why Lumen?';

  @override
  String get aesEncryption => 'AES-256 Encryption';

  @override
  String get encryptionDesc =>
      'Your data is encrypted before it ever touches the disk.';

  @override
  String get expressiveJournaling => 'Expressive Journaling';

  @override
  String get journalingDesc =>
      'Capture moods, prompts, and rich text reflections.';

  @override
  String get deepProductivity => 'Deep Productivity';

  @override
  String get productivityDesc =>
      'Integrated Kanban boards, Mind Maps, and Task tracking.';

  @override
  String get modularExtensible => 'Modular & Extensible';

  @override
  String get modularDesc =>
      'A trait-based plugin system to build your own tools.';

  @override
  String get back => 'Back';

  @override
  String get getStarted => 'Get Started';

  @override
  String get secureYourVault => 'Secure Your Vault';

  @override
  String get setPasswordDesc =>
      'Set a master password. This cannot be recovered if lost.';

  @override
  String get preferredUsername => 'Preferred Username (Author)';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get createVault => 'Create Vault';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get passwordCannotBeEmpty => 'Password cannot be empty';

  @override
  String get failedToSetPassword => 'Failed to set password';
}
