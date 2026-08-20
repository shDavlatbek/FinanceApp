// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Tally';

  @override
  String get navHome => 'Home';

  @override
  String get navHistory => 'History';

  @override
  String get navStats => 'Stats';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonIncome => 'Income';

  @override
  String get commonExpense => 'Expense';

  @override
  String get commonExpenses => 'Expenses';

  @override
  String get commonSpent => 'Spent';

  @override
  String get commonAll => 'All';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonSaveChanges => 'Save changes';

  @override
  String get commonAddEntry => 'Add entry';

  @override
  String get commonToday => 'Today';

  @override
  String get commonYesterday => 'Yesterday';

  @override
  String commonPercent({required int value}) {
    return '$value%';
  }

  @override
  String get homeNetThisMonth => 'NET THIS MONTH';

  @override
  String homeNetForMonth({required String month}) {
    return 'NET · $month';
  }

  @override
  String get homeEmptyTitle => 'A quiet ledger';

  @override
  String get homeEmptyMessage =>
      'Your first entry is one tap away — or text the bot.';

  @override
  String get homeSpendingSection => 'Spending';

  @override
  String get homeNothingSpentTitle => 'Nothing spent';

  @override
  String get homeNothingSpentMessage => 'No expenses recorded this month.';

  @override
  String get homeRecentSection => 'Recent';

  @override
  String get homeNoEntriesTitle => 'No entries yet';

  @override
  String get homeNoEntriesMessage => 'Recent transactions will appear here.';

  @override
  String get historyTitle => 'History';

  @override
  String get historySearchHint => 'Search notes';

  @override
  String get historyCategoryFilter => 'Category';

  @override
  String get historyFilterByCategoryTitle => 'Filter by category';

  @override
  String get historyNoMatchesTitle => 'No matches';

  @override
  String get historyNoMatchesMessage =>
      'Try a different search or clear the filters.';

  @override
  String get historyEmptyTitle => 'Nothing here yet';

  @override
  String get historyEmptyMessage =>
      'Entries you add — here or via Telegram — land in this ledger.';

  @override
  String historyDeletedItem({required String label}) {
    return 'Deleted · $label';
  }

  @override
  String get statsTitle => 'Stats';

  @override
  String statsNoDataTitle({required String month}) {
    return 'No data for $month';
  }

  @override
  String get statsNoIncomeMessage => 'No income recorded this month.';

  @override
  String get statsNoSpendingMessage => 'No spending recorded this month.';

  @override
  String get statsEarnedLabel => 'EARNED';

  @override
  String get statsSpentLabel => 'SPENT';

  @override
  String statsLastMonths({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Last $count months',
      one: 'Last month',
    );
    return '$_temp0';
  }

  @override
  String statsSharePercent({required int percent, required String emoji}) {
    return '$percent% · $emoji';
  }

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get categoriesEmptyTitle => 'No categories';

  @override
  String get categoriesEmptyMessage => 'Add one below to start organizing.';

  @override
  String get categoryNew => 'New category';

  @override
  String get categoryEdit => 'Edit category';

  @override
  String get categoryNameHint => 'Name';

  @override
  String get categoryEmojiLabel => 'EMOJI';

  @override
  String get categoryColorLabel => 'COLOR';

  @override
  String get categoryCreate => 'Create category';

  @override
  String get categoryArchive => 'Archive';

  @override
  String get categoryArchiveConfirmTitle => 'Archive category?';

  @override
  String categoryArchiveConfirmMessage({required String name}) {
    return '“$name” will be hidden from pickers. Existing transactions keep it.';
  }

  @override
  String get entryNewTitle => 'New entry';

  @override
  String get entryEditTitle => 'Edit entry';

  @override
  String get entryNoteHint => 'Add a note';

  @override
  String get entryPickDate => 'Pick date';

  @override
  String get entryAddIncome => 'Add income';

  @override
  String get entryAddExpense => 'Add expense';

  @override
  String entryDeleted({required String amount}) {
    return 'Deleted $amount';
  }

  @override
  String get transactionUncategorized => 'Uncategorized';

  @override
  String get sourceTelegram => 'Telegram';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSyncSection => 'Sync';

  @override
  String get settingsPreferencesSection => 'Preferences';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsCategoriesValue => 'Edit & reorder';

  @override
  String get settingsAppearanceLabel => 'APPEARANCE';

  @override
  String get settingsLanguageLabel => 'LANGUAGE';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String settingsVersion({required String version}) {
    return 'v$version';
  }

  @override
  String get settingsAboutBody =>
      'Local-first money tracking that syncs through your own Google Drive and logs from a self-hosted Telegram bot. Your data never leaves your own accounts.';

  @override
  String get syncIndicatorSyncing => 'Syncing';

  @override
  String get syncIndicatorOffline => 'Offline';

  @override
  String get syncIndicatorIssue => 'Sync issue';

  @override
  String get syncStatusSyncing => 'Syncing…';

  @override
  String get syncStatusConnected => 'Connected';

  @override
  String get syncStatusOffline => 'Offline — will retry';

  @override
  String get syncStatusStandalone => 'Standalone mode';

  @override
  String get syncNeverSynced => 'Never synced';

  @override
  String syncLastSynced({required String time}) {
    return 'Last synced $time';
  }

  @override
  String get syncRelativeJustNow => 'just now';

  @override
  String syncRelativeMinutesAgo({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '$count min ago',
    );
    return '$_temp0';
  }

  @override
  String syncRelativeHoursAgo({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count h ago',
      one: '$count h ago',
    );
    return '$_temp0';
  }

  @override
  String get syncErrorAuthRevoked =>
      'Google access was revoked — connect Drive again';

  @override
  String get syncErrorAuthExpired =>
      'Google access expired — connect Drive again';

  @override
  String get syncErrorDriveFull => 'Google Drive is full';

  @override
  String syncErrorDrive({required String message}) {
    return 'Drive error: $message';
  }

  @override
  String get syncNowButton => 'Sync now';

  @override
  String get syncedSnack => 'Synced';

  @override
  String get syncFailedSnack => 'Sync failed — see status above';

  @override
  String get driveStandaloneNotice =>
      'Standalone mode — everything works offline on this device. Connect Google Drive to sync with the Telegram bot; your data stays in your own Drive as readable JSON.';

  @override
  String get driveNoClientNotice =>
      'This build has no Google OAuth client compiled in. Rebuild with --dart-define=GOOGLE_CLIENT_ID=… and --dart-define=GOOGLE_CLIENT_SECRET=… to enable Drive sync.';

  @override
  String get driveConnectButton => 'Connect Google Drive';

  @override
  String get driveReconnectButton => 'Reconnect Drive';

  @override
  String get driveDisconnectButton => 'Disconnect';

  @override
  String get driveStepOpenLink => 'STEP 1 — OPEN THIS LINK';

  @override
  String get driveStepEnterCode => 'STEP 2 — ENTER THIS CODE';

  @override
  String get driveWaitingForApproval => 'Waiting for you to approve…';

  @override
  String driveWaitingChecked({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Waiting for approval… (checked $count×)',
      one: 'Waiting for approval… (checked $count×)',
    );
    return '$_temp0';
  }

  @override
  String get driveConnectedSnack => 'Google Drive connected — syncing';

  @override
  String get driveDisconnectedSnack => 'Disconnected — standalone mode';

  @override
  String get driveCodeCopied => 'Code copied';

  @override
  String get driveLinkCopied => 'Link copied — open it in a browser';

  @override
  String get driveConnectionTitle => 'Google Drive';

  @override
  String driveConnectionTitleFolder({required String folder}) {
    return 'Google Drive · $folder/';
  }

  @override
  String get driveConnectionUnknownDevice =>
      'This device publishes its own snapshot file.';

  @override
  String driveConnectionDevice({required String device, required String file}) {
    return 'This device: $device · $file';
  }

  @override
  String get authErrorNoClient =>
      'This build has no Google OAuth client compiled in.';

  @override
  String get authErrorDenied => 'You declined the request on Google.';

  @override
  String get authErrorExpired => 'The code expired — try again.';

  @override
  String get authErrorNetwork =>
      'No connection to Google — check your network.';

  @override
  String get seedCategoryGroceries => 'Groceries';

  @override
  String get seedCategoryCafe => 'Cafe';

  @override
  String get seedCategoryTransport => 'Transport';

  @override
  String get seedCategoryHome => 'Home';

  @override
  String get seedCategoryUtilities => 'Utilities';

  @override
  String get seedCategoryHealth => 'Health';

  @override
  String get seedCategoryShopping => 'Shopping';

  @override
  String get seedCategoryFun => 'Fun';

  @override
  String get seedCategorySubscriptions => 'Subscriptions';

  @override
  String get seedCategoryTravel => 'Travel';

  @override
  String get seedCategoryOther => 'Other';

  @override
  String get seedCategorySalary => 'Salary';

  @override
  String get seedCategoryFreelance => 'Freelance';

  @override
  String get seedCategoryGifts => 'Gifts';

  @override
  String get seedCategoryOtherIncome => 'Other income';

  @override
  String get currencyUSD => 'US Dollar';

  @override
  String get currencyEUR => 'Euro';

  @override
  String get currencyGBP => 'British Pound';

  @override
  String get currencyUAH => 'Ukrainian Hryvnia';

  @override
  String get currencyPLN => 'Polish Zloty';

  @override
  String get currencyCZK => 'Czech Koruna';

  @override
  String get currencyCHF => 'Swiss Franc';

  @override
  String get currencySEK => 'Swedish Krona';

  @override
  String get currencyNOK => 'Norwegian Krone';

  @override
  String get currencyDKK => 'Danish Krone';

  @override
  String get currencyJPY => 'Japanese Yen';

  @override
  String get currencyCNY => 'Chinese Yuan';

  @override
  String get currencyINR => 'Indian Rupee';

  @override
  String get currencyCAD => 'Canadian Dollar';

  @override
  String get currencyAUD => 'Australian Dollar';

  @override
  String get currencyNZD => 'New Zealand Dollar';

  @override
  String get currencyBRL => 'Brazilian Real';

  @override
  String get currencyMXN => 'Mexican Peso';

  @override
  String get currencyTRY => 'Turkish Lira';

  @override
  String get currencyKRW => 'South Korean Won';

  @override
  String get currencySGD => 'Singapore Dollar';

  @override
  String get currencyHKD => 'Hong Kong Dollar';

  @override
  String get currencyILS => 'Israeli Shekel';

  @override
  String get currencyAED => 'UAE Dirham';

  @override
  String get currencyZAR => 'South African Rand';

  @override
  String get currencyRUB => 'Russian Ruble';

  @override
  String get currencyUZS => 'Uzbek Sum';

  @override
  String get currencyKZT => 'Kazakhstani Tenge';
}
