import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/app_services.dart';
import 'package:multibilling/domain/attachment.dart';
import 'package:multibilling/domain/category.dart';
import 'package:multibilling/domain/domain_exception.dart';
import 'package:multibilling/domain/entry.dart';
import 'package:multibilling/domain/enums.dart';
import 'package:multibilling/domain/ledger.dart';
import 'package:multibilling/domain/local_date.dart';
import 'package:multibilling/domain/money.dart';
import 'package:multibilling/domain/operation_log.dart';
import 'package:multibilling/domain/user.dart';
import 'package:multibilling/domain/void_request.dart';
import 'package:multibilling/repository/repositories.dart';
import 'package:multibilling/service/entry_service.dart';
import 'package:multibilling/service/statistics_service.dart';

/// 端到端集成测试：用可注入时钟驱动完整业务流，覆盖实验二的关键设计决策。
///
/// 所有服务经 [AppServices.create] 装配，内存数据库 + 临时附件目录，
/// 不依赖任何外部进程。时钟由 [Harness.now] 控制，作废超时无需真等 72 小时。
class Harness {
  Harness({Money? amountLimit, int extraAdmins = 1}) {
    now = DateTime(2026, 11, 13, 10);
    app = AppServices.create(clock: () => now);
    owner = app.auth.register(
      username: 'owner',
      password: 'pw123456',
      displayName: '发起者',
    );
    admins = <User>[
      for (var i = 0; i < extraAdmins; i++)
        app.auth.register(
          username: 'admin$i',
          password: 'pw123456',
          displayName: '管理$i',
        ),
    ];
    member = app.auth.register(
      username: 'member',
      password: 'pw123456',
      displayName: '成员',
    );
    ledger = app.ledgerService.create(
      name: '测试账本',
      validFrom: LocalDate(2026, 1, 1),
      validTo: LocalDate(2026, 12, 31),
      ownerId: owner.userId,
      amountLimit: amountLimit,
    );
    for (final a in admins) {
      app.ledgerService.joinByInviteCode(ledger.inviteCode, a.userId);
      app.memberService.setRole(
        ledgerId: ledger.ledgerId,
        operatorId: owner.userId,
        targetUserId: a.userId,
        role: MemberRole.admin,
      );
    }
    app.ledgerService.joinByInviteCode(ledger.inviteCode, member.userId);
    final cats = app.ledgerService.categoriesOf(ledger.ledgerId);
    expenseCat = cats.firstWhere((c) => c.direction == EntryDirection.expense);
    incomeCat = cats.firstWhere((c) => c.direction == EntryDirection.income);
  }

  late DateTime now;
  late AppServices app;
  late User owner;
  late User member;
  late List<User> admins;
  late Ledger ledger;
  late Category expenseCat;
  late Category incomeCat;
  int _seq = 0;

  /// 默认发生时间逐次错开一分钟，避免无关条目误触重复检测。
  Entry draft({
    Money? amount,
    DateTime? occurredAt,
    int? submitter,
    EntryDirection direction = EntryDirection.expense,
    String title = '测试条目',
  }) {
    final cat = direction == EntryDirection.expense ? expenseCat : incomeCat;
    final who = submitter ?? member.userId;
    return app.entryService.createDraft(
      ledger.ledgerId,
      EntryCommand(
        categoryId: cat.categoryId,
        title: title,
        amount: amount ?? Money.fromYuan(100),
        occurredAt: occurredAt ?? now.add(Duration(minutes: _seq++)),
        reason: '事由',
      ),
      who,
    );
  }

  Entry approved({
    Money? amount,
    DateTime? occurredAt,
    int? submitter,
    EntryDirection direction = EntryDirection.expense,
    String title = '测试条目',
  }) {
    final who = submitter ?? member.userId;
    final e = draft(
      amount: amount,
      occurredAt: occurredAt,
      submitter: who,
      direction: direction,
      title: title,
    );
    app.entryService.submit(e.entryId, who);
    app.reviewService.review(
      entryId: e.entryId,
      action: ReviewAction.approve,
      comment: '',
      adminId: owner.userId,
    );
    return e;
  }

