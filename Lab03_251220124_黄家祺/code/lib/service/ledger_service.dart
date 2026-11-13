import 'dart:math';

import '../domain/category.dart';
import '../domain/domain_exception.dart';
import '../domain/enums.dart';
import '../domain/ledger.dart';
import '../domain/ledger_member.dart';
import '../domain/local_date.dart';
import '../domain/money.dart';
import '../policy/permission_policy.dart';
import '../repository/memory_database.dart';
import '../repository/repositories.dart';
import 'audit_log_service.dart';

/// 账本服务，对应实验二的「账本管理」模块（需求 REQ-001、REQ-016）。
class LedgerService {
  LedgerService({
    required MemoryDatabase db,
    required LedgerRepository ledgers,
    required CategoryRepository categories,
    required PermissionPolicy permissions,
    required AuditLogService audit,
    Random? random,
  }) : _db = db,
       _ledgers = ledgers,
       _categories = categories,
       _permissions = permissions,
       _audit = audit,
       _random = random ?? Random.secure();

  final MemoryDatabase _db;
  final LedgerRepository _ledgers;
  final CategoryRepository _categories;
  final PermissionPolicy _permissions;
  final AuditLogService _audit;
  final Random _random;

  /// 账本名称长度上限。
  static const int maxNameLength = 40;

  /// 创建账本。发起者自动成为 OWNER + ADMIN，并生成默认类别。
  Ledger create({
    required String name,
    required LocalDate validFrom,
    required LocalDate validTo,
    required int ownerId,
    Money? amountLimit,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ValidationException('账本名称不能为空', field: 'name');
    }
    if (trimmed.length > maxNameLength) {
      throw ValidationException('账本名称不能超过 $maxNameLength 字', field: 'name');
    }
    if (validTo < validFrom) {
      throw ValidationException('有效期结束不能早于开始', field: 'validTo');
    }
    final ledgerId = _db.nextId('ledger');
    final ledger = Ledger(
      ledgerId: ledgerId,
      name: trimmed,
      validFrom: validFrom,
      validTo: validTo,
      ownerId: ownerId,
      inviteCode: _uniqueInviteCode(),
      amountLimit: amountLimit,
    );
    _ledgers.save(ledger);
    _ledgers.saveMember(
      LedgerMember(
        memberId: _db.nextId('member'),
        ledgerId: ledgerId,
        userId: ownerId,
        identity: MemberIdentity.owner,
        role: MemberRole.admin,
        joinedAt: DateTime.now(),
      ),
    );
    for (final category in DefaultCategories.forLedger(
      ledgerId,
      _db.nextId('category'),
    )) {
      _categories.save(category);
      _db.bumpSequence('category', category.categoryId);
    }
    _audit.record(
      DomainEvent(
        ledgerId: ledgerId,
        operatorId: ownerId,
        action: 'LEDGER_CREATE',
        targetType: 'Ledger',
        targetId: ledgerId,
        detail: <String, Object?>{
          'name': trimmed,
          'validFrom': validFrom.toIsoString(),
          'validTo': validTo.toIsoString(),
          'inviteCode': ledger.inviteCode,
        },
      ),
    );
    return ledger;
  }

  /// 生成不与现有账本冲突的邀请码。
  String _uniqueInviteCode() {
    for (var attempt = 0; attempt < 32; attempt++) {
      final code = Ledger.buildInviteCode(_random);
      if (_ledgers.findByInviteCode(code) == null) {
        return code;
      }
    }
    throw ConflictException('邀请码生成失败，请重试');
  }

  /// 用邀请码加入账本。
  LedgerMember joinByInviteCode(String code, int userId) {
    final ledger = _ledgers.findByInviteCode(code.trim().toUpperCase());
    if (ledger == null) {
      throw NotFoundException('邀请码对应的账本');
    }
    if (ledger.isReadOnly) {
      throw ForbiddenException('该账本已只读，不能加入');
    }
    final existing = _ledgers.findMember(ledger.ledgerId, userId);
    if (existing != null && !existing.hasLeft) {
      throw ConflictException('你已经是该账本成员');
    }
    final member =
        existing ??
        LedgerMember(
          memberId: _db.nextId('member'),
          ledgerId: ledger.ledgerId,
          userId: userId,
          identity: MemberIdentity.participant,
          role: MemberRole.member,
          joinedAt: DateTime.now(),
        );
    // 重新加入时清空退出标记，但保留原 memberId 以维持历史关联。
    member.leftAt = null;
    _ledgers.saveMember(member);
    _audit.record(
      DomainEvent(
        ledgerId: ledger.ledgerId,
        operatorId: userId,
        action: 'LEDGER_JOIN',
        targetType: 'LedgerMember',
        targetId: member.memberId,
        detail: <String, Object?>{'inviteCode': ledger.inviteCode},
      ),
    );
    return member;
  }

