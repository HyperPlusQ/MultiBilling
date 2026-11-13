import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/domain/entry.dart';
import 'package:multibilling/domain/enums.dart';
import 'package:multibilling/domain/ledger.dart';
import 'package:multibilling/domain/ledger_member.dart';
import 'package:multibilling/domain/local_date.dart';
import 'package:multibilling/domain/money.dart';
import 'package:multibilling/policy/permission_policy.dart';
import 'package:multibilling/repository/memory_database.dart';
import 'package:multibilling/repository/memory_repositories.dart';

/// 权限策略测试：身份/权限正交、只读拦截、发起者不可被降级或自行退出。
void main() {
  late MemoryDatabase db;
  late MemoryLedgerRepository ledgers;
  late PermissionPolicy policy;
  late Ledger ledger;

  // 成员 id 约定：1 发起者，2 管理员，3 普通成员，4 已退出成员。
  LedgerMember member(
    int userId,
    MemberIdentity identity,
    MemberRole role, {
    bool left = false,
  }) => LedgerMember(
    memberId: userId,
    ledgerId: 1,
    userId: userId,
    identity: identity,
    role: role,
    joinedAt: DateTime(2026, 1, 1),
    leftAt: left ? DateTime(2026, 6, 1) : null,
  );

  setUp(() {
    db = MemoryDatabase();
    ledgers = MemoryLedgerRepository(db);
    policy = PermissionPolicy(ledgers);
    ledger = Ledger(
      ledgerId: 1,
      name: '测试账本',
      validFrom: LocalDate(2026, 1, 1),
      validTo: LocalDate(2026, 12, 31),
      ownerId: 1,
      inviteCode: 'ABCD2345',
    );
    ledgers.save(ledger);
    ledgers.saveMember(member(1, MemberIdentity.owner, MemberRole.admin));
    ledgers.saveMember(member(2, MemberIdentity.participant, MemberRole.admin));
    ledgers.saveMember(
      member(3, MemberIdentity.participant, MemberRole.member),
    );
    ledgers.saveMember(
      member(4, MemberIdentity.participant, MemberRole.member, left: true),
    );
  });

  Entry entryOf(int submitter, EntryStatus status) => Entry(
    entryId: 100,
    ledgerId: 1,
    submitterId: submitter,
    categoryId: 1,
    title: '条目',
    direction: EntryDirection.expense,
    amount: Money.fromYuan(10),
    occurredAt: DateTime(2026, 11, 13),
    reason: '事由',
    status: status,
    createdAt: DateTime(2026, 11, 13),
  );

  group('查看与提交', () {
    test('有效成员可查看，退出者与非成员不可', () {
      expect(policy.canView(1, 1), isTrue);
      expect(policy.canView(1, 3), isTrue);
      expect(policy.canView(1, 4), isFalse);
      expect(policy.canView(1, 99), isFalse);
    });

    test('有效成员可提交', () {
      expect(policy.canSubmit(ledger, 3), isTrue);
      expect(policy.canSubmit(ledger, 4), isFalse);
    });

    test('只读账本禁止提交与审核', () {
      ledger.status = LedgerStatus.readOnly;
      expect(policy.canSubmit(ledger, 1), isFalse);
      expect(policy.canReview(ledger, 1), isFalse);
    });
  });

  group('编辑', () {
    test('仅提交人本人可编辑草稿/被驳回', () {
      expect(policy.canEdit(entryOf(3, EntryStatus.draft), 3), isTrue);
      expect(policy.canEdit(entryOf(3, EntryStatus.rejected), 3), isTrue);
      expect(policy.canEdit(entryOf(3, EntryStatus.draft), 2), isFalse);
    });

    test('待审核/已审核条目提交人也不可编辑', () {
      expect(policy.canEdit(entryOf(3, EntryStatus.pending), 3), isFalse);
      expect(policy.canEdit(entryOf(3, EntryStatus.approved), 3), isFalse);
    });
  });

  group('审核与投票', () {
    test('管理员可审核，普通成员不可', () {
      expect(policy.canReview(ledger, 1), isTrue);
      expect(policy.canReview(ledger, 2), isTrue);
      expect(policy.canReview(ledger, 3), isFalse);
    });

    test('发起作废与投票权限等同审核', () {
      expect(policy.canInitiateVoid(ledger, 2), isTrue);
      expect(policy.canVote(ledger, 2), isTrue);
      expect(policy.canVote(ledger, 3), isFalse);
    });
  });

  group('管理员任免与转让', () {
    test('只有发起者能任免管理员', () {
      final target = ledgers.findMember(1, 3)!;
      expect(policy.canManageAdmin(ledger, 1, target), isTrue);
      expect(policy.canManageAdmin(ledger, 2, target), isFalse);
    });

    test('不能对发起者自身任免', () {
      final owner = ledgers.findMember(1, 1)!;
      expect(policy.canManageAdmin(ledger, 1, owner), isFalse);
    });

    test('不能操作已退出成员', () {
      final left = ledgers.findMember(1, 4)!;
      expect(policy.canManageAdmin(ledger, 1, left), isFalse);
    });

    test('转让只能由发起者发起，且不能转给自己或退出者', () {
      final m2 = ledgers.findMember(1, 2)!;
      final m4 = ledgers.findMember(1, 4)!;
      final self = ledgers.findMember(1, 1)!;
      expect(policy.canTransferOwner(ledger, 1, m2), isTrue);
      expect(policy.canTransferOwner(ledger, 2, m2), isFalse);
      expect(policy.canTransferOwner(ledger, 1, self), isFalse);
      expect(policy.canTransferOwner(ledger, 1, m4), isFalse);
    });
  });

  group('账本管理与退出', () {
    test('仅发起者可改设置', () {
      expect(policy.canManageLedger(ledger, 1), isTrue);
      expect(policy.canManageLedger(ledger, 2), isFalse);
    });

    test('发起者不能直接退出，普通成员可以', () {
      expect(policy.canLeave(ledger, 1), isFalse);
      expect(policy.canLeave(ledger, 3), isTrue);
      expect(policy.canLeave(ledger, 4), isFalse);
    });
  });

  group('管理员计数与组合校验', () {
    test('只统计未退出的管理员', () {
      expect(policy.countActiveAdmins(1), 2);
    });

    test('发起者必须持有管理员权限', () {
      expect(
        PermissionPolicy.isValidCombination(
          MemberIdentity.owner,
          MemberRole.admin,
        ),
        isTrue,
      );
      expect(
        PermissionPolicy.isValidCombination(
          MemberIdentity.owner,
          MemberRole.member,
        ),
        isFalse,
      );
      expect(
        PermissionPolicy.isValidCombination(
          MemberIdentity.participant,
          MemberRole.member,
        ),
        isTrue,
      );
    });
  });
}
