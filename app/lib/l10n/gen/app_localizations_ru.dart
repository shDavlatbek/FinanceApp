// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Tally';

  @override
  String get navHome => 'Главная';

  @override
  String get navHistory => 'История';

  @override
  String get navStats => 'Статистика';

  @override
  String get navSettings => 'Настройки';

  @override
  String get commonIncome => 'Доход';

  @override
  String get commonExpense => 'Расход';

  @override
  String get commonExpenses => 'Расходы';

  @override
  String get commonSpent => 'Потрачено';

  @override
  String get commonAll => 'Все';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonUndo => 'Вернуть';

  @override
  String get commonTryAgain => 'Попробовать снова';

  @override
  String get commonSaveChanges => 'Сохранить';

  @override
  String get commonAddEntry => 'Добавить запись';

  @override
  String get commonToday => 'Сегодня';

  @override
  String get commonYesterday => 'Вчера';

  @override
  String commonPercent({required int value}) {
    return '$value%';
  }

  @override
  String get homeNetThisMonth => 'ИТОГ ЗА МЕСЯЦ';

  @override
  String homeNetForMonth({required String month}) {
    return 'ИТОГ · $month';
  }

  @override
  String get homeEmptyTitle => 'Тихая книга';

  @override
  String get homeEmptyMessage =>
      'Первая запись — в одно касание или сообщением боту.';

  @override
  String get homeSpendingSection => 'Траты';

  @override
  String get homeNothingSpentTitle => 'Трат нет';

  @override
  String get homeNothingSpentMessage => 'В этом месяце расходов не было.';

  @override
  String get homeRecentSection => 'Последние';

  @override
  String get homeNoEntriesTitle => 'Записей пока нет';

  @override
  String get homeNoEntriesMessage => 'Последние операции появятся здесь.';

  @override
  String get historyTitle => 'История';

  @override
  String get historySearchHint => 'Поиск по заметкам';

  @override
  String get historyCategoryFilter => 'Категория';

  @override
  String get historyFilterByCategoryTitle => 'Фильтр по категории';

  @override
  String get historyNoMatchesTitle => 'Ничего не найдено';

  @override
  String get historyNoMatchesMessage => 'Измените запрос или сбросьте фильтры.';

  @override
  String get historyEmptyTitle => 'Здесь пока пусто';

  @override
  String get historyEmptyMessage =>
      'Записи — добавленные здесь или через Telegram — попадут в эту книгу.';

  @override
  String historyDeletedItem({required String label}) {
    return 'Удалено · $label';
  }

  @override
  String get statsTitle => 'Статистика';

  @override
  String statsNoDataTitle({required String month}) {
    return 'Нет данных за $month';
  }

  @override
  String get statsNoIncomeMessage => 'В этом месяце доходов не было.';

  @override
  String get statsNoSpendingMessage => 'В этом месяце трат не было.';

  @override
  String get statsEarnedLabel => 'ЗАРАБОТАНО';

  @override
  String get statsSpentLabel => 'ПОТРАЧЕНО';

  @override
  String statsLastMonths({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Последние $count месяца',
      many: 'Последние $count месяцев',
      few: 'Последние $count месяца',
      one: 'Последний месяц',
    );
    return '$_temp0';
  }

  @override
  String statsSharePercent({required int percent, required String emoji}) {
    return '$percent% · $emoji';
  }

  @override
  String get categoriesTitle => 'Категории';

  @override
  String get categoriesEmptyTitle => 'Категорий нет';

  @override
  String get categoriesEmptyMessage =>
      'Добавьте первую, чтобы навести порядок.';

  @override
  String get categoryNew => 'Новая категория';

  @override
  String get categoryEdit => 'Изменить категорию';

  @override
  String get categoryNameHint => 'Название';

  @override
  String get categoryEmojiLabel => 'ЭМОДЗИ';

  @override
  String get categoryColorLabel => 'ЦВЕТ';

  @override
  String get categoryCreate => 'Создать категорию';

  @override
  String get categoryArchive => 'В архив';

  @override
  String get categoryArchiveConfirmTitle => 'Убрать категорию в архив?';

  @override
  String categoryArchiveConfirmMessage({required String name}) {
    return '«$name» исчезнет из списков выбора. Существующие операции её сохранят.';
  }

  @override
  String get entryNewTitle => 'Новая запись';

  @override
  String get entryEditTitle => 'Изменить запись';

  @override
  String get entryNoteHint => 'Добавить заметку';

  @override
  String get entryPickDate => 'Выбрать дату';

  @override
  String get entryAddIncome => 'Добавить доход';

  @override
  String get entryAddExpense => 'Добавить расход';

  @override
  String entryDeleted({required String amount}) {
    return 'Удалено $amount';
  }

  @override
  String get transactionUncategorized => 'Без категории';

  @override
  String get sourceTelegram => 'Telegram';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSyncSection => 'Синхронизация';

  @override
  String get settingsPreferencesSection => 'Параметры';

  @override
  String get settingsAboutSection => 'О приложении';

  @override
  String get settingsCurrency => 'Валюта';

  @override
  String get settingsCategoriesValue => 'Изменить и упорядочить';

  @override
  String get settingsAppearanceLabel => 'ОФОРМЛЕНИЕ';

  @override
  String get settingsLanguageLabel => 'ЯЗЫК';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsThemeSystem => 'Как в системе';

  @override
  String get settingsLanguageSystem => 'Системный';

  @override
  String settingsVersion({required String version}) {
    return 'v$version';
  }

  @override
  String get settingsAboutBody =>
      'Учёт денег, который живёт на вашем устройстве, синхронизируется через ваш собственный Google Диск и принимает записи от вашего Telegram-бота. Данные не покидают ваши аккаунты.';

  @override
  String get syncIndicatorSyncing => 'Синхронизация';

  @override
  String get syncIndicatorOffline => 'Нет сети';

  @override
  String get syncIndicatorIssue => 'Сбой синхронизации';

  @override
  String get syncStatusSyncing => 'Синхронизация…';

  @override
  String get syncStatusConnected => 'Подключено';

  @override
  String get syncStatusOffline => 'Нет сети — повторим позже';

  @override
  String get syncStatusStandalone => 'Автономный режим';

  @override
  String get syncNeverSynced => 'Ещё не синхронизировалось';

  @override
  String syncLastSynced({required String time}) {
    return 'Синхронизация $time';
  }

  @override
  String get syncRelativeJustNow => 'только что';

  @override
  String syncRelativeMinutesAgo({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count минуты назад',
      many: '$count минут назад',
      few: '$count минуты назад',
      one: '$count минуту назад',
    );
    return '$_temp0';
  }

  @override
  String syncRelativeHoursAgo({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count часа назад',
      many: '$count часов назад',
      few: '$count часа назад',
      one: '$count час назад',
    );
    return '$_temp0';
  }

  @override
  String get syncErrorAuthRevoked =>
      'Доступ к Google отозван — подключите Диск заново';

  @override
  String get syncErrorAuthExpired =>
      'Доступ к Google истёк — подключите Диск заново';

  @override
  String get syncErrorDriveFull => 'Google Диск переполнен';

  @override
  String syncErrorDrive({required String message}) {
    return 'Ошибка Диска: $message';
  }

  @override
  String get syncNowButton => 'Синхронизировать';

  @override
  String get syncedSnack => 'Синхронизировано';

  @override
  String get syncFailedSnack =>
      'Синхронизация не удалась — смотрите статус выше';

  @override
  String get driveStandaloneNotice =>
      'Автономный режим — всё работает офлайн на этом устройстве. Подключите Google Диск, чтобы синхронизироваться с Telegram-ботом; данные останутся на вашем Диске в виде читаемого JSON.';

  @override
  String get driveNoClientNotice =>
      'В этой сборке нет клиента Google OAuth. Пересоберите с --dart-define=GOOGLE_CLIENT_ID=… и --dart-define=GOOGLE_CLIENT_SECRET=…, чтобы включить синхронизацию с Диском.';

  @override
  String get driveConnectButton => 'Подключить Google Диск';

  @override
  String get driveReconnectButton => 'Подключить заново';

  @override
  String get driveDisconnectButton => 'Отключить';

  @override
  String get driveStepOpenLink => 'ШАГ 1 — ОТКРОЙТЕ ССЫЛКУ';

  @override
  String get driveStepEnterCode => 'ШАГ 2 — ВВЕДИТЕ КОД';

  @override
  String get driveWaitingForApproval => 'Ждём вашего подтверждения…';

  @override
  String driveWaitingChecked({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ждём подтверждения… (проверили $count раза)',
      many: 'Ждём подтверждения… (проверили $count раз)',
      few: 'Ждём подтверждения… (проверили $count раза)',
      one: 'Ждём подтверждения… (проверили $count раз)',
    );
    return '$_temp0';
  }

  @override
  String get driveConnectedSnack => 'Google Диск подключён — синхронизируем';

  @override
  String get driveDisconnectedSnack => 'Отключено — автономный режим';

  @override
  String get driveCodeCopied => 'Код скопирован';

  @override
  String get driveLinkCopied => 'Ссылка скопирована — откройте её в браузере';

  @override
  String get driveConnectionTitle => 'Google Диск';

  @override
  String driveConnectionTitleFolder({required String folder}) {
    return 'Google Диск · $folder/';
  }

  @override
  String get driveConnectionUnknownDevice =>
      'Это устройство публикует собственный файл снимка.';

  @override
  String driveConnectionDevice({required String device, required String file}) {
    return 'Это устройство: $device · $file';
  }

  @override
  String get authErrorNoClient => 'В этой сборке нет клиента Google OAuth.';

  @override
  String get authErrorDenied => 'Вы отклонили запрос в Google.';

  @override
  String get authErrorExpired => 'Срок действия кода истёк — попробуйте снова.';

  @override
  String get authErrorNetwork => 'Нет связи с Google — проверьте сеть.';

  @override
  String get seedCategoryGroceries => 'Продукты';

  @override
  String get seedCategoryCafe => 'Кафе';

  @override
  String get seedCategoryTransport => 'Транспорт';

  @override
  String get seedCategoryHome => 'Жильё';

  @override
  String get seedCategoryUtilities => 'Коммуналка';

  @override
  String get seedCategoryHealth => 'Здоровье';

  @override
  String get seedCategoryShopping => 'Покупки';

  @override
  String get seedCategoryFun => 'Развлечения';

  @override
  String get seedCategorySubscriptions => 'Подписки';

  @override
  String get seedCategoryTravel => 'Путешествия';

  @override
  String get seedCategoryOther => 'Прочее';

  @override
  String get seedCategorySalary => 'Зарплата';

  @override
  String get seedCategoryFreelance => 'Фриланс';

  @override
  String get seedCategoryGifts => 'Подарки';

  @override
  String get seedCategoryOtherIncome => 'Прочий доход';

  @override
  String get currencyUSD => 'Доллар США';

  @override
  String get currencyEUR => 'Евро';

  @override
  String get currencyGBP => 'Фунт стерлингов';

  @override
  String get currencyUAH => 'Украинская гривна';

  @override
  String get currencyPLN => 'Польский злотый';

  @override
  String get currencyCZK => 'Чешская крона';

  @override
  String get currencyCHF => 'Швейцарский франк';

  @override
  String get currencySEK => 'Шведская крона';

  @override
  String get currencyNOK => 'Норвежская крона';

  @override
  String get currencyDKK => 'Датская крона';

  @override
  String get currencyJPY => 'Японская иена';

  @override
  String get currencyCNY => 'Китайский юань';

  @override
  String get currencyINR => 'Индийская рупия';

  @override
  String get currencyCAD => 'Канадский доллар';

  @override
  String get currencyAUD => 'Австралийский доллар';

  @override
  String get currencyNZD => 'Новозеландский доллар';

  @override
  String get currencyBRL => 'Бразильский реал';

  @override
  String get currencyMXN => 'Мексиканское песо';

  @override
  String get currencyTRY => 'Турецкая лира';

  @override
  String get currencyKRW => 'Южнокорейская вона';

  @override
  String get currencySGD => 'Сингапурский доллар';

  @override
  String get currencyHKD => 'Гонконгский доллар';

  @override
  String get currencyILS => 'Израильский шекель';

  @override
  String get currencyAED => 'Дирхам ОАЭ';

  @override
  String get currencyZAR => 'Южноафриканский ранд';

  @override
  String get currencyRUB => 'Российский рубль';

  @override
  String get currencyUZS => 'Узбекский сум';

  @override
  String get currencyKZT => 'Казахстанский тенге';

  @override
  String get periodDay => 'День';

  @override
  String get periodMonth => 'Месяц';

  @override
  String get periodSwitchToDay => 'Показывать по дням';

  @override
  String get periodSwitchToMonth => 'Показывать весь месяц';

  @override
  String get homeNetToday => 'ИТОГ ЗА ДЕНЬ';

  @override
  String homeNetForDay({required String date}) {
    return 'ИТОГ · $date';
  }

  @override
  String get homeNothingSpentDayTitle => 'За день ничего не потрачено';

  @override
  String get homeNothingSpentDayMessage => 'Спокойный день для кошелька.';

  @override
  String get homeDayEntriesSection => 'Записи';

  @override
  String get seedAccountCash => 'Наличные';

  @override
  String get seedAccountCard => 'Карта';

  @override
  String get seedAccountSavings => 'Накопления';

  @override
  String get seedAccountInvestments => 'Инвестиции';

  @override
  String get transactionTransfer => 'Перевод';

  @override
  String transactionTransferRoute({required String from, required String to}) {
    return '$from → $to';
  }
}
