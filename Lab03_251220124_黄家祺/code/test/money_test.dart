import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/domain/domain_exception.dart';
import 'package:multibilling/domain/money.dart';

/// 金额值对象测试：定点整数避免浮点误差，解析与格式化的边界。
void main() {
  group('Money 定点运算', () {
    test('0.1 + 0.2 精确等于 0.3（double 会失败的经典案例）', () {
      final sum = Money.fromYuan(0.1) + Money.fromYuan(0.2);
      expect(sum, Money.fromYuan(0.3));
      expect(sum.cents, 30);
      // 对照：原生 double 相加并不相等。
      expect(0.1 + 0.2 == 0.3, isFalse);
    });

    test('以分构造与以元构造等价', () {
      expect(Money.ofCents(12345), Money.fromYuan(123.45));
      expect(Money.fromYuan(123.45).cents, 12345);
    });

    test('减法与符号', () {
      expect((Money.fromYuan(10) - Money.fromYuan(3.5)).cents, 650);
      expect(Money.fromYuan(5).signed(true).cents, 500);
      expect(Money.fromYuan(5).signed(false).cents, -500);
      expect(Money.ofCents(-800).abs().cents, 800);
    });

    test('比较运算与排序', () {
      expect(Money.fromYuan(2) > Money.fromYuan(1), isTrue);
      expect(Money.fromYuan(2) >= Money.fromYuan(2), isTrue);
      expect(Money.fromYuan(1) < Money.fromYuan(2), isTrue);
      expect(Money.fromYuan(2) <= Money.fromYuan(2), isTrue);
      final list = [Money.fromYuan(3), Money.fromYuan(1), Money.fromYuan(2)]
        ..sort();
      expect(list.map((m) => m.cents), [100, 200, 300]);
    });

    test('相等性与 hashCode 一致', () {
      expect(Money.ofCents(100) == Money.fromYuan(1), isTrue);
      expect(Money.ofCents(100).hashCode, Money.fromYuan(1).hashCode);
    });
  });

  group('Money 解析', () {
    test('合法输入', () {
      expect(Money.parse('1234.50').cents, 123450);
      expect(Money.parse('  0.05 ').cents, 5);
      expect(Money.parse('1,234.5').cents, 123450);
      expect(Money.parse('-3.20').cents, -320);
      expect(Money.parse('7').cents, 700);
    });

    test('空串抛校验异常并标注字段', () {
      expect(
        () => Money.parse('   '),
        throwsA(
          isA<ValidationException>().having((e) => e.field, 'field', 'amount'),
        ),
      );
    });

    test('超过两位小数被拒绝', () {
      expect(() => Money.parse('1.234'), throwsA(isA<ValidationException>()));
    });

    test('非数字被拒绝', () {
      expect(() => Money.parse('abc'), throwsA(isA<ValidationException>()));
      expect(() => Money.parse('12元'), throwsA(isA<ValidationException>()));
    });
  });

  group('Money 展示', () {
    test('千分位格式化', () {
      expect(Money.fromYuan(1234.5).formatted, '1,234.50');
      expect(Money.fromYuan(1234567.89).formatted, '1,234,567.89');
      expect(Money.ofCents(-123450).formatted, '-1,234.50');
      expect(Money.zero.formatted, '0.00');
    });

    test('asDecimal 不带千分位', () {
      expect(Money.fromYuan(1234.5).asDecimal, '1234.50');
    });

    test('isPositive 只对正数为真', () {
      expect(Money.zero.isPositive, isFalse);
      expect(Money.ofCents(-1).isPositive, isFalse);
      expect(Money.ofCents(1).isPositive, isTrue);
    });
  });
}