  /// 退出账本。发起者必须先转让。
  void leave(int ledgerId, int userId) {
    final ledger = requireLedger(ledgerId);
    if (!_permissions.canLeave(ledger, userId)) {
      throw ForbiddenException('发起者不能直接退出，请先转让给其他成员');
    }
    final member = _ledgers.findMember(ledgerId, userId)!;
    member.leave(DateTime.now());
    _ledgers.saveMember(member);
    _audit.record(
      DomainEvent(
        ledgerId: ledgerId,
        operatorId: userId,
        action: 'LEDGER_LEAVE',
        targetType: 'LedgerMember',
        targetId: member.memberId,
      ),
    );
  }

  /// 转让发起者。原发起者降为参与者但保留管理员权限（假设 A8）。
  void transferOwnership(int ledgerId, int operatorId, int targetUserId) {
    final ledger = requireLedger(ledgerId);
    final target = _ledgers.findMember(ledgerId, targetUserId);
    if (target == null) {
      throw NotFoundException('目标成员');
    }
    if (!_permissions.canTransferOwner(ledger, operatorId, target)) {
      throw ForbiddenException('只有发起者可以转让，且不能转让给自己或已退出成员');
    }
    final previous = _ledgers.findMember(ledgerId, operatorId)!;
    previous.identity = MemberIdentity.participant;
    previous.role = MemberRole.admin;
    target.identity = MemberIdentity.owner;
    target.role = MemberRole.admin;
    ledger.ownerId = targetUserId;
    _ledgers.saveMember(previous);
    _ledgers.saveMember(target);
    _ledgers.save(ledger);
    _audit.record(
      DomainEvent(
        ledgerId: ledgerId,
        operatorId: operatorId,
        action: 'LEDGER_TRANSFER',
        targetType: 'Ledger',
        targetId: ledgerId,
        detail: <String, Object?>{'from': operatorId, 'to': targetUserId},
      ),
    );
  }

  /// 修改账本设置。仅发起者，且有效期不能倒置。
  void updateSettings(
    int ledgerId,
    int operatorId, {
    String? name,
    LocalDate? validFrom,
    LocalDate? validTo,
    Money? amountLimit,
  }) {
    final ledger = requireLedger(ledgerId);
    if (!_permissions.canManageLedger(ledger, operatorId)) {
      throw ForbiddenException('只有发起者可以修改账本设置');
    }
    final from = validFrom ?? ledger.validFrom;
    final to = validTo ?? ledger.validTo;
    if (to < from) {
      throw ValidationException('有效期结束不能早于开始', field: 'validTo');
    }
    if (name != null) {
      if (name.trim().isEmpty) {
        throw ValidationException('账本名称不能为空', field: 'name');
      }
      ledger.name = name.trim();
    }
    ledger.validFrom = from;
    ledger.validTo = to;
    if (amountLimit != null) {
      ledger.amountLimit = amountLimit;
      _audit.record(
        DomainEvent(
          ledgerId: ledgerId,
          operatorId: operatorId,
          action: 'AMOUNT_LIMIT_CHANGE',
          targetType: 'Ledger',
          targetId: ledgerId,
          detail: <String, Object?>{'amountLimit': amountLimit.asDecimal},
        ),
      );
    }
    _ledgers.save(ledger);
  }

  /// 按今天日期刷新过期状态。过期账本转为只读（假设 A5）。
  void refreshExpiry(int ledgerId, LocalDate today) {
    final ledger = requireLedger(ledgerId);
    if (ledger.status == LedgerStatus.archived) {
      return;
    }
    ledger.status = ledger.isExpired(today)
        ? LedgerStatus.readOnly
        : LedgerStatus.active;
    _ledgers.save(ledger);
  }

  /// 取账本，不存在时抛异常。
  Ledger requireLedger(int ledgerId) {
    final ledger = _ledgers.findById(ledgerId);
    if (ledger == null) {
      throw NotFoundException('账本 $ledgerId');
    }
    return ledger;
  }

  /// 某用户可见的账本列表。
  List<Ledger> ledgersOfUser(int userId) =>
      _ledgers
          .findLedgerIdsOfUser(userId)
          .map(_ledgers.findById)
          .whereType<Ledger>()
          .toList()
        ..sort((Ledger a, Ledger b) => a.ledgerId - b.ledgerId);

  /// 某账本的类别列表。
  List<Category> categoriesOf(int ledgerId) => _categories.byLedger(ledgerId);

  /// 某账本的有效成员列表。
  List<LedgerMember> activeMembers(int ledgerId) => _ledgers
      .findMembers(ledgerId)
      .where((LedgerMember m) => !m.hasLeft)
      .toList();
}
