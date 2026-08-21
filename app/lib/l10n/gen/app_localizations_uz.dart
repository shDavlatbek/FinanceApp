// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get appTitle => 'Tally';

  @override
  String get navHome => 'Bosh sahifa';

  @override
  String get navHistory => 'Tarix';

  @override
  String get navStats => 'Statistika';

  @override
  String get navSettings => 'Sozlamalar';

  @override
  String get commonIncome => 'Daromad';

  @override
  String get commonExpense => 'Xarajat';

  @override
  String get commonExpenses => 'Xarajatlar';

  @override
  String get commonSpent => 'Sarflandi';

  @override
  String get commonAll => 'Barchasi';

  @override
  String get commonCancel => 'Bekor qilish';

  @override
  String get commonUndo => 'Qaytarish';

  @override
  String get commonTryAgain => 'Qayta urinish';

  @override
  String get commonSaveChanges => 'Oʻzgarishlarni saqlash';

  @override
  String get commonAddEntry => 'Yozuv qoʻshish';

  @override
  String get commonToday => 'Bugun';

  @override
  String get commonYesterday => 'Kecha';

  @override
  String commonPercent({required int value}) {
    return '$value%';
  }

  @override
  String get homeNetThisMonth => 'SHU OYDAGI SOF QOLDIQ';

  @override
  String homeNetForMonth({required String month}) {
    return 'SOF · $month';
  }

  @override
  String get homeEmptyTitle => 'Sokin daftar';

  @override
  String get homeEmptyMessage =>
      'Birinchi yozuv bir bosish narida — yoki botga yozing.';

  @override
  String get homeSpendingSection => 'Xarajatlar';

  @override
  String get homeNothingSpentTitle => 'Sarf boʻlmadi';

  @override
  String get homeNothingSpentMessage => 'Bu oyda xarajat qayd etilmagan.';

  @override
  String get homeRecentSection => 'Soʻnggilar';

  @override
  String get homeNoEntriesTitle => 'Hali yozuvlar yoʻq';

  @override
  String get homeNoEntriesMessage => 'Soʻnggi amaliyotlar shu yerda koʻrinadi.';

  @override
  String get historyTitle => 'Tarix';

  @override
  String get historySearchHint => 'Izohlardan qidirish';

  @override
  String get historyCategoryFilter => 'Turkum';

  @override
  String get historyFilterByCategoryTitle => 'Turkum boʻyicha filtr';

  @override
  String get historyNoMatchesTitle => 'Mos keladigani yoʻq';

  @override
  String get historyNoMatchesMessage =>
      'Boshqa soʻrov kiriting yoki filtrlarni tozalang.';

  @override
  String get historyEmptyTitle => 'Bu yerda hali hech nima yoʻq';

  @override
  String get historyEmptyMessage =>
      'Bu yerda yoki Telegram orqali qoʻshgan yozuvlaringiz shu daftarga tushadi.';

  @override
  String historyDeletedItem({required String label}) {
    return 'Oʻchirildi · $label';
  }

  @override
  String get statsTitle => 'Statistika';

  @override
  String statsNoDataTitle({required String month}) {
    return '$month uchun maʼlumot yoʻq';
  }

  @override
  String get statsNoIncomeMessage => 'Bu oyda daromad qayd etilmagan.';

  @override
  String get statsNoSpendingMessage => 'Bu oyda xarajat qayd etilmagan.';

  @override
  String get statsEarnedLabel => 'TOPILGAN';

  @override
  String get statsSpentLabel => 'SARFLANGAN';

  @override
  String statsLastMonths({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Soʻnggi $count oy',
      one: 'Soʻnggi oy',
    );
    return '$_temp0';
  }

  @override
  String statsSharePercent({required int percent, required String emoji}) {
    return '$percent% · $emoji';
  }

  @override
  String get categoriesTitle => 'Turkumlar';

  @override
  String get categoriesEmptyTitle => 'Turkumlar yoʻq';

  @override
  String get categoriesEmptyMessage =>
      'Tartibga solishni boshlash uchun quyida bittasini qoʻshing.';

  @override
  String get categoryNew => 'Yangi turkum';

  @override
  String get categoryEdit => 'Turkumni tahrirlash';

  @override
  String get categoryNameHint => 'Nomi';

  @override
  String get categoryEmojiLabel => 'EMOJI';

  @override
  String get categoryColorLabel => 'RANG';

  @override
  String get categoryCreate => 'Turkum yaratish';

  @override
  String get categoryArchive => 'Arxivlash';

  @override
  String get categoryArchiveConfirmTitle => 'Turkum arxivlansinmi?';

  @override
  String categoryArchiveConfirmMessage({required String name}) {
    return '“$name” tanlov roʻyxatlaridan yashiriladi. Mavjud amaliyotlar uni saqlab qoladi.';
  }

  @override
  String get entryNewTitle => 'Yangi yozuv';

  @override
  String get entryEditTitle => 'Yozuvni tahrirlash';

  @override
  String get entryNoteHint => 'Izoh qoʻshish';

  @override
  String get entryPickDate => 'Sanani tanlash';

  @override
  String get entryAddIncome => 'Daromad qoʻshish';

  @override
  String get entryAddExpense => 'Xarajat qoʻshish';

  @override
  String entryDeleted({required String amount}) {
    return '$amount oʻchirildi';
  }

  @override
  String get transactionUncategorized => 'Turkumsiz';

  @override
  String get sourceTelegram => 'Telegram';

  @override
  String get settingsTitle => 'Sozlamalar';

  @override
  String get settingsSyncSection => 'Sinxronizatsiya';

  @override
  String get settingsPreferencesSection => 'Parametrlar';

  @override
  String get settingsAboutSection => 'Ilova haqida';

  @override
  String get settingsCurrency => 'Valyuta';

  @override
  String get settingsCategoriesValue => 'Tahrirlash va tartiblash';

  @override
  String get settingsAppearanceLabel => 'KOʻRINISH';

  @override
  String get settingsLanguageLabel => 'TIL';

  @override
  String get settingsThemeDark => 'Tungi';

  @override
  String get settingsThemeLight => 'Kunduzgi';

  @override
  String get settingsThemeSystem => 'Tizimdagidek';

  @override
  String get settingsLanguageSystem => 'Tizim tili';

  @override
  String settingsVersion({required String version}) {
    return 'v$version';
  }

  @override
  String get settingsAboutBody =>
      'Maʼlumotlar shu qurilmada saqlanadigan, oʻzingizning Google Drive’ingiz orqali sinxronlanadigan va oʻzingiz joylashtirgan Telegram bot orqali yozib boriladigan pul hisobi. Maʼlumotlaringiz oʻz akkauntlaringizdan chiqmaydi.';

  @override
  String get syncIndicatorSyncing => 'Sinxronlanmoqda';

  @override
  String get syncIndicatorOffline => 'Oflayn';

  @override
  String get syncIndicatorIssue => 'Sinxronizatsiya nosozligi';

  @override
  String get syncStatusSyncing => 'Sinxronlanmoqda…';

  @override
  String get syncStatusConnected => 'Ulangan';

  @override
  String get syncStatusOffline => 'Oflayn — keyinroq qayta urinamiz';

  @override
  String get syncStatusStandalone => 'Mustaqil rejim';

  @override
  String get syncNeverSynced => 'Hali sinxronlanmagan';

  @override
  String syncLastSynced({required String time}) {
    return 'Sinxronlangan: $time';
  }

  @override
  String get syncRelativeJustNow => 'hozirgina';

  @override
  String syncRelativeMinutesAgo({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count daqiqa oldin',
      one: '$count daqiqa oldin',
    );
    return '$_temp0';
  }

  @override
  String syncRelativeHoursAgo({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count soat oldin',
      one: '$count soat oldin',
    );
    return '$_temp0';
  }

  @override
  String get syncErrorAuthRevoked =>
      'Google ruxsati bekor qilindi — Drive’ni qayta ulang';

  @override
  String get syncErrorAuthExpired =>
      'Google ruxsati muddati tugadi — Drive’ni qayta ulang';

  @override
  String get syncErrorDriveFull => 'Google Drive toʻlgan';

  @override
  String syncErrorDrive({required String message}) {
    return 'Drive xatosi: $message';
  }

  @override
  String get syncNowButton => 'Hozir sinxronlash';

  @override
  String get syncedSnack => 'Sinxronlandi';

  @override
  String get syncFailedSnack =>
      'Sinxronizatsiya boʻlmadi — yuqoridagi holatga qarang';

  @override
  String get driveStandaloneNotice =>
      'Mustaqil rejim — bu qurilmada hammasi oflayn ishlaydi. Telegram bot bilan sinxronlash uchun Google Drive’ni ulang; maʼlumotlaringiz oʻz Drive’ingizda oʻqiladigan JSON koʻrinishida qoladi.';

  @override
  String get driveNoClientNotice =>
      'Bu buildda Google OAuth mijozi yoʻq. Drive sinxronizatsiyasini yoqish uchun --dart-define=GOOGLE_CLIENT_ID=… va --dart-define=GOOGLE_CLIENT_SECRET=… bilan qayta yigʻing.';

  @override
  String get driveConnectButton => 'Google Drive’ni ulash';

  @override
  String get driveReconnectButton => 'Qayta ulash';

  @override
  String get driveDisconnectButton => 'Uzish';

  @override
  String get driveStepOpenLink => '1-QADAM — SHU HAVOLANI OCHING';

  @override
  String get driveStepEnterCode => '2-QADAM — SHU KODNI KIRITING';

  @override
  String get driveWaitingForApproval => 'Tasdiqlashingizni kutmoqdamiz…';

  @override
  String driveWaitingChecked({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tasdiqni kutmoqdamiz… ($count× tekshirildi)',
      one: 'Tasdiqni kutmoqdamiz… ($count× tekshirildi)',
    );
    return '$_temp0';
  }

  @override
  String get driveConnectedSnack => 'Google Drive ulandi — sinxronlanmoqda';

  @override
  String get driveDisconnectedSnack => 'Uzildi — mustaqil rejim';

  @override
  String get driveCodeCopied => 'Kod nusxalandi';

  @override
  String get driveLinkCopied => 'Havola nusxalandi — brauzerda oching';

  @override
  String get driveConnectionTitle => 'Google Drive';

  @override
  String driveConnectionTitleFolder({required String folder}) {
    return 'Google Drive · $folder/';
  }

  @override
  String get driveConnectionUnknownDevice =>
      'Bu qurilma oʻz snapshot faylini chop etadi.';

  @override
  String driveConnectionDevice({required String device, required String file}) {
    return 'Bu qurilma: $device · $file';
  }

  @override
  String get authErrorNoClient => 'Bu buildda Google OAuth mijozi yoʻq.';

  @override
  String get authErrorDenied => 'Siz Google’dagi soʻrovni rad etdingiz.';

  @override
  String get authErrorExpired => 'Kod muddati tugadi — qayta urinib koʻring.';

  @override
  String get authErrorNetwork =>
      'Google bilan aloqa yoʻq — tarmogʻingizni tekshiring.';

  @override
  String get seedCategoryGroceries => 'Oziq-ovqat';

  @override
  String get seedCategoryCafe => 'Kafe';

  @override
  String get seedCategoryTransport => 'Transport';

  @override
  String get seedCategoryHome => 'Uy';

  @override
  String get seedCategoryUtilities => 'Kommunal';

  @override
  String get seedCategoryHealth => 'Sogʻliq';

  @override
  String get seedCategoryShopping => 'Xaridlar';

  @override
  String get seedCategoryFun => 'Koʻngilochar';

  @override
  String get seedCategorySubscriptions => 'Obunalar';

  @override
  String get seedCategoryTravel => 'Sayohat';

  @override
  String get seedCategoryOther => 'Boshqa';

  @override
  String get seedCategorySalary => 'Maosh';

  @override
  String get seedCategoryFreelance => 'Frilans';

  @override
  String get seedCategoryGifts => 'Sovgʻalar';

  @override
  String get seedCategoryOtherIncome => 'Boshqa daromad';

  @override
  String get currencyUSD => 'AQSH dollari';

  @override
  String get currencyEUR => 'Yevro';

  @override
  String get currencyGBP => 'Funt sterling';

  @override
  String get currencyUAH => 'Ukraina grivnasi';

  @override
  String get currencyPLN => 'Polsha zlotiyi';

  @override
  String get currencyCZK => 'Chexiya kronasi';

  @override
  String get currencyCHF => 'Shveytsariya franki';

  @override
  String get currencySEK => 'Shvetsiya kronasi';

  @override
  String get currencyNOK => 'Norvegiya kronasi';

  @override
  String get currencyDKK => 'Daniya kronasi';

  @override
  String get currencyJPY => 'Yaponiya iyenasi';

  @override
  String get currencyCNY => 'Xitoy yuani';

  @override
  String get currencyINR => 'Hindiston rupiyasi';

  @override
  String get currencyCAD => 'Kanada dollari';

  @override
  String get currencyAUD => 'Avstraliya dollari';

  @override
  String get currencyNZD => 'Yangi Zelandiya dollari';

  @override
  String get currencyBRL => 'Braziliya reali';

  @override
  String get currencyMXN => 'Meksika pesosi';

  @override
  String get currencyTRY => 'Turkiya lirasi';

  @override
  String get currencyKRW => 'Janubiy Koreya voni';

  @override
  String get currencySGD => 'Singapur dollari';

  @override
  String get currencyHKD => 'Gonkong dollari';

  @override
  String get currencyILS => 'Isroil shekeli';

  @override
  String get currencyAED => 'BAA dirhami';

  @override
  String get currencyZAR => 'Janubiy Afrika rendi';

  @override
  String get currencyRUB => 'Rossiya rubli';

  @override
  String get currencyUZS => 'Oʻzbek soʻmi';

  @override
  String get currencyKZT => 'Qozogʻiston tengesi';

  @override
  String get periodDay => 'Kun';

  @override
  String get periodMonth => 'Oy';

  @override
  String get periodSwitchToDay => 'Kunlar boʻyicha koʻrsatish';

  @override
  String get periodSwitchToMonth => 'Butun oyni koʻrsatish';

  @override
  String get homeNetToday => 'BUGUNGI SOF QOLDIQ';

  @override
  String homeNetForDay({required String date}) {
    return 'SOF · $date';
  }

  @override
  String get homeNothingSpentDayTitle => 'Bugun hech narsa sarflanmadi';

  @override
  String get homeNothingSpentDayMessage => 'Hamyon uchun tinch kun.';

  @override
  String get homeDayEntriesSection => 'Yozuvlar';

  @override
  String get seedAccountCash => 'Naqd pul';

  @override
  String get seedAccountCard => 'Karta';

  @override
  String get seedAccountSavings => 'Jamgʻarma';

  @override
  String get seedAccountInvestments => 'Investitsiyalar';

  @override
  String get transactionTransfer => 'Oʻtkazma';

  @override
  String transactionTransferRoute({required String from, required String to}) {
    return '$from → $to';
  }

  @override
  String get periodRange => 'Oraliq';

  @override
  String get periodSwitchToRange => 'Ixtiyoriy sana oraligʻini koʻrsatish';

  @override
  String get periodPickDateHint => 'Koʻrsatilayotgan davrni oʻzgartirish';

  @override
  String get periodPickMonthTitle => 'Oyni tanlang';

  @override
  String get periodPickRangeTitle => 'Sana oraligʻini tanlang';

  @override
  String get periodRangeFrom => 'Dan';

  @override
  String get periodRangeTo => 'Gacha';

  @override
  String get periodApplyRange => 'Qoʻllash';

  @override
  String periodRangeDays({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kun',
      one: '$count kun',
    );
    return '$_temp0';
  }

  @override
  String get periodPresetLast7 => '7 kun';

  @override
  String get periodPresetLast30 => '30 kun';

  @override
  String get periodPresetThisMonth => 'Shu oy';

  @override
  String get periodPresetLastMonth => 'Oʻtgan oy';

  @override
  String get periodPresetThisYear => 'Shu yil';

  @override
  String get statsRangeTrendTitle => 'Oraliq boʻyicha';

  @override
  String homeNetForRange({required String range}) {
    return '$range SOF QOLDIQ';
  }

  @override
  String statsLastDays({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Soʻnggi $count kun',
      one: 'Soʻnggi kun',
    );
    return '$_temp0';
  }

  @override
  String get accountsTitle => 'Hisoblar';

  @override
  String get accountsTotalLabel => 'JAMI HISOBLARDA';

  @override
  String get accountsEmptyTitle => 'Hisob yoʻq';

  @override
  String get accountsEmptyMessage =>
      'Hamyon, karta yoki jamgʻarma qoʻshsangiz, pulingiz qayerda turganini koʻrasiz.';

  @override
  String get accountNew => 'Yangi hisob';

  @override
  String get accountEdit => 'Hisobni oʻzgartirish';

  @override
  String get accountCreate => 'Hisob yaratish';

  @override
  String get accountNameHint => 'Hisob nomi';

  @override
  String get accountEmojiLabel => 'Belgi';

  @override
  String get accountColorLabel => 'Rang';

  @override
  String get accountKindLabel => 'Turi';

  @override
  String get accountKindCash => 'Naqd pul';

  @override
  String get accountKindBank => 'Karta';

  @override
  String get accountKindSavings => 'Jamgʻarma';

  @override
  String get accountKindInvestment => 'Investitsiyalar';

  @override
  String get accountOpeningBalanceLabel => 'Boshlangʻich qoldiq';

  @override
  String get accountOpeningBalanceHelp =>
      'Hisob yuritishni boshlashdan avval hisobda boʻlgan summa. Kartadagi qarz minus bilan yoziladi.';

  @override
  String get accountArchive => 'Arxivga';

  @override
  String get accountArchiveConfirmTitle => 'Hisob arxivga olinsinmi?';

  @override
  String accountArchiveConfirmMessage({required String name}) {
    return '$name tanlash roʻyxatlaridan yoʻqoladi. Unga yozilgan barcha kirimlar tarixda qoladi.';
  }

  @override
  String accountArchivedSnack({required String name}) {
    return '$name arxivga olindi';
  }

  @override
  String get accountsDefaultLabel => 'Telegram bot yozadi';

  @override
  String get accountsDefaultHelp =>
      'Botga yozgan hamma narsa shu hisobga tushadi — u hech narsa soʻramaydi.';

  @override
  String get accountDefaultBadge => 'Bot';

  @override
  String accountSendTo({required String name}) {
    return '${name}ga yuborish';
  }

  @override
  String get accountsMoveMoney => 'Pul oʻtkazish';

  @override
  String get settingsAccountsValue => 'Qoldiqlar va asosiy hisob';

  @override
  String get commonTransfer => 'Oʻtkazma';

  @override
  String get entryAddTransfer => 'Pul oʻtkazish';

  @override
  String get entryFromAccount => 'Qayerdan';

  @override
  String get entryToAccount => 'Qayerga';

  @override
  String get entryAccountLabel => 'Hisob';

  @override
  String get entryTransferPickTwo => 'Ikki xil hisobni tanlang';

  @override
  String get entryTransferNoteHint => 'Bu nima uchun?';

  @override
  String get settingsBackupSection => 'Zaxira nusxa';

  @override
  String get backupExportJsonTitle => 'Nusxani saqlash';

  @override
  String get backupExportJsonSubtitle => 'JSON · tiklanadi';

  @override
  String get backupExportCsvTitle => 'Jadvalga eksport';

  @override
  String get backupExportCsvSubtitle => 'CSV · faqat oʻqish';

  @override
  String get backupImportTitle => 'Nusxani yuklash';

  @override
  String get backupImportSubtitle => 'Birlashadi · yangisi ustun';

  @override
  String get backupCsvNotice =>
      'Jadval oʻchirishlar va sozlamalarni saqlamaydi, shuning uchun bu faqat eksport — tiklash JSON nusxadan boʻladi.';

  @override
  String get backupImportConfirmTitle => 'Bu nusxa yuklansinmi?';

  @override
  String get backupImportConfirmMessage =>
      'Yozuvlar birlashtiriladi, har birining yangi versiyasi ustun boʻladi. Nusxadan keyin qoʻshgan narsalaringiz yoʻqolmaydi, ayni faylni ikkinchi marta yuklash esa hech narsani oʻzgartirmaydi.';

  @override
  String get backupImportConfirmAction => 'Yuklash';

  @override
  String backupSavedSnack({required String file}) {
    return '$file saqlandi';
  }

  @override
  String get backupCancelledSnack => 'Hech narsa saqlanmadi';

  @override
  String backupFailedSnack({required String message}) {
    return 'Saqlash boʻlmadi: $message';
  }

  @override
  String backupImportFailedSnack({required String message}) {
    return 'Faylni oʻqib boʻlmadi: $message';
  }

  @override
  String get backupImportNothingSnack =>
      'Birlashtirishga narsa yoʻq — maʼlumotlar allaqachon yangi';

  @override
  String backupImportedSnack({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count yozuv birlashtirildi',
      one: '$count yozuv birlashtirildi',
    );
    return '$_temp0';
  }

  @override
  String backupImportSkippedSnack({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notoʻgʻri yozuv oʻtkazib yuborildi',
      one: '$count notoʻgʻri yozuv oʻtkazib yuborildi',
    );
    return '$_temp0';
  }

  @override
  String get accountOpeningBalanceInvalid => 'Bu son emas';
}
