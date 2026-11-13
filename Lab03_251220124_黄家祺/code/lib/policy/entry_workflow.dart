import '../domain/domain_exception.dart';
import '../domain/entry.dart';
import '../domain/enums.dart';

/// 条目状态机，对应类图中的 `EntryWorkflow`（设计决策 D3）。
///
/// 所有状态迁移必须经过这里，非法迁移直接抛异常。把规则收在一处，
/// 避免各个服务里散落 `if (status == ...)` 导致漏判。
class EntryWorkflow {
  /// 无状态，允许 const 实例，服务层共享一个即可。
  const EntryWorkflow();

  /// 合法迁移表：key 为当前状态，value 为允许到达的状态集合。
  ///
  /// 注意 `APPROVED` 不能直接回到 `PENDING`——已审核条目的修改必须走
  /// 修改申请流程，由旧条目置无效 + 新条目重新审核来完成。
  static const Map<EntryStatus, Set<EntryStatus>> _allowed =
      <EntryStatus, Set<EntryStatus>>{
        EntryStatus.draft: <EntryStatus>{EntryStatus.pending},
        EntryStatus.pending: <EntryStatus>{
          EntryStatus.approved,
          EntryStatus.rejected,
          EntryStatus.invalid,
        },
        EntryStatus.approved: <EntryStatus>{EntryStatus.invalid},
        EntryStatus.rejected: <EntryStatus>{
          EntryStatus.pending,
          EntryStatus.invalid,
        },
        EntryStatus.invalid: <EntryStatus>{},
      };

  /// 判断从 [from] 到 [to] 是否合法。
  static bool isAllowed(EntryStatus from, EntryStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  /// 断言迁移合法，否则抛 [IllegalTransitionException]。
  static void assertAllowed(EntryStatus from, EntryStatus to) {
    if (!isAllowed(from, to)) {
      throw IllegalTransitionException(from, to);
    }
  }

  /// 列出某状态允许到达的全部状态，界面用来决定按钮是否可用。
  static Set<EntryStatus> reachableFrom(EntryStatus from) =>
      _allowed[from] ?? const <EntryStatus>{};

  /// 执行提交：草稿 → 待审核。
  void submit(Entry entry) {
    assertAllowed(entry.status, EntryStatus.pending);
    entry.markSubmitted();
  }

  /// 执行重新提交：被驳回 → 待审核。
  void resubmit(Entry entry) {
    assertAllowed(entry.status, EntryStatus.pending);
    entry.resubmit();
  }

  /// 执行审核动作。要求补充不改变状态，只打标记。
  void review(Entry entry, ReviewAction action, int reviewerId) {
    final target = action.targetStatus;
    if (target == null) {
      if (entry.status != EntryStatus.pending) {
        throw IllegalTransitionException(entry.status, entry.status);
      }
      entry.markSupplementRequested(reviewerId);
      return;
    }
    assertAllowed(entry.status, target);
    switch (action) {
      case ReviewAction.approve:
        entry.markApproved(reviewerId);
      case ReviewAction.reject:
        entry.markRejected(reviewerId);
      case ReviewAction.requestSupplement:
        entry.markSupplementRequested(reviewerId);
    }
  }

  /// 执行置为无效。这是终态，之后不能再迁移。
  void invalidate(Entry entry, String reason) {
    assertAllowed(entry.status, EntryStatus.invalid);
    entry.markInvalid(reason);
  }
}
