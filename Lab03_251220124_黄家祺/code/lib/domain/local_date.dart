import 'domain_exception.dart';

/// 日期值对象（不含时间与时区）。
///
/// 实验二设计中的 `LocalDate` 在 Dart 里没有对应类型；直接用 `DateTime`
/// 会把本地时区带进账本有效期的比较，跨时区会出现「同一天判定不一致」。
/// 因此这里用年月日三个整数自行实现。
class LocalDate implements Comparable<LocalDate> {
  /// 构造日期，会校验月日合法性。
  factory LocalDate(int year, int month, int day) {
    if (month < 1 || month > 12) {
      throw ValidationException('月份必须在 1 到 12 之间', field: 'month');
    }
    if (day < 1 || day > daysInMonth(year, month)) {
      throw ValidationException('日期超出该月天数', field: 'day');
    }
    return LocalDate._(year, month, day);
  }

  const LocalDate._(this.year, this.month, this.day);

  /// 从 `DateTime` 提取本地日期部分。
  factory LocalDate.fromDateTime(DateTime value) =>
      LocalDate(value.year, value.month, value.day);

  /// 今天。
  factory LocalDate.today() => LocalDate.fromDateTime(DateTime.now());

  /// 解析 `yyyy-MM-dd`。
  factory LocalDate.parse(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
    if (match == null) {
      throw ValidationException('日期格式应为 yyyy-MM-dd', field: 'date');
    }
    return LocalDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// 年。
  final int year;

  /// 月，1 起始。
  final int month;

  /// 日，1 起始。
  final int day;

  /// 判断某年是否闰年。
  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  /// 某年某月的天数。
  static const List<int> _monthLength = <int>[
    31,
    28,
    31,
    30,
    31,
    30,
    30,
    31,
    31,
    30,
    31,
    31,
  ];

  /// 某年某月的天数，考虑闰年。
  static int daysInMonth(int year, int month) {
    if (month == 2 && isLeapYear(year)) {
      return 29;
    }
    return _monthLength[month - 1];
  }

  /// 转换为当天零点的 `DateTime`。
  DateTime toDateTime() => DateTime(year, month, day);

  /// 转换为 `yyyy-MM-dd`。
  String toIsoString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// 转换为 `yyyy年M月`，用于趋势图横轴。
  String toMonthLabel() => '$year年$month月';

  /// 加上若干天。
  LocalDate plusDays(int days) =>
      LocalDate.fromDateTime(toDateTime().add(Duration(days: days)));

  /// 与另一个日期相差的天数（本日期减另一日期）。
  int daysUntil(LocalDate other) =>
      other.toDateTime().difference(toDateTime()).inDays;

  /// 是否落在 [from, to] 闭区间内。
  bool isBetween(LocalDate from, LocalDate to) =>
      compareTo(from) >= 0 && compareTo(to) <= 0;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year - other.year;
    if (month != other.month) return month - other.month;
    return day - other.day;
  }

  bool operator <(LocalDate other) => compareTo(other) < 0;

  bool operator <=(LocalDate other) => compareTo(other) <= 0;

  bool operator >(LocalDate other) => compareTo(other) > 0;

  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIsoString();
}
