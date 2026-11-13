import '../domain/enums.dart';
import '../domain/void_request.dart';

/// 作废投票策略，对应类图中的 `VoidApprovalPolicy`（需求 REQ-010）。
///
/// 三条规则：
/// 1. 分母用创建申请时快照的管理员总数，不用实时人数（D5）；
/// 2. 通过条件是严格多数 `agree * 2 > snapshot`，不是「大于等于半数」；
/// 3. 超过截止时间一律失效，不再计票。
///
/// 大模型初稿给的是 `agree / admin >= 0.5`，在 4 名管理员时 2 票即通过，
/// 与需求「半数以上」不符；这里改成严格大于，并补了快照与超时两条边界。
class VoidApprovalPolicy {
  /// 综合评估当前申请应处于什么结果。
  ///
  /// 先判超时再判票数：即使票数已够，只要过了截止时间也按失效处理，
  /// 避免出现「过期后才补票通过」这种不可解释的历史。
  VoteResult evaluate(VoidRequest request, int agreeCount, DateTime now) {
    if (request.isExpiredAt(now)) {
      return VoteResult.expired;
    }
    if (isPassed(agreeCount, request.adminCountSnapshot)) {
      return VoteResult.passed;
    }
    return VoteResult.voting;
  }

  /// 严格多数判定。快照为零时恒不通过，防止除零与空账本误判。
  bool isPassed(int agree, int adminSnapshot) =>
      VoidRequest.isPassed(agree, adminSnapshot);

  /// 是否已经不可能再通过：反对票多到剩余票全同意也不够。
  ///
  /// 用于提前结束投票，避免管理员明知无望还要等满 72 小时。
  bool isDoomed(VoidRequest request, int disagreeCount) {
    final remaining = request.adminCountSnapshot - disagreeCount;
    return !isPassed(remaining, request.adminCountSnapshot);
  }

  /// 还差几票通过，界面画进度条用。
  int votesStillNeeded(VoidRequest request, int agreeCount) {
    final needed = request.requiredAgreeCount - agreeCount;
    return needed < 0 ? 0 : needed;
  }

  /// 投票进度，0.0 到 1.0。
  double progress(VoidRequest request, int agreeCount) {
    final required = request.requiredAgreeCount;
    if (required <= 0) {
      return 0;
    }
    final ratio = agreeCount / required;
    return ratio > 1 ? 1 : ratio;
  }

  /// 统计同意票数。
  int countAgree(List<VoidVote> votes) =>
      votes.where((VoidVote v) => v.isAgree).length;

  /// 统计反对票数。
  int countDisagree(List<VoidVote> votes) =>
      votes.where((VoidVote v) => !v.isAgree).length;

  /// 生成投票面板的说明文案。
  String describe(VoidRequest request, List<VoidVote> votes) {
    final agree = countAgree(votes);
    final needed = request.requiredAgreeCount;
    return '需 $needed 票同意（发起时共 ${request.adminCountSnapshot} 名管理员），'
        '当前 $agree 票同意、${countDisagree(votes)} 票反对。';
  }

  /// 把评估结果映射到申请的流转状态。
  RequestStatus toRequestStatus(VoteResult result) {
    switch (result) {
      case VoteResult.passed:
        return RequestStatus.approved;
      case VoteResult.expired:
        return RequestStatus.expired;
      case VoteResult.voting:
        return RequestStatus.pending;
    }
  }
}
