import '../domain/attachment.dart';
import '../domain/category.dart';
import '../domain/entry.dart';
import '../domain/enums.dart';
import '../domain/ledger.dart';
import '../domain/ledger_member.dart';
import '../domain/local_date.dart';
import '../domain/modification_request.dart';
import '../domain/money.dart';
import '../domain/operation_log.dart';
import '../domain/review_record.dart';
import '../domain/user.dart';
import '../domain/void_request.dart';

/// 分页结果。
class Page<T> {
  const Page({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  /// 当前页数据。
  final List<T> items;

  /// 满足条件的总条数。
  final int total;

  /// 页码，从 1 开始。
  final int page;

  /// 每页条数。
  final int pageSize;

  /// 总页数。
  int get pageCount => pageSize == 0 ? 0 : (total / pageSize).ceil();

  /// 是否还有下一页。
  bool get hasNext => page < pageCount;
}

/// 条目检索条件，对应实验二的五维组合筛选。
///
/// 所有字段都是可选的，为空表示该维度不参与过滤。
class EntryQuery {
  const EntryQuery({
    this.keyword,
    this.categoryId,
    this.submitterId,
    this.status,
    this.direction,
    this.from,
    this.to,
    this.minAmount,
    this.maxAmount,
    this.page = 1,
    this.pageSize = 20,
    this.includeDraftOf,
  });

  /// 标题与事由的关键字。
  final String? keyword;

  /// 类别过滤。
  final int? categoryId;

  /// 提交人过滤。
  final int? submitterId;

  /// 状态过滤，对应四个板块的 Tab。
  final EntryStatus? status;

  /// 收支方向过滤。
  final EntryDirection? direction;

  /// 发生时间下界（含）。
  final LocalDate? from;

  /// 发生时间上界（含）。
  final LocalDate? to;

  /// 金额下界（含）。
  final Money? minAmount;

  /// 金额上界（含）。
  final Money? maxAmount;

  /// 页码。
  final int page;

  /// 每页条数。
  final int pageSize;

  /// 允许看到该用户草稿的用户 id；草稿对其他人不可见。
  final int? includeDraftOf;

  /// 判断一条条目是否满足全部条件。
  bool matches(Entry entry) {
    if (entry.status == EntryStatus.draft &&
        entry.submitterId != includeDraftOf) {
      return false;
    }
    if (status != null && entry.status != status) {
      return false;
    }
    if (direction != null && entry.direction != direction) {
      return false;
    }
    if (categoryId != null && entry.categoryId != categoryId) {
      return false;
    }
    if (submitterId != null && entry.submitterId != submitterId) {
      return false;
    }
    if (keyword != null && keyword!.trim().isNotEmpty) {
      final needle = keyword!.trim().toLowerCase();
      final haystack = '${entry.title} ${entry.reason}'.toLowerCase();
      if (!haystack.contains(needle)) {
        return false;
      }
    }
    final date = entry.occurredDate;
    if (from != null && date.compareTo(from!) < 0) {
      return false;
    }
    if (to != null && date.compareTo(to!) > 0) {
      return false;
    }
    if (minAmount != null && entry.amount < minAmount!) {
      return false;
    }
    if (maxAmount != null && entry.amount > maxAmount!) {
      return false;
    }
    return true;
  }

  /// 复制并覆盖部分条件，界面切换 Tab 时用。
  EntryQuery copyWith({
    String? keyword,
    int? categoryId,
    int? submitterId,
    EntryStatus? status,
    EntryDirection? direction,
    LocalDate? from,
    LocalDate? to,
    Money? minAmount,
    Money? maxAmount,
    int? page,
    int? pageSize,
    int? includeDraftOf,
    bool clearStatus = false,
    bool clearCategory = false,
    bool clearSubmitter = false,
    bool clearDirection = false,
    bool clearRange = false,
    bool clearKeyword = false,
  }) => EntryQuery(
    keyword: clearKeyword ? null : (keyword ?? this.keyword),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    submitterId: clearSubmitter ? null : (submitterId ?? this.submitterId),
    status: clearStatus ? null : (status ?? this.status),
    direction: clearDirection ? null : (direction ?? this.direction),
    from: clearRange ? null : (from ?? this.from),
    to: clearRange ? null : (to ?? this.to),
    minAmount: clearRange ? null : (minAmount ?? this.minAmount),
    maxAmount: clearRange ? null : (maxAmount ?? this.maxAmount),
    page: page ?? this.page,
    pageSize: pageSize ?? this.pageSize,
    includeDraftOf: includeDraftOf ?? this.includeDraftOf,
  );
}

/// 用户仓储。
abstract interface class UserRepository {
  /// 按主键查找。
  User? findById(int userId);

  /// 按登录名查找。
  User? findByUsername(String username);

  /// 保存（新增或更新）。
  User save(User user);

  /// 全部用户。
  List<User> all();
}

/// 账本仓储。
abstract interface class LedgerRepository {
  /// 按主键查找。
  Ledger? findById(int ledgerId);

  /// 按邀请码查找。
  Ledger? findByInviteCode(String code);

  /// 保存。
  Ledger save(Ledger ledger);

  /// 全部账本。
  List<Ledger> all();

  /// 某账本的全部成员（含已退出）。
  List<LedgerMember> findMembers(int ledgerId);

  /// 某用户在某账本中的成员记录。
  LedgerMember? findMember(int ledgerId, int userId);

  /// 保存成员记录。
  LedgerMember saveMember(LedgerMember member);

  /// 某用户参与的全部账本 id。
  List<int> findLedgerIdsOfUser(int userId);
}

/// 类别仓储。
abstract interface class CategoryRepository {
  /// 按主键查找。
  Category? findById(int categoryId);

  /// 某账本的全部类别。
  List<Category> byLedger(int ledgerId);

  /// 保存。
  Category save(Category category);
}

/// 条目仓储。
abstract interface class EntryRepository {
  /// 按主键查找。
  Entry? findById(int entryId);

  /// 保存。
  Entry save(Entry entry);

  /// 按条件分页检索。
  Page<Entry> search(int ledgerId, EntryQuery query);

  /// 某账本的全部条目，统计与重复检测用。
  List<Entry> byLedger(int ledgerId);

  /// 按重复指纹查找已存在的条目。
  List<Entry> findByFingerprint(int ledgerId, String fingerprint);

  /// 统计同指纹的已审核条目数。
  int countApprovedByFingerprint(int ledgerId, String fingerprint);

  /// 统计专用出口：在仓储层固定追加 `status = APPROVED` 条件。
  ///
  /// 设计决策 D8。统计服务只能调这个方法，拿不到其他状态的条目，
  /// 从结构上杜绝「某个报表忘了加状态过滤」这类遗漏。
  List<Entry> approvedForStatistics(int ledgerId);
}

/// 附件仓储。
abstract interface class AttachmentRepository {
  /// 按主键查找。
  Attachment? findById(int attachmentId);

  /// 某条目的全部附件。
  List<Attachment> byEntry(int entryId);

  /// 某条目是否存在指定用途的附件。
  bool hasPurpose(int entryId, AttachmentPurpose purpose);

  /// 保存。
  Attachment save(Attachment attachment);
}

/// 审核记录仓储。
abstract interface class ReviewRecordRepository {
  /// 某条目的审核时间线，按时间升序。
  List<ReviewRecord> byEntry(int entryId);

  /// 保存。
  ReviewRecord save(ReviewRecord record);
}

/// 修改申请仓储。
abstract interface class ModificationRequestRepository {
  /// 按主键查找。
  ModificationRequest? findById(int requestId);

  /// 某条目当前进行中的申请，最多一条。
  ModificationRequest? findOpenByEntry(int entryId);

  /// 某账本的全部申请。
  List<ModificationRequest> byLedger(int ledgerId);

  /// 保存。
  ModificationRequest save(ModificationRequest request);
}

/// 作废申请仓储。
abstract interface class VoidRequestRepository {
  /// 按主键查找。
  VoidRequest? findById(int requestId);

  /// 某账本进行中的申请。
  List<VoidRequest> findPendingByLedger(int ledgerId);

  /// 全部进行中的申请，超时扫描用。
  List<VoidRequest> findAllPending();

  /// 某条目的申请历史。
  List<VoidRequest> byEntry(int entryId);

  /// 保存。
  VoidRequest save(VoidRequest request);
}

/// 作废投票仓储。
abstract interface class VoidVoteRepository {
  /// 某申请的全部投票。
  List<VoidVote> byRequest(int requestId);

  /// 某管理员是否已对某申请投过票。
  bool hasVoted(int requestId, int adminId);

  /// 保存。
  VoidVote save(VoidVote vote);
}

/// 操作存档仓储。
///
/// 刻意不提供 update / delete：存档只能追加与读取。
abstract interface class OperationLogRepository {
  /// 追加一条记录。
  OperationLog append(OperationLog log);

  /// 某账本最后一条记录的哈希，链首返回 genesis。
  String lastHash(int ledgerId);

  /// 某账本的全部存档，按 logId 升序。
  List<OperationLog> byLedger(int ledgerId);
}
