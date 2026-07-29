import 'dart:async';

import 'package:pocketbase/pocketbase.dart';
import 'package:uuid/uuid.dart';

import '../../models/finance_category.dart';
import '../../models/finance_transaction.dart';
import '../../repositories/finance_repository.dart';
import 'pocketbase_config.dart';

class PocketBaseFinanceRepository implements FinanceRepository {
  PocketBaseFinanceRepository._(this._client);

  final PocketBase _client;

  static const _uuid = Uuid();

  final _categoriesController =
      StreamController<List<FinanceCategory>>.broadcast();

  final _transactionsController =
      StreamController<List<FinanceTransaction>>.broadcast();

  List<FinanceCategory> _categories = const [];
  List<FinanceTransaction> _transactions = const [];

  UnsubscribeFunc? _unsubscribeCategories;
  UnsubscribeFunc? _unsubscribeTransactions;

  bool _disposed = false;

  static Future<PocketBaseFinanceRepository> create(PocketBase client) async {
    if (!client.authStore.isValid || client.authStore.record == null) {
      throw StateError(
        'Für das PocketBase-Repository ist eine Anmeldung erforderlich.',
      );
    }

    final repository = PocketBaseFinanceRepository._(client);

    await repository._initialize();

    return repository;
  }

  String get _ownerId {
    final userId = _client.authStore.record?.id;

    if (!_client.authStore.isValid || userId == null || userId.isEmpty) {
      throw StateError('Es ist kein gültiger Benutzer angemeldet.');
    }

    return userId;
  }

  Future<void> _initialize() async {
    await Future.wait([_reloadCategories(), _reloadTransactions()]);

    _unsubscribeCategories = await _client
        .collection(PocketBaseConfig.categoriesCollection)
        .subscribe('*', (_) => _reloadCategoriesInBackground());

    _unsubscribeTransactions = await _client
        .collection(PocketBaseConfig.transactionsCollection)
        .subscribe('*', (_) => _reloadTransactionsInBackground());
  }

  void _reloadCategoriesInBackground() {
    unawaited(
      _reloadCategories().catchError((Object error, StackTrace stackTrace) {
        // Bei einer kurzen Netzwerkunterbrechung bleiben
        // die zuletzt geladenen Daten sichtbar.
      }),
    );
  }

  void _reloadTransactionsInBackground() {
    unawaited(
      _reloadTransactions().catchError((Object error, StackTrace stackTrace) {
        // Bei einer kurzen Netzwerkunterbrechung bleiben
        // die zuletzt geladenen Daten sichtbar.
      }),
    );
  }

  Future<void> _reloadCategories() async {
    final records = await _client
        .collection(PocketBaseConfig.categoriesCollection)
        .getFullList(
          filter: _client.filter('owner = {:owner} && deletedAtMs = 0', {
            'owner': _ownerId,
          }),
          sort: 'name',
        );

    _categories = records.map(_categoryFromRecord).toList(growable: false);

    if (!_disposed) {
      _categoriesController.add(List.unmodifiable(_categories));
    }
  }

  Future<void> _reloadTransactions() async {
    final records = await _client
        .collection(PocketBaseConfig.transactionsCollection)
        .getFullList(
          filter: _client.filter('owner = {:owner} && deletedAtMs = 0', {
            'owner': _ownerId,
          }),
          sort: '-bookingDate,-clientUpdatedAtMs',
        );

    _transactions = records.map(_transactionFromRecord).toList(growable: false);

    if (!_disposed) {
      _transactionsController.add(List.unmodifiable(_transactions));
    }
  }

  FinanceCategory _categoryFromRecord(RecordModel record) {
    return FinanceCategory.fromJson(record.toJson());
  }

  FinanceTransaction _transactionFromRecord(RecordModel record) {
    return FinanceTransaction.fromJson(record.toJson());
  }

  int _deletedAtMs(RecordModel record) {
    final value = record.toJson()['deletedAtMs'];

    return value is num ? value.toInt() : 0;
  }

