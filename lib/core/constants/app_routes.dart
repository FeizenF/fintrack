/// Route paths and names. Centralised so navigation never relies on raw
/// strings scattered across features.
abstract final class AppRoutes {
  // Shell tabs
  static const String home = '/';
  static const String transactions = '/transactions';
  static const String budgets = '/budgets';
  static const String reports = '/reports';
  static const String settings = '/settings';

  // Pushed pages
  static const String transactionNew = '/transactions/new';
  static const String accounts = '/accounts';
  static const String categories = '/categories';
  static const String savings = '/savings';
  static const String backup = '/backup';
  static const String security = '/security';
  static const String preferences = '/preferences';
  static const String shopping = '/shopping';

  /// Router path patterns (used by go_router route definitions).
  static const String transactionDetailPattern = '/transactions/:id';
  static const String transactionEditPattern = '/transactions/:id/edit';
  static const String shoppingDetailPattern = '/shopping/:id';

  /// Concrete navigation targets.
  static String transactionDetail(int id) => '/transactions/$id';
  static String transactionEdit(int id) => '/transactions/$id/edit';
  static String shoppingDetail(int id) => '/shopping/$id';
}
