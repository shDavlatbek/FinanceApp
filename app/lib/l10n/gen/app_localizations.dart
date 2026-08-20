import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_uz.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('uz'),
  ];

  /// Application name. Brand — keep identical in every locale.
  ///
  /// In en, this message translates to:
  /// **'Tally'**
  String get appTitle;

  /// Bottom navigation label for the Home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation label for the History tab
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// Bottom navigation label for the Stats tab
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get navStats;

  /// Bottom navigation label for the Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Label for money coming in — chips, legends, filters
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get commonIncome;

  /// Label for a single outgoing transaction kind
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get commonExpense;

  /// Plural label for outgoing transactions, used as a filter chip
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get commonExpenses;

  /// Label for the total amount spent in a period
  ///
  /// In en, this message translates to:
  /// **'Spent'**
  String get commonSpent;

  /// Filter chip that clears the transaction-kind filter
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// Dismisses a dialog or an in-progress flow without acting
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Snackbar action that restores a just-deleted transaction
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// Button that retries a failed operation
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Primary button when editing an existing record
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get commonSaveChanges;

  /// Empty-state button that opens the transaction entry sheet
  ///
  /// In en, this message translates to:
  /// **'Add entry'**
  String get commonAddEntry;

  /// Label for the current calendar day
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get commonToday;

  /// Label for the previous calendar day
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get commonYesterday;

  /// A share of a total rendered as a percentage
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String commonPercent({required int value});

  /// Uppercase caption above the hero number when the current month is shown
  ///
  /// In en, this message translates to:
  /// **'NET THIS MONTH'**
  String get homeNetThisMonth;

  /// Uppercase caption above the hero number for a past month. The month is already formatted and uppercased.
  ///
  /// In en, this message translates to:
  /// **'NET · {month}'**
  String homeNetForMonth({required String month});

  /// Title of the Home empty state when nothing was recorded yet
  ///
  /// In en, this message translates to:
  /// **'A quiet ledger'**
  String get homeEmptyTitle;

  /// Body of the Home empty state
  ///
  /// In en, this message translates to:
  /// **'Your first entry is one tap away — or text the bot.'**
  String get homeEmptyMessage;

  /// Section header above the per-category spending bars
  ///
  /// In en, this message translates to:
  /// **'Spending'**
  String get homeSpendingSection;

  /// Title shown when the selected month has no expenses
  ///
  /// In en, this message translates to:
  /// **'Nothing spent'**
  String get homeNothingSpentTitle;

  /// Body shown when the selected month has no expenses
  ///
  /// In en, this message translates to:
  /// **'No expenses recorded this month.'**
  String get homeNothingSpentMessage;

  /// Section header above the five most recent transactions
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get homeRecentSection;

  /// Title of the empty Recent list
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get homeNoEntriesTitle;

  /// Body of the empty Recent list
  ///
  /// In en, this message translates to:
  /// **'Recent transactions will appear here.'**
  String get homeNoEntriesMessage;

  /// Screen title of the History tab
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// Placeholder in the note-search field
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get historySearchHint;

  /// Filter chip that opens the category picker
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get historyCategoryFilter;

  /// Title of the category-filter bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Filter by category'**
  String get historyFilterByCategoryTitle;

  /// Title shown when search and filters return nothing
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get historyNoMatchesTitle;

  /// Body shown when search and filters return nothing
  ///
  /// In en, this message translates to:
  /// **'Try a different search or clear the filters.'**
  String get historyNoMatchesMessage;

  /// Title of the History empty state with no filters applied
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get historyEmptyTitle;

  /// Body of the History empty state with no filters applied
  ///
  /// In en, this message translates to:
  /// **'Entries you add — here or via Telegram — land in this ledger.'**
  String get historyEmptyMessage;

  /// Snackbar after swiping a transaction away; the label is its note, or the formatted amount when it has none.
  ///
  /// In en, this message translates to:
  /// **'Deleted · {label}'**
  String historyDeletedItem({required String label});

  /// Screen title of the Stats tab
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get statsTitle;

  /// Empty-state title on Stats; the month is already formatted.
  ///
  /// In en, this message translates to:
  /// **'No data for {month}'**
  String statsNoDataTitle({required String month});

  /// Stats empty-state body while the Income kind is selected
  ///
  /// In en, this message translates to:
  /// **'No income recorded this month.'**
  String get statsNoIncomeMessage;

  /// Stats empty-state body while the Expense kind is selected
  ///
  /// In en, this message translates to:
  /// **'No spending recorded this month.'**
  String get statsNoSpendingMessage;

  /// Uppercase caption in the donut centre for total income
  ///
  /// In en, this message translates to:
  /// **'EARNED'**
  String get statsEarnedLabel;

  /// Uppercase caption in the donut centre for total spending
  ///
  /// In en, this message translates to:
  /// **'SPENT'**
  String get statsSpentLabel;

  /// Section header above the trend chart. Russian needs one/few/many/other.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Last month} other{Last {count} months}}'**
  String statsLastMonths({required int count});

  /// Share of the total plus the category emoji, under the donut centre amount
  ///
  /// In en, this message translates to:
  /// **'{percent}% · {emoji}'**
  String statsSharePercent({required int percent, required String emoji});

  /// Screen title of the Categories screen
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesTitle;

  /// Title shown when a kind has no categories left
  ///
  /// In en, this message translates to:
  /// **'No categories'**
  String get categoriesEmptyTitle;

  /// Body shown when a kind has no categories left
  ///
  /// In en, this message translates to:
  /// **'Add one below to start organizing.'**
  String get categoriesEmptyMessage;

  /// Button that opens the sheet for creating a category, and that sheet's title
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get categoryNew;

  /// Title of the category sheet when editing an existing category
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get categoryEdit;

  /// Placeholder in the category name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get categoryNameHint;

  /// Uppercase label above the emoji picker
  ///
  /// In en, this message translates to:
  /// **'EMOJI'**
  String get categoryEmojiLabel;

  /// Uppercase label above the color picker
  ///
  /// In en, this message translates to:
  /// **'COLOR'**
  String get categoryColorLabel;

  /// Primary button that saves a brand-new category
  ///
  /// In en, this message translates to:
  /// **'Create category'**
  String get categoryCreate;

  /// Button and dialog action that hides a category from pickers
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get categoryArchive;

  /// Title of the archive confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Archive category?'**
  String get categoryArchiveConfirmTitle;

  /// Body of the archive confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'“{name}” will be hidden from pickers. Existing transactions keep it.'**
  String categoryArchiveConfirmMessage({required String name});

  /// Title of the transaction sheet when adding
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get entryNewTitle;

  /// Title of the transaction sheet when editing
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get entryEditTitle;

  /// Placeholder in the transaction note field
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get entryNoteHint;

  /// Date chip that opens the calendar picker
  ///
  /// In en, this message translates to:
  /// **'Pick date'**
  String get entryPickDate;

  /// Primary button that saves a new income transaction
  ///
  /// In en, this message translates to:
  /// **'Add income'**
  String get entryAddIncome;

  /// Primary button that saves a new expense transaction
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get entryAddExpense;

  /// Snackbar after deleting a transaction from the edit sheet
  ///
  /// In en, this message translates to:
  /// **'Deleted {amount}'**
  String entryDeleted({required String amount});

  /// Fallback name when a transaction references a missing category
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get transactionUncategorized;

  /// Badge on transactions logged through the Telegram bot. Brand — keep identical.
  ///
  /// In en, this message translates to:
  /// **'Telegram'**
  String get sourceTelegram;

  /// Screen title of the Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Section header above the Google Drive card
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get settingsSyncSection;

  /// Section header above currency, categories, appearance and language
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferencesSection;

  /// Section header above the app description
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSection;

  /// Row title and picker title for the main currency
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrency;

  /// Trailing hint on the Categories row
  ///
  /// In en, this message translates to:
  /// **'Edit & reorder'**
  String get settingsCategoriesValue;

  /// Uppercase label above the theme selector
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE'**
  String get settingsAppearanceLabel;

  /// Uppercase label above the language selector
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get settingsLanguageLabel;

  /// Theme option: always dark
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Theme option: always light
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme option: follow the device setting
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// Language option: follow the device locale. The other options are endonyms (English, Русский, Oʻzbekcha) and are never translated.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// App version line in the About card
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String settingsVersion({required String version});

  /// One-paragraph description of the app in the About card
  ///
  /// In en, this message translates to:
  /// **'Local-first money tracking that syncs through your own Google Drive and logs from a self-hosted Telegram bot. Your data never leaves your own accounts.'**
  String get settingsAboutBody;

  /// Compact chip in the Home header while a sync pass runs
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncIndicatorSyncing;

  /// Compact chip in the Home header when the last pass failed at the network level
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncIndicatorOffline;

  /// Compact chip in the Home header when the last pass failed for a non-network reason
  ///
  /// In en, this message translates to:
  /// **'Sync issue'**
  String get syncIndicatorIssue;

  /// Settings sync status while a pass runs
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncStatusSyncing;

  /// Settings sync status when Drive is connected and quiet
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get syncStatusConnected;

  /// Settings sync status after a network failure
  ///
  /// In en, this message translates to:
  /// **'Offline — will retry'**
  String get syncStatusOffline;

  /// Settings sync status when no Google account is connected
  ///
  /// In en, this message translates to:
  /// **'Standalone mode'**
  String get syncStatusStandalone;

  /// Sub-line under the sync status when no pass ever succeeded
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get syncNeverSynced;

  /// Sub-line under the sync status; the time is a relative or absolute label
  ///
  /// In en, this message translates to:
  /// **'Last synced {time}'**
  String syncLastSynced({required String time});

  /// Relative time for the last minute
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get syncRelativeJustNow;

  /// Relative time in minutes. Russian needs one/few/many/other.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} min ago} other{{count} min ago}}'**
  String syncRelativeMinutesAgo({required int count});

  /// Relative time in hours. Russian needs one/few/many/other.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} h ago} other{{count} h ago}}'**
  String syncRelativeHoursAgo({required int count});

  /// Sync error after the refresh token was revoked
  ///
  /// In en, this message translates to:
  /// **'Google access was revoked — connect Drive again'**
  String get syncErrorAuthRevoked;

  /// Sync error after Drive answered 401
  ///
  /// In en, this message translates to:
  /// **'Google access expired — connect Drive again'**
  String get syncErrorAuthExpired;

  /// Sync error after Drive answered 403 storageQuotaExceeded
  ///
  /// In en, this message translates to:
  /// **'Google Drive is full'**
  String get syncErrorDriveFull;

  /// Sync error carrying Google's own untranslated message
  ///
  /// In en, this message translates to:
  /// **'Drive error: {message}'**
  String syncErrorDrive({required String message});

  /// Button that starts a sync pass immediately
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNowButton;

  /// Snackbar after a successful manual sync
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncedSnack;

  /// Snackbar after a failed manual sync
  ///
  /// In en, this message translates to:
  /// **'Sync failed — see status above'**
  String get syncFailedSnack;

  /// Notice box shown while no Google account is connected
  ///
  /// In en, this message translates to:
  /// **'Standalone mode — everything works offline on this device. Connect Google Drive to sync with the Telegram bot; your data stays in your own Drive as readable JSON.'**
  String get driveStandaloneNotice;

  /// Notice box shown when the app was built without the OAuth dart-defines. Keep the --dart-define flag names untranslated.
  ///
  /// In en, this message translates to:
  /// **'This build has no Google OAuth client compiled in. Rebuild with --dart-define=GOOGLE_CLIENT_ID=… and --dart-define=GOOGLE_CLIENT_SECRET=… to enable Drive sync.'**
  String get driveNoClientNotice;

  /// Button that starts the OAuth device flow
  ///
  /// In en, this message translates to:
  /// **'Connect Google Drive'**
  String get driveConnectButton;

  /// Button that restarts the OAuth device flow after Google access was revoked or expired
  ///
  /// In en, this message translates to:
  /// **'Reconnect Drive'**
  String get driveReconnectButton;

  /// Button that revokes the token and returns to standalone mode
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get driveDisconnectButton;

  /// Uppercase step label above the Google verification URL
  ///
  /// In en, this message translates to:
  /// **'STEP 1 — OPEN THIS LINK'**
  String get driveStepOpenLink;

  /// Uppercase step label above the user code
  ///
  /// In en, this message translates to:
  /// **'STEP 2 — ENTER THIS CODE'**
  String get driveStepEnterCode;

  /// Progress line before the first poll of the device flow
  ///
  /// In en, this message translates to:
  /// **'Waiting for you to approve…'**
  String get driveWaitingForApproval;

  /// Progress line with the poll counter. Russian needs one/few/many/other.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Waiting for approval… (checked {count}×)} other{Waiting for approval… (checked {count}×)}}'**
  String driveWaitingChecked({required int count});

  /// Snackbar after the device flow completes
  ///
  /// In en, this message translates to:
  /// **'Google Drive connected — syncing'**
  String get driveConnectedSnack;

  /// Snackbar after disconnecting the Google account
  ///
  /// In en, this message translates to:
  /// **'Disconnected — standalone mode'**
  String get driveDisconnectedSnack;

  /// Snackbar after copying the device user code
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get driveCodeCopied;

  /// Snackbar when no browser could be launched and the URL was copied instead
  ///
  /// In en, this message translates to:
  /// **'Link copied — open it in a browser'**
  String get driveLinkCopied;

  /// Title of the connection summary before the folder is known. Brand — keep identical.
  ///
  /// In en, this message translates to:
  /// **'Google Drive'**
  String get driveConnectionTitle;

  /// Title of the connection summary with the resolved Drive folder
  ///
  /// In en, this message translates to:
  /// **'Google Drive · {folder}/'**
  String driveConnectionTitleFolder({required String folder});

  /// Sub-line of the connection summary before the device identity loads
  ///
  /// In en, this message translates to:
  /// **'This device publishes its own snapshot file.'**
  String get driveConnectionUnknownDevice;

  /// Sub-line naming this peer and the snapshot file it owns
  ///
  /// In en, this message translates to:
  /// **'This device: {device} · {file}'**
  String driveConnectionDevice({required String device, required String file});

  /// Device-flow failure: the app was built without the OAuth dart-defines
  ///
  /// In en, this message translates to:
  /// **'This build has no Google OAuth client compiled in.'**
  String get authErrorNoClient;

  /// Device-flow failure: the user pressed Deny
  ///
  /// In en, this message translates to:
  /// **'You declined the request on Google.'**
  String get authErrorDenied;

  /// Device-flow failure: the user code timed out
  ///
  /// In en, this message translates to:
  /// **'The code expired — try again.'**
  String get authErrorExpired;

  /// Device-flow failure: the device is offline
  ///
  /// In en, this message translates to:
  /// **'No connection to Google — check your network.'**
  String get authErrorNetwork;

  /// Seed category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get seedCategoryGroceries;

  /// Seed category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Cafe'**
  String get seedCategoryCafe;

  /// Seed category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get seedCategoryTransport;

  /// Seed category for housing costs. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get seedCategoryHome;

  /// Seed category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get seedCategoryUtilities;

  /// Seed category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get seedCategoryHealth;

  /// Seed category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get seedCategoryShopping;

  /// Seed category for entertainment. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Fun'**
  String get seedCategoryFun;

  /// Seed category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get seedCategorySubscriptions;

  /// Seed category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get seedCategoryTravel;

  /// Catch-all seed expense category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get seedCategoryOther;

  /// Seed income category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get seedCategorySalary;

  /// Seed income category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Freelance'**
  String get seedCategoryFreelance;

  /// Seed income category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Gifts'**
  String get seedCategoryGifts;

  /// Catch-all seed income category. Shown only while the user has not renamed it.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get seedCategoryOtherIncome;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'US Dollar'**
  String get currencyUSD;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Euro'**
  String get currencyEUR;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'British Pound'**
  String get currencyGBP;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Ukrainian Hryvnia'**
  String get currencyUAH;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Polish Zloty'**
  String get currencyPLN;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Czech Koruna'**
  String get currencyCZK;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Swiss Franc'**
  String get currencyCHF;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Swedish Krona'**
  String get currencySEK;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Norwegian Krone'**
  String get currencyNOK;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Danish Krone'**
  String get currencyDKK;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Japanese Yen'**
  String get currencyJPY;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Chinese Yuan'**
  String get currencyCNY;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Indian Rupee'**
  String get currencyINR;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Canadian Dollar'**
  String get currencyCAD;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Australian Dollar'**
  String get currencyAUD;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'New Zealand Dollar'**
  String get currencyNZD;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Brazilian Real'**
  String get currencyBRL;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Mexican Peso'**
  String get currencyMXN;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Turkish Lira'**
  String get currencyTRY;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'South Korean Won'**
  String get currencyKRW;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Singapore Dollar'**
  String get currencySGD;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Hong Kong Dollar'**
  String get currencyHKD;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Israeli Shekel'**
  String get currencyILS;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'UAE Dirham'**
  String get currencyAED;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'South African Rand'**
  String get currencyZAR;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Russian Ruble'**
  String get currencyRUB;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Uzbek Sum'**
  String get currencyUZS;

  /// Currency name in the currency picker
  ///
  /// In en, this message translates to:
  /// **'Kazakhstani Tenge'**
  String get currencyKZT;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
