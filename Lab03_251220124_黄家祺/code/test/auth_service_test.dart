import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/domain/domain_exception.dart';
import 'package:multibilling/domain/enums.dart';
import 'package:multibilling/repository/memory_database.dart';
import 'package:multibilling/repository/memory_repositories.dart';
import 'package:multibilling/service/auth_service.dart';

/// 认证服务测试：注册校验、登录防枚举、改密、停用。
void main() {
  late AuthService auth;

  setUp(() {
    final db = MemoryDatabase();
    auth = AuthService(db, MemoryUserRepository(db));
  });

  group('注册', () {
    test('合法注册成功并可登录', () {
      final u = auth.register(
        username: 'alice',
        password: 'secret123',
        displayName: '爱丽丝',
      );
      expect(u.username, 'alice');
      expect(u.displayName, '爱丽丝');
      expect(auth.login('alice', 'secret123').userId, u.userId);
    });

    test('用户名过短被拒', () {
      expect(
        () => auth.register(
          username: 'ab',
          password: 'secret123',
          displayName: 'x',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.field,
            'field',
            'username',
          ),
        ),
      );
    });

    test('用户名含非法字符被拒', () {
      expect(
        () => auth.register(
          username: 'bad name!',
          password: 'secret123',
          displayName: 'x',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('口令过短被拒', () {
      expect(
        () =>
            auth.register(username: 'alice', password: '123', displayName: 'x'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.field,
            'field',
            'password',
          ),
        ),
      );
    });

    test('显示名为空被拒', () {
      expect(
        () => auth.register(
          username: 'alice',
          password: 'secret123',
          displayName: '  ',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('用户名重复被拒', () {
      auth.register(username: 'alice', password: 'secret123', displayName: 'x');
      expect(
        () => auth.register(
          username: 'alice',
          password: 'other123',
          displayName: 'y',
        ),
        throwsA(isA<ConflictException>()),
      );
    });

    test('口令不以明文存储', () {
      final u = auth.register(
        username: 'alice',
        password: 'secret123',
        displayName: 'x',
      );
      expect(u.passwordHash.contains('secret123'), isFalse);
    });
  });

  group('登录', () {
    test('用户名不存在与口令错误返回同一提示（防账号枚举）', () {
      auth.register(username: 'alice', password: 'secret123', displayName: 'x');
      Object? noUser;
      Object? badPw;
      try {
        auth.login('nobody', 'secret123');
      } catch (e) {
        noUser = e;
      }
      try {
        auth.login('alice', 'wrongpass');
      } catch (e) {
        badPw = e;
      }
      expect(noUser, isA<ValidationException>());
      expect(badPw, isA<ValidationException>());
      expect(
        (noUser! as ValidationException).message,
        (badPw! as ValidationException).message,
      );
    });

    test('停用账号不能登录', () {
      final u = auth.register(
        username: 'alice',
        password: 'secret123',
        displayName: 'x',
      );
      auth.disable(u.userId);
      expect(u.status, UserStatus.disabled);
      expect(
        () => auth.login('alice', 'secret123'),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });

  group('修改口令', () {
    test('旧口令正确时改密成功，新口令可登录', () {
      final u = auth.register(
        username: 'alice',
        password: 'secret123',
        displayName: 'x',
      );
      auth.changePassword(u.userId, 'secret123', 'newsecret456');
      expect(auth.login('alice', 'newsecret456').userId, u.userId);
      expect(
        () => auth.login('alice', 'secret123'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('旧口令错误时拒绝改密', () {
      final u = auth.register(
        username: 'alice',
        password: 'secret123',
        displayName: 'x',
      );
      expect(
        () => auth.changePassword(u.userId, 'wrong', 'newsecret456'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('新口令过短被拒', () {
      final u = auth.register(
        username: 'alice',
        password: 'secret123',
        displayName: 'x',
      );
      expect(
        () => auth.changePassword(u.userId, 'secret123', '123'),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
