import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/domain/domain_exception.dart';
import 'package:multibilling/domain/local_date.dart';

/// 日期值对象测试：闰年、合法性校验、区间与天数差。
void main() {
  group('LocalDate 合法性', () {
    test('闰年判定', () {
      expect(LocalDate.isLeapYear(2000), isTrue);
      expect(LocalDate.isLeapYear(2024), isTrue);
      expect(LocalDate.isLeapYear(1900), isFalse);
      expect(LocalDate.isLeapYear(2023), isFalse);
    });

    test('闰年二月允许 29 日', () {
      expect(LocalDate(2024, 2, 29).day, 29);
      expect(LocalDate.daysInMonth(2024, 2), 29);
      expect(LocalDate.daysInMonth(2023, 2), 28);
    });

    test('平年二月 29 日抛异常', () {
      expect(() => LocalDate(2023, 2, 29), throwsA(isA<ValidationException>()));
    });

    test('月份越界抛异常', () {
      expect(() => LocalDate(2024, 0, 1), throwsA(isA<ValidationException>()));
      expect(() => LocalDate(2024, 13, 1), throwsA(isA<ValidationException>()));
    });

    test('小月 31 日抛异常', () {
      expect(() => LocalDate(2024, 4, 31), throwsA(isA<ValidationException>()));
    });
  });

  group('LocalDate 运算', () {
    test('plusDays 跨月跨年', () {
      expect(LocalDate(2024, 1, 31).plusDays(1), LocalDate(2024, 2, 1));
      expect(LocalDate(2024, 12, 31).plusDays(1), LocalDate(2025, 1, 1));
      expect(LocalDate(2024, 3, 1).plusDays(-1), LocalDate(2024, 2, 29));
    });

    test('daysUntil 计算相差天数', () {
      expect(LocalDate(2024, 1, 1).daysUntil(LocalDate(2024, 1, 10)), 9);
      expect(LocalDate(2024, 1, 10).daysUntil(LocalDate(2024, 1, 1)), -9);
    });

    test('isBetween 闭区间', () {
      final from = LocalDate(2024, 1, 1);
      final to = LocalDate(2024, 12, 31);
      expect(LocalDate(2024, 1, 1).isBetween(from, to), isTrue);
      expect(LocalDate(2024, 12, 31).isBetween(from, to), isTrue);
      expect(LocalDate(2024, 6, 15).isBetween(from, to), isTrue);
      expect(LocalDate(2023, 12, 31).isBetween(from, to), isFalse);
      expect(LocalDate(2025, 1, 1).isBetween(from, to), isFalse);
    });

    test('比较运算', () {
      expect(LocalDate(2024, 1, 1) < LocalDate(2024, 1, 2), isTrue);
      expect(LocalDate(2024, 2, 1) > LocalDate(2024, 1, 31), isTrue);
      expect(LocalDate(2024, 1, 1) <= LocalDate(2024, 1, 1), isTrue);
    });
  });

  group('LocalDate 序列化', () {
    test('parse 与 toIsoString 往返', () {
      expect(LocalDate.parse('2024-02-29').toIsoString(), '2024-02-29');
      expect(LocalDate(2024, 1, 5).toIsoString(), '2024-01-05');
    });

    test('非法格式抛异常', () {
      expect(
        () => LocalDate.parse('2024/02/29'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => LocalDate.parse('24-02-29'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('fromDateTime 只取日期部分', () {
      final dt = DateTime(2024, 5, 6, 23, 59, 59);
      expect(LocalDate.fromDateTime(dt), LocalDate(2024, 5, 6));
    });

    test('toMonthLabel 用于趋势图', () {
      expect(LocalDate(2024, 5, 6).toMonthLabel(), '2024年5月');
    });
  });
}
