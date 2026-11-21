/// Route paths. Use these constants instead of string literals.
abstract final class Routes {
  static const String home = '/home';
  static const String history = '/history';
  static const String reports = '/reports';
  static const String more = '/more';
  static const String add = '/add';

  static const String budgets = '/more/budgets';
  static const String recurring = '/more/recurring';
  static const String categories = '/more/categories';
  static const String accounts = '/more/accounts';
  static const String settings = '/more/settings';
  static const String about = '/more/about';

  static const String transactionPattern = '/transaction/:id';
  static const String recurringEditPath = '/recurring/edit';
  static const String voice = '/voice';
  static const String voiceConfirm = '/voice/confirm';

  static String transaction(String id) => '/transaction/$id';
  static String addOfType(String type) => '$add?type=$type';
  static String addEdit(String id) => '$add?edit=$id';
  static String addRepeat(String id) => '$add?repeat=$id';

  /// New rule, an existing rule ([id]), or a rule prefilled from a
  /// transaction ([fromTransaction]).
  static String recurringEdit({String? id, String? fromTransaction}) => id != null
      ? '$recurringEditPath?id=$id'
      : fromTransaction != null
          ? '$recurringEditPath?from=$fromTransaction'
          : recurringEditPath;
}