  Future<RecordModel?> _findRecordByEntityId({
    required String collection,
    required String entityId,
  }) async {
    try {
      return await _client
          .collection(collection)
          .getFirstListItem(
            _client.filter('owner = {:owner} && entityId = {:entityId}', {
              'owner': _ownerId,
              'entityId': entityId,
            }),
          );
    } on ClientException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  Future<RecordModel?> _findCategoryByName(String name) async {
    try {
      return await _client
          .collection(PocketBaseConfig.categoriesCollection)
          .getFirstListItem(
            _client.filter('owner = {:owner} && name = {:name}', {
              'owner': _ownerId,
              'name': name,
            }),
          );
    } on ClientException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  List<FinanceTransaction> _filterTransactions({
    required List<FinanceTransaction> transactions,
    String? startIsoInclusive,
    String? endIsoExclusive,
    String? categoryId,
  }) {
    final filtered = transactions.where((transaction) {
      if (transaction.deletedAtMs != null) {
        return false;
      }

      if (startIsoInclusive != null &&
          transaction.date.compareTo(startIsoInclusive) < 0) {
        return false;
      }

      if (endIsoExclusive != null &&
          transaction.date.compareTo(endIsoExclusive) >= 0) {
        return false;
      }

      if (categoryId != null && transaction.categoryId != categoryId) {
        return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      final dateComparison = b.date.compareTo(a.date);

      if (dateComparison != 0) {
        return dateComparison;
      }

      return b.updatedAtMs.compareTo(a.updatedAtMs);
    });

    return List.unmodifiable(filtered);
  }

  @override
  Stream<List<FinanceCategory>> watchActiveCategories() async* {
    yield List.unmodifiable(_categories);
    yield* _categoriesController.stream;
  }

  @override
  Stream<List<FinanceTransaction>> watchActiveTransactionsInRange({
    String? startIsoInclusive,
    String? endIsoExclusive,
    String? categoryId,
  }) async* {
    yield _filterTransactions(
      transactions: _transactions,
      startIsoInclusive: startIsoInclusive,
      endIsoExclusive: endIsoExclusive,
      categoryId: categoryId,
    );

    yield* _transactionsController.stream.map(
      (transactions) => _filterTransactions(
        transactions: transactions,
        startIsoInclusive: startIsoInclusive,
        endIsoExclusive: endIsoExclusive,
        categoryId: categoryId,
      ),
    );
  }

  @override
  Future<CategoryCreationResult> createCategory(String name) async {
    final normalizedName = name.trim();

    if (normalizedName.isEmpty) {
      return CategoryCreationResult.invalid;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _findCategoryByName(normalizedName);

    if (existing != null) {
      if (_deletedAtMs(existing) == 0) {
        return CategoryCreationResult.alreadyExists;
      }

      await _client
          .collection(PocketBaseConfig.categoriesCollection)
          .update(
            existing.id,
            body: {
              'name': normalizedName,
              'clientUpdatedAtMs': now,
              'deletedAtMs': 0,
            },
          );

      await _reloadCategories();

      return CategoryCreationResult.restored;
    }

    await _client
        .collection(PocketBaseConfig.categoriesCollection)
        .create(
          body: {
            'entityId': _uuid.v4(),
            'owner': _ownerId,
            'name': normalizedName,
            'clientUpdatedAtMs': now,
            'deletedAtMs': 0,
          },
        );

    await _reloadCategories();

    return CategoryCreationResult.created;
  }

  @override
  Future<FinanceCategory?> getActiveCategoryByName(String name) async {
    final record = await _findCategoryByName(name.trim());

    if (record == null || _deletedAtMs(record) != 0) {
      return null;
    }

    return _categoryFromRecord(record);
  }

  @override
  Future<FinanceCategory?> getCategoryById(String id) async {
    final record = await _findRecordByEntityId(
      collection: PocketBaseConfig.categoriesCollection,
      entityId: id,
    );

    return record == null ? null : _categoryFromRecord(record);
  }

  @override
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
  }) async {
    final transaction = FinanceTransaction(
      id: id,
      type: type,
      amountCents: amountCents,
      date: date,
      category: category,
      categoryId: categoryId,
      note: note,
      updatedAtMs: updatedAtMs,
      deletedAtMs: deletedAtMs,
    );

    final body = {...transaction.toJson(), 'owner': _ownerId};

    final existing = await _findRecordByEntityId(
      collection: PocketBaseConfig.transactionsCollection,
      entityId: id,
    );

    final records = _client.collection(PocketBaseConfig.transactionsCollection);

    if (existing == null) {
      await records.create(body: body);
    } else {
      await records.update(existing.id, body: body);
    }

    await _reloadTransactions();
  }

  @override
  Future<void> deleteTransaction(String id) async {
    final record = await _findRecordByEntityId(
      collection: PocketBaseConfig.transactionsCollection,
      entityId: id,
    );

    if (record == null) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await _client
        .collection(PocketBaseConfig.transactionsCollection)
        .update(
          record.id,
          body: {'clientUpdatedAtMs': now, 'deletedAtMs': now},
        );

    await _reloadTransactions();
  }

  @override
  Future<void> renameCategory(String id, String newName) async {
    final normalizedName = newName.trim();

    if (normalizedName.isEmpty) {
      return;
    }

    final record = await _findRecordByEntityId(
      collection: PocketBaseConfig.categoriesCollection,
      entityId: id,
    );

    if (record == null) {
      throw StateError('Die Kategorie wurde auf dem Server nicht gefunden.');
    }

    await _client
        .collection(PocketBaseConfig.categoriesCollection)
        .update(
          record.id,
          body: {
            'name': normalizedName,
            'clientUpdatedAtMs': DateTime.now().millisecondsSinceEpoch,
          },
        );

    await _reloadCategories();
  }

  @override
  Future<int> countActiveTransactionsForCategory(String categoryId) async {
    final result = await _client
        .collection(PocketBaseConfig.transactionsCollection)
        .getList(
          page: 1,
          perPage: 1,
          filter: _client.filter(
            'owner = {:owner} && '
            'categoryEntityId = {:categoryId} && '
            'deletedAtMs = 0',
            {'owner': _ownerId, 'categoryId': categoryId},
          ),
        );

    return result.totalItems;
  }

  @override
  Future<void> deleteCategoryWithPolicy({
    required String categoryId,
    required CategoryDeletionPolicy policy,
    String? targetCategoryId,
  }) {
    throw UnsupportedError(
      'Die atomare PocketBase-Serveraktion zum Löschen '
      'einer Kategorie wird im nächsten Schritt ergänzt.',
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _unsubscribeCategories?.call();
    await _unsubscribeTransactions?.call();

    await _categoriesController.close();
    await _transactionsController.close();
  }
}
