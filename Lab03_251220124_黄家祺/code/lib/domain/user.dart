import 'enums.dart';

/// 用户账号，对应类图中的 `User`。
///
/// 桌面版是单机多用户模型：账号在进程内切换，不存在远端会话，
/// 因此这里只保留身份判定所需的最小字段。
class User {
  User({
    required this.userId,
    required this.username,
    required this.passwordHash,
    required this.displayName,
    this.status = UserStatus.active,
  });

  /// 从 JSON 还原。
  factory User.fromJson(Map<String, Object?> json) => User(
    userId: json['userId']! as int,
    username: json['username']! as String,
    passwordHash: json['passwordHash']! as String,
    displayName: json['displayName']! as String,
    status: UserStatus.values.firstWhere(
      (UserStatus value) => value.name == json['status'],
      orElse: () => UserStatus.active,
    ),
  );

  /// 全局唯一主键。
  final int userId;

  /// 登录名，全局唯一。
  final String username;

  /// 慢哈希结果，绝不保存明文。
  final String passwordHash;

  /// 账本成员列表中展示的名字。
  final String displayName;

  /// 账号状态。
  UserStatus status;

  /// 账号是否可用；停用后不能登录，但历史条目仍保留其署名。
  bool get isEnabled => status == UserStatus.active;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'passwordHash': passwordHash,
    'displayName': displayName,
    'status': status.name,
  };

  @override
  String toString() => 'User($userId, $username)';
}