  Attachment uploadProof(int entryId, {int? uploader}) {
    final dir = Directory.systemTemp.createTempSync('mb_test_proof');
    final f = File('${dir.path}/proof.png')..writeAsBytesSync([1, 2, 3, 4, 5]);
    return app.attachmentService.upload(
      ledgerId: ledger.ledgerId,
      entryId: entryId,
      uploaderId: uploader ?? member.userId,
      source: f,
      purpose: AttachmentPurpose.proof,
    );
  }
}

void main() {
  group('条目生命周期', () {
    test('草稿 → 提交 → 审核通过，时间线与存档同步', () {
      final h = Harness();
      final e = h.draft();
      expect(e.status, EntryStatus.draft);
      h.app.entryService.submit(e.entryId, h.member.userId);
      expect(e.status, EntryStatus.pending);
      h.app.reviewService.review(
        entryId: e.entryId,
        action: ReviewAction.approve,
        comment: '票据齐全',
        adminId: h.owner.userId,
      );
      expect(e.status, EntryStatus.approved);
      expect(e.lastReviewerId, h.owner.userId);
      final timeline = h.app.reviewService.timeline(e.entryId);
      expect(timeline.length, 1);
      expect(timeline.single.action, ReviewAction.approve);
      expect(h.app.audit.verifyChain(h.ledger.ledgerId).valid, isTrue);
    });

    test('非提交人不能提交他人条目', () {
      final h = Harness();
      final e = h.draft(submitter: h.member.userId);
      expect(
        () => h.app.entryService.submit(e.entryId, h.owner.userId),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('非管理员不能审核', () {
      final h = Harness();
      final e = h.draft();
      h.app.entryService.submit(e.entryId, h.member.userId);
      expect(
        () => h.app.reviewService.review(
          entryId: e.entryId,
          action: ReviewAction.approve,
          comment: '',
          adminId: h.member.userId,
        ),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('打回必须填原因，随后可重新提交', () {
      final h = Harness();
      final e = h.draft();
      h.app.entryService.submit(e.entryId, h.member.userId);
      expect(
        () => h.app.reviewService.review(
          entryId: e.entryId,
          action: ReviewAction.reject,
          comment: '  ',
          adminId: h.owner.userId,
        ),
        throwsA(isA<ValidationException>()),
      );
      h.app.reviewService.review(
        entryId: e.entryId,
        action: ReviewAction.reject,
        comment: '请补充发票',
        adminId: h.owner.userId,
      );
      expect(e.status, EntryStatus.rejected);
      h.app.entryService.submit(e.entryId, h.member.userId);
      expect(e.status, EntryStatus.pending);
    });

    test('发生时间超出账本有效期被拒', () {
      final h = Harness();
      expect(
        () => h.draft(occurredAt: DateTime(2027, 5, 1)),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.field,
            'field',
            'occurredAt',
          ),
        ),
      );
    });
  });

  group('重复检测（REQ-012）', () {
    test('同方向同金额同分钟触发证明要求，上传后可提交', () {
      final h = Harness();
      final t = DateTime(2026, 11, 13, 12, 30);
      h.approved(amount: Money.fromYuan(100), occurredAt: t);
      final dup = h.draft(amount: Money.fromYuan(100), occurredAt: t);

      final preview = h.app.entryService.preview(dup.entryId, h.member.userId);
      expect(preview.requiresProof, isTrue);
      expect(preview.canSubmit, isFalse);
      expect(preview.duplicateWarning, isNotEmpty);

      expect(
        () => h.app.entryService.submit(dup.entryId, h.member.userId),
        throwsA(isA<ProofRequiredException>()),
      );

      h.uploadProof(dup.entryId);
      final preview2 = h.app.entryService.preview(dup.entryId, h.member.userId);
      expect(preview2.canSubmit, isTrue);
      h.app.entryService.submit(dup.entryId, h.member.userId);
      expect(dup.status, EntryStatus.pending);
    });

    test('金额不同不触发重复', () {
      final h = Harness();
      final t = DateTime(2026, 11, 13, 12, 30);
      h.approved(amount: Money.fromYuan(100), occurredAt: t);
      final other = h.draft(amount: Money.fromYuan(101), occurredAt: t);
      expect(
        h.app.entryService
            .preview(other.entryId, h.member.userId)
            .requiresProof,
        isFalse,
      );
    });
  });

  group('金额上限（REQ-013，假设 A6）', () {
    test('等于上限不算超限，无需证明', () {
      final h = Harness(amountLimit: Money.fromYuan(200));
      final e = h.draft(amount: Money.fromYuan(200));
      h.app.entryService.submit(e.entryId, h.member.userId);
      expect(e.status, EntryStatus.pending);
      expect(e.strictReview, isFalse);
    });

    test('超过上限标记严格审核且需证明', () {
      final h = Harness(amountLimit: Money.fromYuan(200));
      final e = h.draft(amount: Money.fromYuan(250));
      final preview = h.app.entryService.preview(e.entryId, h.member.userId);
      expect(preview.requiresProof, isTrue);
      expect(preview.strictReviewWarning, isNotEmpty);
      expect(
        () => h.app.entryService.submit(e.entryId, h.member.userId),
        throwsA(isA<ProofRequiredException>()),
      );
      h.uploadProof(e.entryId);
      h.app.entryService.submit(e.entryId, h.member.userId);
      expect(e.strictReview, isTrue);
    });
  });

  group('修改申请（设计决策 D6）', () {
    test('通过后旧条目置无效、生成新的待审核条目', () {
      final h = Harness();
      final old = h.approved(amount: Money.fromYuan(100), title: '原标题');
      final proof = h.uploadProof(old.entryId);
      final req = h.app.reviewService.applyModification(
        entryId: old.entryId,
        applicantId: h.member.userId,
        proposedSnapshot: <String, Object?>{
          'amount': '150.00',
          'title': '改后标题',
        },
        proofAttachmentId: proof.attachmentId,
      );
      expect(old.status, EntryStatus.approved);
      expect(req.isOpen, isTrue);

      final replacement = h.app.reviewService.approveModification(
        requestId: req.requestId,
        adminId: h.owner.userId,
      );
      expect(
        h.app.entryService.requireEntry(old.entryId).status,
        EntryStatus.invalid,
      );
      expect(replacement.status, EntryStatus.pending);
      expect(replacement.replacesEntryId, old.entryId);
      expect(replacement.amount, Money.fromYuan(150));
      expect(replacement.title, '改后标题');

      h.app.reviewService.review(
        entryId: replacement.entryId,
        action: ReviewAction.approve,
        comment: '',
        adminId: h.owner.userId,
      );
      final summary = h.app.statistics.summary(
        h.ledger.ledgerId,
        const EntryQuery(),
      );
      expect(summary.expense, Money.fromYuan(150));
    });

    test('无证明材料不能申请修改已审核条目', () {
      final h = Harness();
      final old = h.approved();
      expect(
        () => h.app.reviewService.applyModification(
          entryId: old.entryId,
          applicantId: h.member.userId,
          proposedSnapshot: <String, Object?>{'title': '新'},
          proofAttachmentId: 0,
        ),
        throwsA(isA<ProofRequiredException>()),
      );
    });

    test('同一条目同时只能有一条进行中的修改申请', () {
      final h = Harness();
      final old = h.approved();
      final proof = h.uploadProof(old.entryId);
      h.app.reviewService.applyModification(
        entryId: old.entryId,
        applicantId: h.member.userId,
        proposedSnapshot: <String, Object?>{'title': '甲'},
        proofAttachmentId: proof.attachmentId,
      );
      expect(
        () => h.app.reviewService.applyModification(
          entryId: old.entryId,
          applicantId: h.member.userId,
          proposedSnapshot: <String, Object?>{'title': '乙'},
          proofAttachmentId: proof.attachmentId,
        ),
        throwsA(isA<ConflictException>()),
      );
    });
  });

  group('作废投票（REQ-010，设计决策 D5）', () {
    test('快照 2 需 2 票，达标后条目置无效', () {
      final h = Harness(extraAdmins: 1);
      final e = h.approved();
      final req = h.app.voidService.initiate(
        entryId: e.entryId,
        reason: '重复报销',
        adminId: h.owner.userId,
      );
      expect(req.adminCountSnapshot, 2);
      expect(req.requiredAgreeCount, 2);

      final p1 = h.app.voidService.vote(
        requestId: req.requestId,
        decision: VoteDecision.agree,
        adminId: h.owner.userId,
      );
      expect(p1.result, VoteResult.voting);
      expect(e.status, EntryStatus.approved);

      final p2 = h.app.voidService.vote(
        requestId: req.requestId,
        decision: VoteDecision.agree,
        adminId: h.admins[0].userId,
      );
      expect(p2.result, VoteResult.passed);
      expect(
        h.app.entryService.requireEntry(e.entryId).status,
        EntryStatus.invalid,
      );
      expect(
        h.app.voidService.historyOf(e.entryId).single.status,
        RequestStatus.approved,
      );
    });

    test('快照 4 时 2 票（恰好半数）不通过，第 3 票才通过', () {
      final h = Harness(extraAdmins: 3);
      final e = h.approved();
      final req = h.app.voidService.initiate(
        entryId: e.entryId,
        reason: '与课程无关',
        adminId: h.owner.userId,
      );
      expect(req.adminCountSnapshot, 4);
      expect(req.requiredAgreeCount, 3);

      h.app.voidService.vote(
        requestId: req.requestId,
        decision: VoteDecision.agree,
        adminId: h.owner.userId,
      );
      final p2 = h.app.voidService.vote(
        requestId: req.requestId,
        decision: VoteDecision.agree,
        adminId: h.admins[0].userId,
      );
      expect(p2.result, VoteResult.voting);
      expect(e.status, EntryStatus.approved);

      final p3 = h.app.voidService.vote(
        requestId: req.requestId,
        decision: VoteDecision.agree,
        adminId: h.admins[1].userId,
      );
      expect(p3.result, VoteResult.passed);
      expect(
        h.app.entryService.requireEntry(e.entryId).status,
        EntryStatus.invalid,
      );
    });

    test('一人一票，重复投票被拒', () {
      final h = Harness(extraAdmins: 1);
      final e = h.approved();
      final req = h.app.voidService.initiate(
        entryId: e.entryId,
        reason: '理由',
        adminId: h.owner.userId,
      );
      h.app.voidService.vote(
        requestId: req.requestId,
        decision: VoteDecision.agree,
        adminId: h.owner.userId,
      );
      expect(
        () => h.app.voidService.vote(
          requestId: req.requestId,
          decision: VoteDecision.agree,
          adminId: h.owner.userId,
        ),
        throwsA(isA<ConflictException>()),
      );
    });

    test('非管理员不能发起或投票', () {
      final h = Harness(extraAdmins: 1);
      final e = h.approved();
      expect(
        () => h.app.voidService.initiate(
          entryId: e.entryId,
          reason: '理由',
          adminId: h.member.userId,
        ),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('注入时钟模拟超时：到期后失效，条目保持已审核', () {
      final h = Harness(extraAdmins: 1);
      final e = h.approved();
      final req = h.app.voidService.initiate(
        entryId: e.entryId,
        reason: '理由',
        adminId: h.owner.userId,
      );
      h.app.voidService.vote(
        requestId: req.requestId,
        decision: VoteDecision.agree,
        adminId: h.owner.userId,
      );

      h.now = h.now.add(const Duration(hours: 73));
      final processed = h.app.voidService.expireDueRequests();
      expect(processed, 1);
      expect(
        h.app.voidService.historyOf(e.entryId).single.status,
        RequestStatus.expired,
      );
      expect(
        h.app.entryService.requireEntry(e.entryId).status,
        EntryStatus.approved,
      );
      expect(
        () => h.app.voidService.vote(
          requestId: req.requestId,
          decision: VoteDecision.agree,
          adminId: h.admins[0].userId,
        ),
        throwsA(isA<ConflictException>()),
      );
    });

    test('超时优先于票数：到期后即便补够票也不通过', () {
      final h = Harness(extraAdmins: 1);
      final e = h.approved();
      final req = h.app.voidService.initiate(
        entryId: e.entryId,
        reason: '理由',
        adminId: h.owner.userId,
      );
      h.app.voidService.vote(
        requestId: req.requestId,
        decision: VoteDecision.agree,
        adminId: h.owner.userId,
      );
      h.now = h.now.add(const Duration(hours: 73));
      expect(
        () => h.app.voidService.vote(
          requestId: req.requestId,
          decision: VoteDecision.agree,
          adminId: h.admins[0].userId,
        ),
        throwsA(isA<ConflictException>()),
      );
      expect(
        h.app.entryService.requireEntry(e.entryId).status,
        EntryStatus.approved,
      );
      expect(
        h.app.voidService.historyOf(e.entryId).single.status,
        RequestStatus.expired,
      );
    });
  });

  group('操作存档哈希链（REQ-011，设计决策 D7）', () {
    test('正常业务链校验通过', () {
      final h = Harness();
      h.approved();
      final v = h.app.audit.verifyChain(h.ledger.ledgerId);
      expect(v.valid, isTrue);
      expect(v.checkedCount, greaterThan(0));
    });

    test('篡改中间一条明细后整链校验失败并定位', () {
      final h = Harness();
      h.approved();
      final chain = h.app.audit.history(h.ledger.ledgerId);
      expect(chain.length, greaterThanOrEqualTo(3));
      final victim = chain[chain.length ~/ 2];
      final tampered = OperationLog(
        logId: victim.logId,
        ledgerId: victim.ledgerId,
        operatorId: victim.operatorId,
        action: victim.action,
        targetType: victim.targetType,
        targetId: victim.targetId,
        detail: <String, Object?>{'tampered': true},
        prevHash: victim.prevHash,
        hash: victim.hash,
        createdAt: victim.createdAt,
      );
      h.app.db.logs[victim.logId] = tampered;
      final v = h.app.audit.verifyChain(h.ledger.ledgerId);
      expect(v.valid, isFalse);
      expect(v.brokenAtLogId, victim.logId);
    });
  });

  group('统计口径（设计决策 D8）', () {
    test('仅已审核条目计入，其余状态一律排除', () {
      final h = Harness();
      h.approved(
        amount: Money.fromYuan(1000),
        direction: EntryDirection.income,
        submitter: h.owner.userId,
      );
      h.approved(amount: Money.fromYuan(300));

      final pending = h.draft(amount: Money.fromYuan(50));
      h.app.entryService.submit(pending.entryId, h.member.userId);

      final rejected = h.draft(amount: Money.fromYuan(80));
      h.app.entryService.submit(rejected.entryId, h.member.userId);
      h.app.reviewService.review(
        entryId: rejected.entryId,
        action: ReviewAction.reject,
        comment: '不符',
        adminId: h.owner.userId,
      );

      h.draft(amount: Money.fromYuan(20)); // 草稿

      final s = h.app.statistics.summary(h.ledger.ledgerId, const EntryQuery());
      expect(s.income, Money.fromYuan(1000));
      expect(s.expense, Money.fromYuan(300));
      expect(s.entryCount, 2);
      expect(s.memberCount, 2);
      expect(s.balance, Money.fromYuan(700));
    });

    test('口径说明明确要求展示且只计已审核', () {
      expect(StatisticsService.caliberNote, contains('已审核'));
    });
  });

  group('成员与权限流转', () {
    test('转让发起者后原发起者保留管理员权限（假设 A8）', () {
      final h = Harness(extraAdmins: 1);
      h.app.ledgerService.transferOwnership(
        h.ledger.ledgerId,
        h.owner.userId,
        h.admins[0].userId,
      );
      final ledger = h.app.ledgerService.requireLedger(h.ledger.ledgerId);
      expect(ledger.ownerId, h.admins[0].userId);
      expect(
        h.app.memberService.isAdmin(h.ledger.ledgerId, h.owner.userId),
        isTrue,
      );
      expect(
        h.app.memberService.isAdmin(h.ledger.ledgerId, h.admins[0].userId),
        isTrue,
      );
    });

    test('发起者不能直接退出，须先转让', () {
      final h = Harness();
      expect(
        () => h.app.ledgerService.leave(h.ledger.ledgerId, h.owner.userId),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('退出后不再计入管理员快照', () {
      final h = Harness(extraAdmins: 2);
      expect(h.app.memberService.adminCount(h.ledger.ledgerId), 3);
      h.app.ledgerService.leave(h.ledger.ledgerId, h.admins[1].userId);
      expect(h.app.memberService.adminCount(h.ledger.ledgerId), 2);
    });
  });
}
