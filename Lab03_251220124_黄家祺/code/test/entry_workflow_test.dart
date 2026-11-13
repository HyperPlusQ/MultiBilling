import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/domain/domain_exception.dart';
import 'package:multibilling/domain/entry.dart';
import 'package:multibilling/domain/enums.dart';
import 'package:multibilling/domain/money.dart';
import 'package:multibilling/policy/entry_workflow.dart';

/// 状态机测试：穷举合法/非法迁移，验证「已审核不能直接回退」等关键约束。
Entry entryWith(EntryStatus status) => Entry(
  entryId: 1,
  ledgerId: 1,
  submitterId: 1,
  categoryId: 1,
  title: '测试条目',
  direction: EntryDirection.expense,
  amount: Money.fromYuan(100),
  occurredAt: DateTime(2026, 11, 13, 10),
  reason: '事由',
  status: status,
  createdAt: DateTime(2026, 11, 13),
);

void main() {
  const workflow = EntryWorkflow();

  group('迁移表', () {
    test('草稿只能到待审核', () {
      expect(EntryWorkflow.reachableFrom(EntryStatus.draft), {
        EntryStatus.pending,
      });
    });

    test('待审核可到通过/驳回/无效', () {
      expect(EntryWorkflow.reachableFrom(EntryStatus.pending), {
        EntryStatus.approved,
        EntryStatus.rejected,
        EntryStatus.invalid,
      });
    });

    test('已审核只能置无效，不能直接回待审核', () {
      expect(EntryWorkflow.reachableFrom(EntryStatus.approved), {
        EntryStatus.invalid,
      });
      expect(
        EntryWorkflow.isAllowed(EntryStatus.approved, EntryStatus.pending),
        isFalse,
      );
    });

    test('已驳回可重新提交或置无效', () {
      expect(EntryWorkflow.reachableFrom(EntryStatus.rejected), {
        EntryStatus.pending,
        EntryStatus.invalid,
      });
    });

    test('无效是终态，无任何后继', () {
      expect(EntryWorkflow.reachableFrom(EntryStatus.invalid), isEmpty);
    });

    test('穷举所有状态对，与迁移表一致', () {
      const expected = <EntryStatus, Set<EntryStatus>>{
        EntryStatus.draft: {EntryStatus.pending},
        EntryStatus.pending: {
          EntryStatus.approved,
          EntryStatus.rejected,
          EntryStatus.invalid,
        },
        EntryStatus.approved: {EntryStatus.invalid},
        EntryStatus.rejected: {EntryStatus.pending, EntryStatus.invalid},
        EntryStatus.invalid: <EntryStatus>{},
      };
      for (final from in EntryStatus.values) {
        for (final to in EntryStatus.values) {
          expect(
            EntryWorkflow.isAllowed(from, to),
            expected[from]!.contains(to),
            reason: '$from -> $to',
          );
        }
      }
    });
  });

  group('执行迁移', () {
    test('submit：草稿 → 待审核，版本递增', () {
      final e = entryWith(EntryStatus.draft);
      workflow.submit(e);
      expect(e.status, EntryStatus.pending);
      expect(e.version, 1);
    });

    test('submit 非草稿抛非法迁移', () {
      final e = entryWith(EntryStatus.approved);
      expect(
        () => workflow.submit(e),
        throwsA(isA<IllegalTransitionException>()),
      );
    });

    test('review approve：待审核 → 已审核，记录审核人', () {
      final e = entryWith(EntryStatus.pending);
      workflow.review(e, ReviewAction.approve, 42);
      expect(e.status, EntryStatus.approved);
      expect(e.lastReviewerId, 42);
    });

    test('review reject：待审核 → 已驳回', () {
      final e = entryWith(EntryStatus.pending);
      workflow.review(e, ReviewAction.reject, 42);
      expect(e.status, EntryStatus.rejected);
    });

    test('review 要求补充：状态不变，仅打标记', () {
      final e = entryWith(EntryStatus.pending);
      workflow.review(e, ReviewAction.requestSupplement, 42);
      expect(e.status, EntryStatus.pending);
      expect(e.supplementRequested, isTrue);
      expect(e.lastReviewerId, 42);
    });

    test('对已审核条目要求补充抛非法迁移', () {
      final e = entryWith(EntryStatus.approved);
      expect(
        () => workflow.review(e, ReviewAction.requestSupplement, 42),
        throwsA(isA<IllegalTransitionException>()),
      );
    });

    test('resubmit：已驳回 → 待审核', () {
      final e = entryWith(EntryStatus.rejected);
      workflow.resubmit(e);
      expect(e.status, EntryStatus.pending);
    });

    test('invalidate 后不能再迁移', () {
      final e = entryWith(EntryStatus.approved);
      workflow.invalidate(e, '重复报销');
      expect(e.status, EntryStatus.invalid);
      expect(e.invalidReason, '重复报销');
      expect(
        () => workflow.submit(e),
        throwsA(isA<IllegalTransitionException>()),
      );
      expect(
        () => workflow.invalidate(e, '再次'),
        throwsA(isA<IllegalTransitionException>()),
      );
    });

    test('invalidate 必须给原因', () {
      final e = entryWith(EntryStatus.pending);
      expect(
        () => workflow.invalidate(e, '  '),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
