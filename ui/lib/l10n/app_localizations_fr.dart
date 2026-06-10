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
  String importedEntries(int count) {
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
