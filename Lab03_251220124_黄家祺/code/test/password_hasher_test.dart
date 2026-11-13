import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/domain/password_hasher.dart';

/// 口令散列测试：加盐迭代 SHA-256 的往返校验与抗篡改。
void main() {
  group('PasswordHasher', () {
    test('同一口令与盐可复现校验', () {
      final salt = PasswordHasher.newSalt();
      final stored = PasswordHasher.hash('correct horse', salt);
      expect(PasswordHasher.verify('correct horse', stored), isTrue);
    });

    test('错误口令校验失败', () {
      final salt = PasswordHasher.newSalt();
      final stored = PasswordHasher.hash('correct horse', salt);
      expect(PasswordHasher.verify('wrong horse', stored), isFalse);
    });

    test('相同口令不同盐得到不同散列（抗彩虹表）', () {
      final h1 = PasswordHasher.hash('same', PasswordHasher.newSalt());
      final h2 = PasswordHasher.hash('same', PasswordHasher.newSalt());
      expect(h1, isNot(h2));
    });

    test('散列格式含算法标记、迭代次数与盐', () {
      final salt = PasswordHasher.newSalt();
      final stored = PasswordHasher.hash('pw', salt);
      final parts = stored.split(r'$');
      expect(parts.length, 3);
      expect(parts[0], 'pbkdf2-like-sha256#${PasswordHasher.iterations}');
      expect(parts[1], salt);
    });

    test('存储串被截断或篡改时校验失败', () {
      final stored = PasswordHasher.hash('pw', PasswordHasher.newSalt());
      expect(PasswordHasher.verify('pw', 'garbage'), isFalse);
      expect(
        PasswordHasher.verify('pw', stored.substring(0, stored.length - 2)),
        isFalse,
      );
    });

    test('盐每次生成不同', () {
      expect(PasswordHasher.newSalt(), isNot(PasswordHasher.newSalt()));
    });
  });
}
