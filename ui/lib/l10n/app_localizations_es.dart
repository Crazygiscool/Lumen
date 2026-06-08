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
  String importedEntries(Object count) {
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
}
