import '../domain/domain_exception.dart';
import '../domain/enums.dart';
import '../domain/ledger_member.dart';
import '../policy/permission_policy.dart';
import '../repository/repositories.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';

/// 成员与权限服务，对应实验二的「成员与权限」模块（需求 REQ-002）。
class MemberService {
  MemberService({
    required LedgerRepository ledgers,
    required PermissionPolicy permissions,
    required AuditLogService audit,
    required AuthService auth,
  }) : _ledgers = ledgers,
       _permissions = permissions,
       _audit = audit,
       _auth = auth;

  final LedgerRepository _ledgers;
  final PermissionPolicy _permissions;
  final AuditLogService _audit;
  final AuthService _auth;

  /// 任免管理员。只有发起者能操作，且不能动发起者自己。
  void setRole({
    required int ledgerId,
    required int operatorId,
    required int targetUserId,
    required MemberRole role,
  }) {
    final ledger = _ledgers.findById(ledgerId);
    if (ledger == null) {
      throw NotFoundException('账本 $ledgerId');
    }
    final target = _ledgers.findMember(ledgerId, targetUserId);
    if (target == null) {
      throw NotFoundException('目标成员');
    }
    if (!_permissions.canManageAdmin(ledger, operatorId, target)) {
      throw ForbiddenException('只有发起者可以任免管理员，且不能变更发起者自身');
    }
    if (!PermissionPolicy.isValidCombination(target.identity, role)) {
      throw ValidationException('发起者必须持有管理员权限');
    }
    final previous = target.role;
    target.role = role;
    _ledgers.saveMember(target);
    _audit.record(
      DomainEvent(
        ledgerId: ledgerId,
        operatorId: operatorId,
        action: 'MEMBER_ROLE_CHANGE',
        targetType: 'LedgerMember',
        targetId: target.memberId,
        detail: <String, Object?>{
          'userId': targetUserId,
          'from': previous.name,
          'to': role.name,
        },
      ),
    );
  }

  /// 某账本的成员视图，含显示名与身份权限标签。
  List<MemberView> memberViews(int ledgerId) {
    final members = _ledgers.findMembers(ledgerId);
    return members
        .map(
          (LedgerMember m) => MemberView(
            member: m,
            displayName: _auth.displayNameOf(m.userId),
            username: _auth.requireUser(m.userId).username,
          ),
        )
        .toList();
  }

  /// 当前有效管理员人数。
  int adminCount(int ledgerId) => _permissions.countActiveAdmins(ledgerId);

  /// 判断某用户在某账本是否管理员。
  bool isAdmin(int ledgerId, int userId) {
    final member = _permissions.activeMember(ledgerId, userId);
    return member != null && member.isAdmin;
  }
}

/// 成员列表的展示模型，把领域对象与显示名拼在一起。
class MemberView {
  const MemberView({
    required this.member,
    required this.displayName,
    required this.username,
  });

  /// 领域成员对象。
  final LedgerMember member;

  /// 显示名。
  final String displayName;

  /// 登录名。
  final String username;

  /// 身份与权限的组合标签，如「发起者 · 管理员」。
  String get badge => '${member.identity.label} · ${member.role.label}';

  /// 是否已退出。
  bool get hasLeft => member.hasLeft;

  /// 退出成员的展示后缀。
  String get label => hasLeft ? '$displayName（已退出）' : displayName;
}
