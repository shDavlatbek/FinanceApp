/// End-to-end i18n: every locale renders translated chrome, switching the
/// language provider re-renders immediately, money follows the selected
/// locale on screen, and seed categories localize only until they are renamed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/theme.dart';
import 'package:tally/data/providers.dart';
import 'package:tally/data/repo/transactions_repository.dart';
import 'package:tally/features/accounts/accounts_screen.dart';
import 'package:tally/features/categories/categories_screen.dart';
import 'package:tally/features/common/kind_pill.dart';
import 'package:tally/features/settings/settings_screen.dart';
import 'package:tally/l10n/l10n.dart';
import 'package:tally/l10n/locale_controller.dart';
import 'package:tally/main.dart';

import 'support/pump_localized.dart';
import 'support/test_db.dart';

const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';
const String _salary = 'c1a7e2f0-0101-4a00-9000-000000000101';

/// Lets async DB streams, entrance animations and the branch fade settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (final int ms in const [100, 300, 500, 800]) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  group('a plain widget renders in each locale', () {
    const Map<String, String> expenseLabel = <String, String>{
      'en': 'Expense',
      'ru': 'Расход',
      'uz': 'Xarajat',
    };
    const Map<String, String> incomeLabel = <String, String>{
      'en': 'Income',
      'ru': 'Доход',
      'uz': 'Daromad',
    };

    const Map<String, String> transferLabel = <String, String>{
      'en': 'Transfer',
      'ru': 'Перевод',
      'uz': 'Oʻtkazma',
    };

    for (final String code in expenseLabel.keys) {
      testWidgets('KindPill in $code', (tester) async {
        await tester.pumpLocalized(
          KindPill(value: Kind.expense, onChanged: (_) {}),
          locale: Locale(code),
        );
        expect(find.text(expenseLabel[code]!), findsOneWidget);
        expect(find.text(incomeLabel[code]!), findsOneWidget);
        // The two-kind pill is the CATEGORY one: a category is an income or an
        // expense, never a transfer.
        expect(find.text(transferLabel[code]!), findsNothing);
      });

      testWidgets('the three-kind KindPill in $code', (tester) async {
        await tester.pumpLocalized(
          KindPill(
            value: Kind.transfer,
            onChanged: (_) {},
            options: kTransactionKindOptions,
          ),
          locale: Locale(code),
        );
        // Three labels in one pill on a narrow screen is where translations
        // overflow, and a layout overflow fails this test by itself.
        expect(find.text(transferLabel[code]!), findsOneWidget);
        expect(find.text(expenseLabel[code]!), findsOneWidget);
        expect(find.text(incomeLabel[code]!), findsOneWidget);
      });
    }
  });

  group('the whole app renders in each locale', () {
    const Map<String, (String hero, String settingsTab)> expected =
        <String, (String, String)>{
      'en': ('NET THIS MONTH', 'Settings'),
      'ru': ('ИТОГ ЗА МЕСЯЦ', 'Настройки'),
      'uz': ('SHU OYDAGI SOF QOLDIQ', 'Sozlamalar'),
    };

    for (final MapEntry<String, (String, String)> e in expected.entries) {
      testWidgets('locale ${e.key}', (tester) async {
        final AppDatabase db = openTestDb();
        final ProviderContainer container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        addTearDown(db.close);
        addTearDown(container.dispose);

        // The preference lives in the SYNCED settings row, so this is exactly
        // what the Telegram bot will read.
        await container.read(settingsRepoProvider).setLanguage(e.key);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TallyApp(),
          ),
        );
        await _settle(tester);

        expect(find.text(e.value.$1), findsOneWidget);
        expect(find.text(e.value.$2), findsWidgets);

        await _teardownTree(tester);
      });
    }
  });

  group('no screen overflows with the longer translations', () {
    // Russian and Uzbek strings are markedly longer than English; a
    // RenderFlex overflow throws in tests, so simply walking every surface
    // under each locale is the regression test.
    const Map<String, List<String>> tabs = <String, List<String>>{
      'ru': ['История', 'Статистика', 'Настройки'],
      'uz': ['Tarix', 'Statistika', 'Sozlamalar'],
    };

    for (final MapEntry<String, List<String>> e in tabs.entries) {
      testWidgets('locale ${e.key}', (tester) async {
        final AppDatabase db = openTestDb();
        final ProviderContainer container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        addTearDown(db.close);
        addTearDown(container.dispose);

        await TransactionsRepository(db, onMutation: () {}).insert(
          kind: Kind.expense,
          amountMinor: 24850,
          categoryId: _groceries,
          note: 'test',
          occurredAt: DateTime.now(),
        );
        await container.read(settingsRepoProvider).setLanguage(e.key);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TallyApp(),
          ),
        );
        await _settle(tester);

        // Entry sheet: amount field, category chips, date chips, save.
        await tester.tap(find.byIcon(Icons.add_rounded));
        await _settle(tester);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await _settle(tester);

        for (final String tab in e.value) {
          await tester.tap(find.text(tab).last);
          await _settle(tester);
        }

        await _teardownTree(tester);
      });
    }
  });

  testWidgets('switching the language re-renders immediately', (tester) async {
    final AppDatabase db = openTestDb();
    final ProviderContainer container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(db.close);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    expect(find.text('NET THIS MONTH'), findsOneWidget);
    expect(find.text('History'), findsWidgets);

    await container
        .read(localeControllerProvider.notifier)
        .setLanguage('ru');
    await _settle(tester);

    expect(find.text('NET THIS MONTH'), findsNothing);
    expect(find.text('ИТОГ ЗА МЕСЯЦ'), findsOneWidget);
    expect(find.text('История'), findsWidgets);

    // …and back again, through the Uzbek catalog.
    await container
        .read(localeControllerProvider.notifier)
        .setLanguage('uz');
    await _settle(tester);
    expect(find.text('SHU OYDAGI SOF QOLDIQ'), findsOneWidget);
    expect(find.text('Tarix'), findsWidgets);

    // '' means "follow the device locale", which the test harness reports as
    // en_US -> the English catalog.
    await container.read(localeControllerProvider.notifier).setLanguage('');
    await _settle(tester);
    expect(find.text('NET THIS MONTH'), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('the language picker writes the synced settings row',
      (tester) async {
    final AppDatabase db = openTestDb();
    final ProviderContainer container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(db.close);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Settings').last);
    await _settle(tester);

    await tester.scrollUntilVisible(find.text('Русский'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Русский'));
    await _settle(tester);

    expect(await container.read(settingsRepoProvider).getLanguage(), 'ru');
    expect(find.text('ЯЗЫК'), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('money and dates on screen follow the selected locale',
      (tester) async {
    final AppDatabase db = openTestDb();
    final ProviderContainer container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(db.close);
    addTearDown(container.dispose);

    await TransactionsRepository(db, onMutation: () {}).insert(
      kind: Kind.income,
      amountMinor: 123456789,
      categoryId: _salary,
      note: 'oylik',
      occurredAt: DateTime.now(),
    );
    await container.read(settingsRepoProvider).setCurrency('RUB');
    await container.read(settingsRepoProvider).setLanguage('ru');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TallyApp(),
      ),
    );
    await _settle(tester);
    // The hero number counts up; let the 450 ms tween land.
    await tester.pump(const Duration(milliseconds: 600));

    // ru: NBSP groups, comma decimals, symbol suffix.
    expect(find.text('1 234 567,89 ₽'), findsWidgets);

    // History groups by day under a localized "today" header, and its
    // tiles localize the unrenamed seed category.
    await tester.tap(find.text('История').last);
    await _settle(tester);
    expect(find.text('СЕГОДНЯ'), findsOneWidget);
    expect(find.text('+1 234 567,89 ₽'), findsWidgets);
    expect(find.text('Зарплата'), findsWidgets);

    await _teardownTree(tester);
  });

  group('seed categories localize only until they are renamed', () {
    Future<ProviderContainer> pumpCategories(
      WidgetTester tester,
      AppDatabase db, {
      required String locale,
    }) async {
      final ProviderContainer container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: tallyTheme(Brightness.dark),
            home: const CategoriesScreen(),
          ),
        ),
      );
      await _settle(tester);
      return container;
    }

    testWidgets('an untouched seed shows its translated name',
        (tester) async {
      final AppDatabase db = openTestDb();
      addTearDown(db.close);
      await pumpCategories(tester, db, locale: 'ru');

      expect(find.text('Продукты'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Транспорт'), findsOneWidget);

      await _teardownTree(tester);
    });

    testWidgets('the Uzbek catalog is used for uz', (tester) async {
      final AppDatabase db = openTestDb();
      addTearDown(db.close);
      await pumpCategories(tester, db, locale: 'uz');

      expect(find.text('Oziq-ovqat'), findsOneWidget);
      expect(find.text('Kommunal'), findsOneWidget);

      await _teardownTree(tester);
    });

    testWidgets('a renamed seed shows verbatim in every language',
        (tester) async {
      final AppDatabase db = openTestDb();
      addTearDown(db.close);
      final ProviderContainer container =
          await pumpCategories(tester, db, locale: 'ru');

      await container.read(categoriesRepoProvider).upsert(
            id: _groceries,
            name: 'Bozor',
            emoji: '🛒',
            color: '#4CAF7D',
            kind: Kind.expense,
          );
      await _settle(tester);

      expect(find.text('Bozor'), findsOneWidget);
      expect(find.text('Продукты'), findsNothing);
      // The other seeds are untouched and still translate.
      expect(find.text('Транспорт'), findsOneWidget);

      await _teardownTree(tester);
    });

    test('a user category is never localized', () async {
      final AppLocalizations ru =
          await AppLocalizations.delegate.load(const Locale('ru'));
      // Same canonical text, but not a seed id -> shown verbatim.
      expect(
        localizedCategoryName(ru, id: 'not-a-seed', name: 'Groceries'),
        'Groceries',
      );
      expect(
        localizedCategoryName(ru, id: _groceries, name: 'Groceries'),
        'Продукты',
      );
    });
  });

  group('the new surfaces render in each locale', () {
    const Map<String, (String accountsTitle, String total, String backup)>
        expected = <String, (String, String, String)>{
      'en': ('Accounts', 'TOTAL BALANCE', 'Import a backup'),
      'ru': ('Счета', 'ВСЕГО НА СЧЕТАХ', 'Загрузить копию'),
      'uz': ('Hisoblar', 'JAMI HISOBLARDA', 'Nusxani yuklash'),
    };

    for (final MapEntry<String, (String, String, String)> e
        in expected.entries) {
      testWidgets('Accounts in ${e.key}', (WidgetTester tester) async {
        // A phone-sized viewport on purpose: the total hero, the "send to"
        // chips and the four type pills are exactly where a longer
        // translation overflows, and an overflow fails this test on its own.
        tester.view.physicalSize = const Size(1170, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final AppDatabase db = openTestDb();
        addTearDown(db.close);
        await TransactionsRepository(db).insertTransfer(
          amountMinor: 5000000,
          fromAccountId: 'a1c7e2f0-0001-4a00-9000-000000000001',
          toAccountId: 'a1c7e2f0-0003-4a00-9000-000000000003',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              locale: Locale(e.key),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: tallyTheme(Brightness.dark),
              home: const AccountsScreen(),
            ),
          ),
        );
        await _settle(tester);

        expect(find.text(e.value.$1), findsWidgets);
        expect(find.text(e.value.$2), findsOneWidget);

        // Open the account editor, where the four type pills sit two to a
        // row — the tightest layout in the feature. Found by its icon, which
        // is the one thing on the button that does not change per language.
        await tester.tap(find.byIcon(Icons.add_rounded));
        await _settle(tester);
        expect(find.byType(TextField), findsWidgets);

        await _teardownTree(tester);
      });

      testWidgets('the Backup section in ${e.key}',
          (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1170, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final AppDatabase db = openTestDb();
        addTearDown(db.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              locale: Locale(e.key),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: tallyTheme(Brightness.dark),
              home: const Scaffold(body: SettingsScreen()),
            ),
          ),
        );
        await _settle(tester);
        await tester.scrollUntilVisible(find.text(e.value.$3), 250);
        await _settle(tester);

        expect(find.text(e.value.$3), findsOneWidget);

        await _teardownTree(tester);
      });
    }
  });
}
