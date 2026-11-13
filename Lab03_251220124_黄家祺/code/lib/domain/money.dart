import 'domain_exception.dart';

/// 金额值对象。
///
/// 实验二设计使用 Java `BigDecimal`，Dart 标准库没有等价的十进制定点类型，
/// 而记账金额参与求和与比较，用 `double` 会产生 `0.1 + 0.2 != 0.3` 这类误差。
/// 因此这里改用「分」为最小单位的定点整数表示，对外仍以元为单位格式化。
class Money implements Comparable<Money> {
  /// 以「分」为单位构造。
  const Money.ofCents(this.cents);

  /// 以「元」为单位构造，允许两位小数。
  factory Money.fromYuan(num yuan) {
    final rounded = (yuan * 100).round();
    return Money.ofCents(rounded);
  }

  /// 解析界面输入的元字符串，最多两位小数。
  factory Money.parse(String input) {
    final trimmed = input.trim().replaceAll(',', '');
    if (trimmed.isEmpty) {
      throw ValidationException('金额不能为空', field: 'amount');
    }
    final match = RegExp(r'^-?\d+(\.\d{1,2})?$').firstMatch(trimmed);
    if (match == null) {
      throw ValidationException('金额格式不正确，最多两位小数', field: 'amount');
    }
    final value = double.parse(trimmed);
    return Money.fromYuan(value);
  }

  /// 最小货币单位：分。
  final int cents;

  /// 零金额。
  static const Money zero = Money.ofCents(0);

  /// 是否为正数。
  bool get isPositive => cents > 0;

  /// 取绝对值。
  Money abs() => Money.ofCents(cents.abs());

  /// 按收支方向加上符号，供统计聚合使用。
  Money signed(bool isIncome) => Money.ofCents(isIncome ? cents : -cents);

  Money operator +(Money other) => Money.ofCents(cents + other.cents);

  Money operator -(Money other) => Money.ofCents(cents - other.cents);

  bool operator >(Money other) => cents > other.cents;

  bool operator >=(Money other) => cents >= other.cents;

  bool operator <(Money other) => cents < other.cents;

  bool operator <=(Money other) => cents <= other.cents;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  /// 元为单位的数值，仅用于展示与图表，不参与业务判断。
  double get yuan => cents / 100.0;

  /// 保留两位小数的纯数字，如 `1234.50`。
  String get asDecimal => yuan.toStringAsFixed(2);

  /// 带千分位的展示文本，如 `1,234.50`。
  String get formatted {
    final sign = cents < 0 ? '-' : '';
    final fixed = yuan.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final buffer = StringBuffer();
    final digits = parts.first;
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return '$sign$buffer.${parts[1]}';
  }

  @override
  String toString() => asDecimal;
}
