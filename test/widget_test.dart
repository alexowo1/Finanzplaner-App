import 'package:flutter_test/flutter_test.dart';
import 'package:haushaltsplaner/data/models/finance_transaction.dart';

void main() {
  test('FinanceTransaction stores transaction data', () {
    const transaction = FinanceTransaction(
      id: 'test-id',
      type: 'expense',
      amountCents: 1234,
      date: '2026-07-24',
      category: 'Allgemein',
      categoryId: 'category-id',
      note: 'Test',
      updatedAtMs: 1,
      deletedAtMs: null,
    );

    expect(transaction.amountCents, 1234);
    expect(transaction.deletedAtMs, isNull);
  });
}
