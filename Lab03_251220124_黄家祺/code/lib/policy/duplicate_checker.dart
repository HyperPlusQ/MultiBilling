import '../domain/entry.dart';
import '../domain/enums.dart';
import '../repository/repositories.dart';

/// 重复条目检测器，对应类图中的 `DuplicateChecker`（需求 REQ-012）。
///
/// 判定维度为「同账本 + 同方向 + 同金额 + 同发生时间（精确到分钟）」，
/// 这是实验二假设 A2 的落地。命中重复不直接拒绝提交，而是要求补交
/// 证明材料附件，由管理员判断是否确为两笔独立支出。
class DuplicateChecker {
  DuplicateChecker(this._entries);

  final EntryRepository _entries;

  /// 找出与候选条目指纹相同的已有条目。
  ///
  /// 排除候选自身，也排除已无效的条目——被作废的条目不应再阻止新提交。
  List<Entry> findDuplicates(Entry candidate) {
    final matches = _entries.findByFingerprint(
      candidate.ledgerId,
      candidate.duplicateFingerprint,
    );
    return matches
        .where(
          (Entry e) =>
              e.entryId != candidate.entryId && e.status != EntryStatus.invalid,
        )
        .toList();
  }

  /// 是否需要证明材料。
  ///
  /// 只要存在同指纹的有效条目就需要证明。[findDuplicates] 已排除候选自身
  /// 与已无效条目；保存草稿走 createDraft/updateDraft，根本不经过本方法，
  /// 因此连续保存草稿不会被拦。提交与预检都在条目仍是草稿时调用本方法，
  /// 故不能再按「候选是草稿」短路，否则 REQ-012 的证明门槛永远不触发。
  bool requiresProof(Entry candidate) => findDuplicates(candidate).isNotEmpty;

  /// 同指纹的已审核条目数，界面用来提示「已有 N 笔相同记录」。
  int approvedDuplicateCount(Entry candidate) =>
      _entries.countApprovedByFingerprint(
        candidate.ledgerId,
        candidate.duplicateFingerprint,
      );

  /// 生成给用户看的重复提示文案。
  String describe(Entry candidate) {
    final duplicates = findDuplicates(candidate);
    if (duplicates.isEmpty) {
      return '';
    }
    final titles = duplicates.map((Entry e) => e.title).take(3).join('、');
    return '检测到 ${duplicates.length} 笔时间、金额、方向相同的记录'
        '（$titles），请上传证明材料说明这是独立的一笔。';
  }
}
