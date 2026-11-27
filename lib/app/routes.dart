/// Route paths. Use these constants instead of string literals.
abstract final class Routes {
  static const String home = '/home';
  static const String history = '/history';
  static const String reports = '/reports';
  static const String more = '/more';
  static const String add = '/add';

  static const String budgets = '/more/budgets';
  static const String categories = '/more/categories';
  static const String accounts = '/more/accounts';
  static const String loans = '/more/loans';
  static const String settings = '/more/settings';
  static const String about = '/more/about';
  static const String backup = '/more/backup';
  static const String backupRestore = '/more/backup/restore';

  static const String transactionPattern = '/transaction/:id';
  static const String voice = '/voice';
  static const String voiceConfirm = '/voice/confirm';

  static String transaction(String id) => '/transaction/$id';
  static String loanPerson(String id) => '$loans/$id';
  static String addOfType(String type) => '$add?type=$type';
  /// A transfer form with the destination and amount already filled in.
  static String addTransfer({required String to, String? from, int? amountPaisa}) =>
      '$add?type=transfer&to=$to'
      '${from == null ? '' : '&from=$from'}'
      '${amountPaisa == null ? '' : '&amount=$amountPaisa'}';
  static String addEdit(String id) => '$add?edit=$id';
  static String addRepeat(String id) => '$add?repeat=$id';
}
