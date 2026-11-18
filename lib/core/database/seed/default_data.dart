import '../enums.dart';

/// Names of the seeded default categories, as required by the specification.
const List<String> defaultIncomeCategoryNames = <String>[
  'Gaji',
  'Uang saku',
  'Bisnis',
  'Bonus',
  'Investasi',
  'Lainnya',
];

const List<String> defaultExpenseCategoryNames = <String>[
  'Makanan',
  'Transportasi',
  'Pendidikan',
  'Belanja',
  'Tagihan',
  'Hiburan',
  'Kesehatan',
  'Kebutuhan usaha',
  'Lainnya',
];

/// Icon keys are resolved to Material icons by the presentation layer, keeping
/// the database free of Flutter dependencies.
const Map<String, String> _incomeIconKeys = <String, String>{
  'Gaji': 'payments',
  'Uang saku': 'wallet',
  'Bisnis': 'storefront',
  'Bonus': 'redeem',
  'Investasi': 'trending_up',
  'Lainnya': 'category',
};

const Map<String, String> _expenseIconKeys = <String, String>{
  'Makanan': 'restaurant',
  'Transportasi': 'directions_car',
  'Pendidikan': 'school',
  'Belanja': 'shopping_bag',
  'Tagihan': 'receipt',
  'Hiburan': 'movie',
  'Kesehatan': 'health_and_safety',
  'Kebutuhan usaha': 'business_center',
  'Lainnya': 'category',
};

/// ARGB colors used for category chips and charts.
const Map<String, int> _incomeColors = <String, int>{
  'Gaji': 0xFF12855A,
  'Uang saku': 0xFF1F9D74,
  'Bisnis': 0xFF0F7B6C,
  'Bonus': 0xFF2E9E5B,
  'Investasi': 0xFF3AA17E,
  'Lainnya': 0xFF6B7A8F,
};

const Map<String, int> _expenseColors = <String, int>{
  'Makanan': 0xFFC0392B,
  'Transportasi': 0xFF2D6CDF,
  'Pendidikan': 0xFF6C4BD1,
  'Belanja': 0xFFD4742C,
  'Tagihan': 0xFF8E44AD,
  'Hiburan': 0xFFC2456F,
  'Kesehatan': 0xFF159B8A,
  'Kebutuhan usaha': 0xFF7A5C2E,
  'Lainnya': 0xFF6B7A8F,
};

/// Plain seed row for one default category. Deliberately a value object so the
/// data file stays independent of Drift's generated companions.
class DefaultCategorySeed {
  const DefaultCategorySeed({
    required this.name,
    required this.kind,
    required this.iconKey,
    required this.colorValue,
    required this.sortOrder,
  });

  final String name;
  final CategoryKind kind;
  final String iconKey;
  final int colorValue;
  final int sortOrder;
}

/// Default categories inserted on first launch, income block first.
List<DefaultCategorySeed> defaultCategorySeeds() {
  final List<DefaultCategorySeed> seeds = <DefaultCategorySeed>[];

  for (int i = 0; i < defaultIncomeCategoryNames.length; i++) {
    final String name = defaultIncomeCategoryNames[i];
    seeds.add(
      DefaultCategorySeed(
        name: name,
        kind: CategoryKind.income,
        iconKey: _incomeIconKeys[name] ?? 'category',
        colorValue: _incomeColors[name] ?? 0xFF6B7A8F,
        sortOrder: i,
      ),
    );
  }

  for (int i = 0; i < defaultExpenseCategoryNames.length; i++) {
    final String name = defaultExpenseCategoryNames[i];
    seeds.add(
      DefaultCategorySeed(
        name: name,
        kind: CategoryKind.expense,
        iconKey: _expenseIconKeys[name] ?? 'category',
        colorValue: _expenseColors[name] ?? 0xFF6B7A8F,
        sortOrder: i,
      ),
    );
  }

  return seeds;
}
