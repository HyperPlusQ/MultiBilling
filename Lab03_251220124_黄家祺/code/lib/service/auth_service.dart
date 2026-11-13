import '../domain/domain_exception.dart';
import '../domain/enums.dart';
import '../domain/password_hasher.dart';
import '../domain/user.dart';
import '../repository/memory_database.dart';
import '../repository/repositories.dart';

/// 认证服务，对应实验二的「账户与认证」模块（需求 REQ-017）。
///
/// 桌面单机版没有 HTTP 会话，登录成功后由界面层持有当前 [User]，
/// 后续所有服务调用都显式传入操作者 id，权限判定不依赖任何全局状态。
class AuthService {
  AuthService(this._db, this._users);

  final MemoryDatabase _db;
  final UserRepository _users;

  /// 用户名最短长度。
  static const int minUsernameLength = 3;

  /// 口令最短长度。
  static const int minPasswordLength = 6;

  /// 注册新账号。
  User register({
    required String username,
    required String password,
    required String displayName,
  }) {
    final name = username.trim();
    if (name.length < minUsernameLength) {
      throw ValidationException(
        '用户名至少 $minUsernameLength 个字符',
        field: 'username',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) {
      throw ValidationException('用户名只能包含字母、数字与下划线', field: 'username');
    }
    if (password.length < minPasswordLength) {
      throw ValidationException(
        '口令至少 $minPasswordLength 个字符',
        field: 'password',
      );
    }
    if (displayName.trim().isEmpty) {
      throw ValidationException('显示名不能为空', field: 'displayName');
    }
    if (_users.findByUsername(name) != null) {
      throw ConflictException('用户名已被占用', field: 'username');
    }
    final salt = PasswordHasher.newSalt();
    final user = User(
      userId: _db.nextId('user'),
      username: name,
      passwordHash: PasswordHasher.hash(password, salt),
      displayName: displayName.trim(),
    );
    return _users.save(user);
  }

  /// 登录校验。
  ///
  /// 用户名不存在与口令错误返回同一条提示，避免账号枚举。
  User login(String username, String password) {
    final user = _users.findByUsername(username.trim());
    if (user == null || !PasswordHasher.verify(password, user.passwordHash)) {
      throw ValidationException('用户名或口令不正确', field: 'password');
    }
    if (!user.isEnabled) {
      throw ForbiddenException('该账号已停用');
    }
    return user;
  }

  /// 修改口令，需要先校验旧口令。
  void changePassword(int userId, String oldPassword, String newPassword) {
    final user = _users.findById(userId);
    if (user == null) {
      throw NotFoundException('用户');
    }
    if (!PasswordHasher.verify(oldPassword, user.passwordHash)) {
      throw ValidationException('原口令不正确', field: 'oldPassword');
    }
    if (newPassword.length < minPasswordLength) {
      throw ValidationException(
        '新口令至少 $minPasswordLength 个字符',
        field: 'newPassword',
      );
    }
    final salt = PasswordHasher.newSalt();
    final updated = User(
      userId: user.userId,
      username: user.username,
      passwordHash: PasswordHasher.hash(newPassword, salt),
      displayName: user.displayName,
      status: user.status,
    );
    _users.save(updated);
  }

  /// 按 id 取用户，找不到时抛异常。
  User requireUser(int userId) {
    final user = _users.findById(userId);
    if (user == null) {
      throw NotFoundException('用户 $userId');
    }
    return user;
  }

  /// 取显示名，用户已删除时回退为占位文本。
  String displayNameOf(int userId) =>
      _users.findById(userId)?.displayName ?? '用户 $userId';

  /// 全部账号，成员选择器用。
  List<User> allUsers() => _users.all();

  /// 停用账号。历史条目仍保留其署名。
  void disable(int userId) {
    final user = requireUser(userId);
    user.status = UserStatus.disabled;
    _users.save(user);
  }
}
