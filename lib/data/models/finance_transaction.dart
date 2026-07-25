class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.date,
    required this.category,
    required this.categoryId,
    required this.note,
    required this.updatedAtMs,
    required this.deletedAtMs,
  });

  final String id;
  final String type;
  final int amountCents;
  final String date;
  final String category;
  final String? categoryId;
  final String? note;
  final int updatedAtMs;
  final int? deletedAtMs;
}
