import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/local_date.dart';

part 'history_filter.freezed.dart';

/// User-facing type filter. [expense] includes refunds.
enum HistoryTypeFilter { income, expense, transfer }

@freezed
abstract class HistoryFilter with _$HistoryFilter {
  const HistoryFilter._();

  const factory HistoryFilter({
    /// Empty = all types.
    @Default(<HistoryTypeFilter>{}) Set<HistoryTypeFilter> types,
    String? categoryId,
    String? subcategoryId,
    String? accountId,
    DateRange? range,
    @Default('') String search,
  }) = _HistoryFilter;

  /// Whether any filter other than search is set (used for the badge).
  bool get hasFilters =>
      types.isNotEmpty ||
      categoryId != null ||
      subcategoryId != null ||
      accountId != null ||
      range != null;

  bool get isEmpty => !hasFilters && search.trim().isEmpty;
}

/// A history query: scope + filter + page size.
@freezed
abstract class HistoryQuery with _$HistoryQuery {
  const factory HistoryQuery({
    required List<String> workspaceIds,
    @Default(HistoryFilter()) HistoryFilter filter,

    /// Minimum number of rows. The last day is always loaded completely.
    @Default(50) int limit,
  }) = _HistoryQuery;
}
