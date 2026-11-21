/// Route paths. Use these constants instead of string literals.
abstract final class Routes {
  static const String home = '/home';
  static const String history = '/history';
  static const String reports = '/reports';
  static const String more = '/more';
  static const String add = '/add';

  static const String categories = '/more/categories';
  static const String accounts = '/more/accounts';
  static const String settings = '/more/settings';
  static const String about = '/more/about';

  static const String transactionPattern = '/transaction/:id';

  static String transaction(String id) => '/transaction/$id';
  static String addOfType(String type) => '$add?type=$type';
  static String addEdit(String id) => '$add?edit=$id';
  static String addRepeat(String id) => '$add?repeat=$id';
}
