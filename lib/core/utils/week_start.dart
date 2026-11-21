/// First day of the week (Bangladesh calendars usually start on Saturday).
enum WeekStart {
  saturday(DateTime.saturday),
  sunday(DateTime.sunday),
  monday(DateTime.monday);

  const WeekStart(this.isoWeekday);

  final int isoWeekday;

  static WeekStart parse(String? value) =>
      values.firstWhere((w) => w.name == value, orElse: () => saturday);
}
