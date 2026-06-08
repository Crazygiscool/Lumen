// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Lumen';

  @override
  String get journal => 'Journal';

  @override
  String get notes => 'Notes';

  @override
  String get tasks => 'Tâches';

  @override
  String get kanban => 'Kanban';

  @override
  String get mindMap => 'Carte Mentale';

  @override
  String get settings => 'Paramètres';

  @override
  String get lock => 'Verrouiller';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get search => 'Rechercher';

  @override
  String get searchHint => 'Rechercher des entrées...';

  @override
  String get all => 'Tout';

  @override
  String get addEntry => 'Ajouter une Entrée';

  @override
  String get importStoic => 'Importer depuis Stoic';

  @override
  String get selectStoicExport =>
      'Sélectionner l\'export Stoic (dossier ou .zip)';

  @override
  String get enterPassword => 'Entrer le mot de passe';

  @override
  String get password => 'Mot de passe';

  @override
  String get startImport => 'Lancer l\'importation';

  @override
  String get importComplete => 'Importation terminée';

  @override
  String importedEntries(Object count) {
    return '$count entrées importées';
  }

  @override
  String get done => 'Terminé';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get confirmDelete => 'Supprimer cette entrée ?';

  @override
  String get typeQueryToSearch => 'Tapez une requête pour rechercher';

  @override
  String get noResultsFound => 'Aucun résultat trouvé';

  @override
  String get untitled => '(sans titre)';

  @override
  String get focusMode => 'Mode focus (Ctrl+.)';

  @override
  String get searchShortcut => 'Rechercher (Ctrl+F)';

  @override
  String get newEntry => 'Nouvelle Entrée';

  @override
  String get selectKind => 'Sélectionner le type';

  @override
  String get entryBody => 'Corps de l\'entrée';

  @override
  String get author => 'Auteur';

  @override
  String get created => 'Créé';

  @override
  String get statusTodo => 'à faire';

  @override
  String get statusInProgress => 'en_cours';

  @override
  String get statusDone => 'terminé';

  @override
  String get enterPasswordToDecrypt =>
      'Cette entrée est chiffrée. Entrez le mot de passe pour déchiffrer.';
}
