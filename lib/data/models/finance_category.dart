class FinanceCategory {
  const FinanceCategory({
    required this.id,
    required this.name,
    required this.updatedAtMs,
    required this.deletedAtMs,
  });

  final String id;
  final String name;
  final int updatedAtMs;
  final int? deletedAtMs;
}
