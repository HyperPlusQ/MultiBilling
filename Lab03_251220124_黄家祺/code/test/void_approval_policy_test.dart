import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/domain/enums.dart';
import 'package:multibilling/domain/void_request.dart';
import 'package:multibilling/policy/void_approval_policy.dart';

/// 作废投票策略测试：严格多数边界、快照分母、超时优先于票数。
VoidRequest requestWith(int snapshot, {DateTime? deadline}) {
  final created = DateTime(2026, 11, 13, 10);
  return VoidRequest(
    requestId: 1,
    ledgerId: 1,
    entryId: 1,
    initiatorId: 1,
    reason: '重复报销',
    adminCountSnapshot: snapshot,
    deadline: deadline ?? created.add(VoidRequest.defaultWindow),
    createdAt: created,
  );
}

VoidVote vote(int adminId, bool agree) => VoidVote(
  voteId: adminId,
  requestId: 1,
  adminId: adminId,
  decision: agree ? VoteDecision.agree : VoteDecision.disagree,
  votedAt: DateTime(2026, 11, 13, 11),
);

void main() {
  final policy = VoidApprovalPolicy();
  final now = DateTime(2026, 11, 13, 12);

  group('严格多数判定 agree*2 > snapshot', () {
    test('快照为 0 恒不通过（防除零/空账本）', () {
      expect(VoidRequest.isPassed(0, 0), isFalse);
      expect(VoidRequest.isPassed(5, 0), isFalse);
    });

    test('快照 1：需 1 票', () {
      expect(VoidRequest.isPassed(0, 1), isFalse);
      expect(VoidRequest.isPassed(1, 1), isTrue);
      expect(requestWith(1).requiredAgreeCount, 1);
    });

    test('快照 2：需 2 票，1 票不过', () {
      expect(VoidRequest.isPassed(1, 2), isFalse);
      expect(VoidRequest.isPassed(2, 2), isTrue);
      expect(requestWith(2).requiredAgreeCount, 2);
    });

    test('快照 3：需 2 票（半数以上）', () {
      expect(VoidRequest.isPassed(1, 3), isFalse);
      expect(VoidRequest.isPassed(2, 3), isTrue);
      expect(requestWith(3).requiredAgreeCount, 2);
    });

    test('快照 4：需 3 票，2 票恰好半数不通过（修复初稿 >=0.5 的 bug）', () {
      expect(VoidRequest.isPassed(2, 4), isFalse);
      expect(VoidRequest.isPassed(3, 4), isTrue);
      expect(requestWith(4).requiredAgreeCount, 3);
    });

    test('快照 5：需 3 票', () {
      expect(VoidRequest.isPassed(2, 5), isFalse);
      expect(VoidRequest.isPassed(3, 5), isTrue);
      expect(requestWith(5).requiredAgreeCount, 3);
    });

    test('快照 6：需 4 票，3 票恰好半数不通过', () {
      expect(VoidRequest.isPassed(3, 6), isFalse);
      expect(VoidRequest.isPassed(4, 6), isTrue);
      expect(requestWith(6).requiredAgreeCount, 4);
    });
  });

  group('evaluate 综合评估', () {
    test('票不足且未超时 → 投票中', () {
      final r = requestWith(4);
      expect(policy.evaluate(r, 2, now), VoteResult.voting);
    });

    test('票足够且未超时 → 通过', () {
      final r = requestWith(4);
      expect(policy.evaluate(r, 3, now), VoteResult.passed);
    });

    test('已超时即便票够也判失效（超时优先）', () {
      final r = requestWith(4);
      final afterDeadline = r.deadline.add(const Duration(seconds: 1));
      expect(policy.evaluate(r, 4, afterDeadline), VoteResult.expired);
    });

    test('恰好在截止时刻即失效（闭区间）', () {
      final r = requestWith(4);
      expect(policy.evaluate(r, 4, r.deadline), VoteResult.expired);
    });
  });

  group('提前否决与进度', () {
    test('反对票多到剩余全同意也不够 → doomed', () {
      final r = requestWith(4); // 需 3 票
      expect(policy.isDoomed(r, 2), isTrue); // 剩 2 票，2*2=4 不 > 4
      expect(policy.isDoomed(r, 1), isFalse); // 剩 3 票仍可能通过
    });

    test('votesStillNeeded 不为负', () {
      final r = requestWith(4);
      expect(policy.votesStillNeeded(r, 1), 2);
      expect(policy.votesStillNeeded(r, 3), 0);
      expect(policy.votesStillNeeded(r, 5), 0);
    });

    test('progress 截断到 1.0', () {
      final r = requestWith(4); // 需 3
      expect(policy.progress(r, 0), 0);
      expect(policy.progress(r, 3), 1);
      expect(policy.progress(r, 6), 1);
    });
  });

  group('计票与状态映射', () {
    test('统计同意/反对票', () {
      final votes = [vote(1, true), vote(2, true), vote(3, false)];
      expect(policy.countAgree(votes), 2);
      expect(policy.countDisagree(votes), 1);
    });

    test('评估结果映射到申请状态', () {
      expect(policy.toRequestStatus(VoteResult.passed), RequestStatus.approved);
      expect(policy.toRequestStatus(VoteResult.expired), RequestStatus.expired);
      expect(policy.toRequestStatus(VoteResult.voting), RequestStatus.pending);
    });
  });

  group('VoidRequest 时间窗', () {
    test('默认窗口 72 小时', () {
      final r = requestWith(2);
      expect(r.deadline.difference(r.createdAt), const Duration(hours: 72));
    });

    test('remaining 超时后归零', () {
      final r = requestWith(2);
      expect(r.remaining(r.createdAt).inHours, 72);
      expect(
        r.remaining(r.deadline.add(const Duration(hours: 1))),
        Duration.zero,
      );
    });
  });
}
