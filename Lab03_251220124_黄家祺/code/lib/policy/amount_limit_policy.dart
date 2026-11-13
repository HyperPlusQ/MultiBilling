import '../domain/ledger.dart';
import '../domain/money.dart';

/// 金额限制策略，对应类图中的 `AmountLimitPolicy`（需求 REQ-013）。
///
/// 发起者为账本设置单笔上限，超过上限的条目不拒绝提交，而是标记
/// `strictReview`，在审核界面高亮提示管理员重点核对。
class AmountLimitPolicy {
  /// 是否需要严格审核。
  ///
  /// 边界按实验二假设 A6：金额**等于**上限不算超限，严格大于才算。
  /// 上限为零表示未设置限制。
  bool requiresStrictReview(Ledger ledger, Money amount) {
    if (ledger.amountLimit.cents == 0) {
      return false;
    }
    return amount > ledger.amountLimit;
  }

  /// 需要的证明材料份数。
  ///
  /// 超限条目要求至少一份证明；未超限为零。保留成方法而不是常量，
  /// 是为了让「按超限倍数递增份数」这类后续规则有统一的落点。
  int requiredProofCount(Ledger ledger, Money amount) =>
      requiresStrictReview(ledger, amount) ? 1 : 0;

  /// 超出上限的金额，未超限返回零。
  Money excess(Ledger ledger, Money amount) {
    if (!requiresStrictReview(ledger, amount)) {
      return Money.zero;
    }
    return amount - ledger.amountLimit;
  }

  /// 生成审核界面的提示文案。
  String describe(Ledger ledger, Money amount) {
    if (!requiresStrictReview(ledger, amount)) {
      return '';
    }
    return '本笔 ${amount.formatted} 元超过账本单笔上限 '
        '${ledger.amountLimit.formatted} 元，已标记严格审核，'
        '超出 ${excess(ledger, amount).formatted} 元。';
  }
}
