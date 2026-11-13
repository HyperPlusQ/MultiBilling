import '../domain/entry.dart';
import '../domain/enums.dart';
import '../domain/ledger.dart';
import '../domain/ledger_member.dart';
import '../repository/repositories.dart';

/// 权限策略，对应类图中的 `PermissionPolicy`。
///
/// 所有「能不能做」的判断集中在这里，服务层只调用不自行判断。
/// 前端隐藏按钮只是体验层优化，真正的拦截发生在这一层。
class PermissionPolicy {
  PermissionPolicy(this._ledgers);

  final LedgerRepository _ledgers;

  /// 取出成员记录；不存在或已退出都视为无权。
  LedgerMember? activeMember(int ledgerId, int userId) {
    final member = _ledgers.findMember(ledgerId, userId);
    if (member == null || member.hasLeft) {
      return null;
    }
    return member;
  }

  /// 是否有权查看该账本。退出后不可再读数据。
  bool canView(int ledgerId, int userId) =>
      activeMember(ledgerId, userId) != null;

  /// 是否有权提交条目。需要是有效成员且账本未过期。
  bool canSubmit(Ledger ledger, int userId) {
    if (ledger.isReadOnly) {
      return false;
    }
    return activeMember(ledger.ledgerId, userId) != null;
  }

  /// 是否有权编辑该条目。仅提交人本人，且状态为草稿或被驳回。
  bool canEdit(Entry entry, int userId) {
    if (!canView(entry.ledgerId, userId)) {
      return false;
    }
    return entry.isEditableBy(userId);
  }

  /// 是否有权审核。需要管理员权限且账本可写。
  bool canReview(Ledger ledger, int userId) {
    if (ledger.isReadOnly) {
      return false;
    }
    final member = activeMember(ledger.ledgerId, userId);
    return member != null && member.isAdmin;
  }

  /// 是否有权发起作废投票。与审核同权限。
  bool canInitiateVoid(Ledger ledger, int userId) => canReview(ledger, userId);

  /// 是否有权参与作废投票。
  bool canVote(Ledger ledger, int userId) => canReview(ledger, userId);

  /// 操作者能否变更目标成员的权限。
  ///
  /// 规则：只有发起者能任免管理员；发起者自身不可被降级；
  /// 不能操作已退出的成员。
  bool canManageAdmin(Ledger ledger, int operatorId, LedgerMember target) {
    if (target.hasLeft) {
      return false;
    }
    final operator = activeMember(ledger.ledgerId, operatorId);
    if (operator == null || !operator.isOwner) {
      return false;
    }
    if (target.isOwner) {
      return false;
    }
    return true;
  }

  /// 能否把发起者转让给目标成员。
  ///
  /// 只有现任发起者可以转让，目标必须是仍在账本内的其他成员。
  bool canTransferOwner(Ledger ledger, int operatorId, LedgerMember target) {
    if (target.hasLeft || target.userId == operatorId) {
      return false;
    }
    final operator = activeMember(ledger.ledgerId, operatorId);
    return operator != null && operator.isOwner;
  }

  /// 能否修改账本设置（名称、有效期、金额上限）。仅发起者。
  bool canManageLedger(Ledger ledger, int userId) {
    final member = activeMember(ledger.ledgerId, userId);
    return member != null && member.isOwner;
  }

  /// 能否退出账本。发起者必须先转让才能退出。
  bool canLeave(Ledger ledger, int userId) {
    final member = activeMember(ledger.ledgerId, userId);
    return member != null && !member.isOwner;
  }

  /// 统计当前有效管理员人数，作废申请创建时快照这个值。
  int countActiveAdmins(int ledgerId) => _ledgers
      .findMembers(ledgerId)
      .where((LedgerMember m) => !m.hasLeft && m.isAdmin)
      .length;

  /// 校验成员身份与权限的组合是否合法。
  ///
  /// 发起者必须持有管理员权限，这是不变量而非可配置项。
  static bool isValidCombination(MemberIdentity identity, MemberRole role) {
    if (identity == MemberIdentity.owner) {
      return role == MemberRole.admin;
    }
    return true;
  }
}
