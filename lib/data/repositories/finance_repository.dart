import '../models/finance_category.dart';
import '../models/finance_transaction.dart';

enum CategoryCreationResult { created, restored, alreadyExists, invalid }

/// Abstraktion zwischen UI und Datenquelle.
///
/// Die UI kennt dadurch weder Drift noch SQLite. Heute wird dieses Interface
/// durch eine Drift-Implementierung umgesetzt; später kann eine Remote-/Sync-
/// Implementierung ergänzt werden, ohne die Screens erneut umzubauen.
abstract class FinanceRepository {
  Stream<List<FinanceTransaction>> watchActiveTransactionsInRange({
    String? startIsoInclusive,
    String? endIsoExclusive,
    String? categoryId,
  });

  Stream<List<FinanceCategory>> watchActiveCategories();

  Future<CategoryCreationResult> createCategory(String name);
  Future<FinanceCategory?> getActiveCategoryByName(String name);
  Future<FinanceCategory?> getCategoryById(String id);

  Future<void> saveTransaction({
    required String id,
    required String type,
    required int amountCents,
    required String date,
    required String category,
    String? categoryId,
    String? note,
    required int updatedAtMs,
    int? deletedAtMs,
  });

  Future<void> deleteTransaction(String id);
  Future<void> renameCategory(String id, String newName);
  Future<int> countActiveTransactionsForCategory(String categoryId);
  Future<FinanceCategory> ensureCategoryActiveByName(String name);

  Future<void> moveActiveTransactionsToCategory({
    required String fromCategoryId,
    required String toCategoryId,
    required String toCategoryNameSnapshot,
  });

  Future<void> deleteActiveTransactionsForCategory(String categoryId);
  Future<void> deleteCategory(String id);
  Future<T> runInTransaction<T>(Future<T> Function() action);
}
