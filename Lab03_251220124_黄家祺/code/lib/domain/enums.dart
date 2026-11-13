/// 领域枚举定义，对应实验二 UML 类图中的 8 个业务枚举。
library;

/// 收支条目状态。四个业务板块（未审核/已审核/已驳回/无效）是本枚举的投影，
/// 而非四张独立数据表；`DRAFT` 仅提交人可见，不进入任何板块。
enum EntryStatus {
  draft('草稿'),
  pending('未审核'),
  approved('已审核'),
  rejected('已驳回'),
  invalid('无效');

  const EntryStatus(this.label);

  /// 界面展示用的中文名称。
  final String label;

  /// 该状态是否属于四个业务板块之一。
  bool get inBoard => this != EntryStatus.draft;

  /// 提交人是否可以直接编辑该状态的条目。
  bool get editableBySubmitter =>
      this == EntryStatus.draft || this == EntryStatus.rejected;

  /// 是否为不再变化的终态。
  bool get isTerminal => this == EntryStatus.invalid;
}

/// 成员身份，表达"谁创建了这个账本"。与 [MemberRole] 正交，避免角色组合爆炸。
enum MemberIdentity {
  owner('发起者'),
  participant('参与者');

  const MemberIdentity(this.label);

  /// 界面展示用的中文名称。
  final String label;
}

/// 成员权限，表达"能不能审核"。发起者天然持有 [MemberRole.admin] 且不可被降级。
enum MemberRole {
  admin('管理员'),
  member('成员');

  const MemberRole(this.label);

  /// 界面展示用的中文名称。
  final String label;
}

/// 收支方向。
enum EntryDirection {
  income('收入'),
  expense('支出');

  const EntryDirection(this.label);

  /// 界面展示用的中文名称。
  final String label;

  /// 统计时的符号：收入为正、支出为负。
  int get sign => this == EntryDirection.income ? 1 : -1;
}

/// 修改申请与作废申请共用的流转状态。
enum RequestStatus {
  pending('待处理'),
  approved('已通过'),
  rejected('已驳回'),
  expired('已超时');

  const RequestStatus(this.label);

  /// 界面展示用的中文名称。
  final String label;

  /// 是否仍在流转中。
  bool get isOpen => this == RequestStatus.pending;
}

/// 附件用途。重复条目与已审核条目的修改必须有 `PROOF`，普通票据用 `GENERAL`。
enum AttachmentPurpose {
  general('普通票据'),
  proof('证明材料'),
  supplement('补充材料');

  const AttachmentPurpose(this.label);

  /// 界面展示用的中文名称。
  final String label;
}

/// 管理员审核动作。
enum ReviewAction {
  approve('通过'),
  reject('打回'),
  requestSupplement('要求补充');

  const ReviewAction(this.label);

  /// 界面展示用的中文名称。
  final String label;

  /// 打回必须填写原因。
  bool get requiresComment => this != ReviewAction.approve;

  /// 该动作对应的目标状态；要求补充不改变状态，返回 null。
  EntryStatus? get targetStatus {
    switch (this) {
      case ReviewAction.approve:
        return EntryStatus.approved;
      case ReviewAction.reject:
        return EntryStatus.rejected;
      case ReviewAction.requestSupplement:
        return null;
    }
  }
}

/// 作废投票决定。
enum VoteDecision {
  agree('同意作废'),
  disagree('不同意');

  const VoteDecision(this.label);

  /// 界面展示用的中文名称。
  final String label;
}

/// 账号状态。实验二的类图未单列该枚举，实现时补齐。
enum UserStatus {
  active('正常'),
  disabled('已停用');

  const UserStatus(this.label);

  /// 界面展示用的中文名称。
  final String label;
}

/// 账本状态。过期账本转为只读。
enum LedgerStatus {
  active('进行中'),
  readOnly('只读'),
  archived('已归档');

  const LedgerStatus(this.label);

  /// 界面展示用的中文名称。
  final String label;
}

/// 领域错误类别，供界面层映射成可读提示。
enum DomainErrorKind {
  forbidden('无权操作'),
  illegalTransition('状态不允许'),
  validation('字段校验失败'),
  notFound('对象不存在'),
  conflict('并发或唯一性冲突'),
  proofRequired('缺少证明材料');

  const DomainErrorKind(this.label);

  /// 界面展示用的中文名称。
  final String label;
}
