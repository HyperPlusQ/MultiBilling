import 'enums.dart';

/// 账本成员，对应类图中的 `LedgerMember`。
///
/// 同时持有 [identity] 与 [role] 两个正交维度：身份回答「谁建的账本」，
/// 权限回答「能不能审核」。合并成单一角色会产生四种组合爆炸。
class LedgerMember {
  LedgerMember({
    required this.memberId,
    required this.ledgerId,
    required this.userId,
    required this.identity,
    required this.role,
    required this.joinedAt,
    this.leftAt,
  });

  /// 从 JSON 还原。
  factory LedgerMember.fromJson(Map<String, Object?> json) => LedgerMember(
    memberId: json['memberId']! as int,
    ledgerId: json['ledgerId']! as int,
    userId: json['userId']! as int,
    identity: MemberIdentity.values.byName(json['identity']! as String),
    role: MemberRole.values.byName(json['role']! as String),
    joinedAt: DateTime.parse(json['joinedAt']! as String),
    leftAt: json['leftAt'] == null
        ? null
        : DateTime.parse(json['leftAt']! as String),
  );

  /// 主键。
  final int memberId;

  /// 所属账本。
  final int ledgerId;

  /// 关联的用户。
  final int userId;

  /// 身份。
  MemberIdentity identity;

  /// 权限。
  MemberRole role;

  /// 加入时间。
  final DateTime joinedAt;

  /// 退出时间，`null` 表示仍在账本内。
  DateTime? leftAt;

  /// 是否为发起者。
  bool get isOwner => identity == MemberIdentity.owner;

  /// 是否具备管理员权限；发起者恒为真。
  bool get isAdmin => isOwner || role == MemberRole.admin;

  /// 是否已退出。退出后不可再读取该账本数据，但历史条目仍保留其署名。
  bool get hasLeft => leftAt != null;

  /// 标记退出。发起者不能退出，必须先转让。
  void leave(DateTime at) {
    leftAt = at;
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'memberId': memberId,
    'ledgerId': ledgerId,
    'userId': userId,
    'identity': identity.name,
    'role': role.name,
    'joinedAt': joinedAt.toIso8601String(),
    'leftAt': leftAt?.toIso8601String(),
  };

  @override
  String toString() =>
      'LedgerMember($memberId, ledger=$ledgerId, ${identity.label}/${role.label})';
}
