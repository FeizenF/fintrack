import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/transactions_repository.dart';
import 'package:fintrack/core/utils/csv_exporter.dart';

void main() {
  late AppDatabase db;
  late AccountsRepository accounts;
  late CategoriesRepository categories;
  late TransactionsRepository transactions;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.ensureSeeded();
    accounts = AccountsRepository(db);
    categories = CategoriesRepository(db);
    transactions = TransactionsRepository(db);
  });

  tearDown(() => db.close());

  test('CsvExporter encodes transactions with BOM and header', () async {
    final int cash = await accounts.create(
      name: 'Dompet Utama',
      type: AccountType.cash,
    );
    final int bank = await accounts.create(
      name: 'BCA Rekening',
      type: AccountType.bank,
    );
    final Category incomeCat = (await categories.list(
      kind: CategoryKind.income,
    )).first;
    final Category expenseCat = (await categories.list(
      kind: CategoryKind.expense,
    )).first;

    final int t1 = await transactions.createIncome(
      accountId: cash,
      categoryId: incomeCat.id,
      amount: 1500000,
      date: DateTime.utc(2026, 5, 1, 10, 30),
      note: 'Gaji pokok',
    );
    final int t2 = await transactions.createExpense(
      accountId: cash,
      categoryId: expenseCat.id,
      amount: 45000,
      date: DateTime.utc(2026, 5, 2, 12),
      note: 'Makan siang, enak!',
    );
    final int t3 = await transactions.createTransfer(
      fromAccountId: cash,
      toAccountId: bank,
      amount: 200000,
      date: DateTime.utc(2026, 5, 3),
      note: 'Pindah tabungan',
    );

    final List<FinancialTransaction> rawList = await transactions.list();
    final Map<int, String> accountNames = <int, String>{
      cash: 'Dompet Utama',
      bank: 'BCA Rekening',
    };
    final Map<int, String> categoryNames = <int, String>{
      incomeCat.id: incomeCat.name,
      expenseCat.id: expenseCat.name,
    };

    final List<ExportTransaction> exportItems = rawList.map((
      FinancialTransaction tx,
    ) {
      return ExportTransaction(
        transaction: tx,
        sourceAccount: accountNames[tx.accountId] ?? '',
        destinationAccount: tx.toAccountId != null
            ? accountNames[tx.toAccountId!]
            : null,
        category: tx.categoryId != null ? categoryNames[tx.categoryId!] : null,
      );
    }).toList();

    final List<int> bytes = CsvExporter.encode(exportItems);
    expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]); // UTF-8 BOM

    final String csv = utf8.decode(bytes);
    expect(
      csv,
      contains(
        '"ID","Tanggal","Jenis","Akun asal","Akun tujuan","Kategori",'
        '"Nominal (Rupiah)","Catatan"',
      ),
    );
    expect(csv, contains('Dompet Utama'));
    expect(csv, contains('BCA Rekening'));
    expect(csv, contains('"1500000"'));
    expect(csv, contains('"Makan siang, enak!"'));
    expect(csv, contains('"${t1.toString()}"'));
    expect(csv, contains('"${t2.toString()}"'));
    expect(csv, contains('"${t3.toString()}"'));
    expect(csv.split('\r\n').where((String l) => l.isNotEmpty).length, 4);
  });

  test('CsvExporter neutralises formula injection in note text', () {
    final FinancialTransaction mockTx = FinancialTransaction(
      id: 1,
      type: TransactionType.expense,
      accountId: 1,
      amount: 10000,
      transactionDate: DateTime.utc(2026, 1, 1),
      note: '=cmd|"/C calc"!A0',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final List<int> bytes = CsvExporter.encode(<ExportTransaction>[
      ExportTransaction(
        transaction: mockTx,
        sourceAccount: 'Dompet',
        category: 'Lainnya',
      ),
    ]);

    final String csv = utf8.decode(bytes);
    expect(csv, contains("'=cmd|\"\"/C calc\"\"!A0"));
  });

  test('CsvExporter neutralises formulas after leading whitespace', () {
    final FinancialTransaction mockTx = FinancialTransaction(
      id: 1,
      type: TransactionType.expense,
      accountId: 1,
      amount: 10000,
      transactionDate: DateTime.utc(2026, 1, 1),
      note: '  =1+1',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final String csv = utf8.decode(
      CsvExporter.encode(<ExportTransaction>[
        ExportTransaction(
          transaction: mockTx,
          sourceAccount: 'Dompet',
          category: 'Lainnya',
        ),
      ]),
    );

    expect(csv, contains("'  =1+1"));
  });
}
