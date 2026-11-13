import '../domain/attachment.dart';
import '../domain/category.dart';
import '../domain/entry.dart';
import '../domain/ledger.dart';
import '../domain/ledger_member.dart';
import '../domain/modification_request.dart';
import '../domain/operation_log.dart';
import '../domain/review_record.dart';
import '../domain/user.dart';
import '../domain/void_request.dart';

/// 进程内数据存储。
///
/// 实验二设计用 MySQL + Redis + MinIO 三套外部服务；桌面单机版没有
/// 这些依赖，改为「内存表 + 启动时从 JSON 载入 + 变更后落盘」。
/// 仓储接口保持不变，因此日后要换回数据库只需替换实现类。
///
/// 单元测试直接构造本类，不触碰文件系统。
class MemoryDatabase {
  /// 用户表，key 为 userId。
  final Map<int, User> users = <int, User>{};

  /// 账本表。
  final Map<int, Ledger> ledgers = <int, Ledger>{};

  /// 成员表。
  final Map<int, LedgerMember> members = <int, LedgerMember>{};

  /// 类别表。
  final Map<int, Category> categories = <int, Category>{};

  /// 条目表。
  final Map<int, Entry> entries = <int, Entry>{};

  /// 附件表。
  final Map<int, Attachment> attachments = <int, Attachment>{};

  /// 审核记录表。
  final Map<int, ReviewRecord> reviews = <int, ReviewRecord>{};

  /// 修改申请表。
  final Map<int, ModificationRequest> modifications =
      <int, ModificationRequest>{};

  /// 作废申请表。
  final Map<int, VoidRequest> voidRequests = <int, VoidRequest>{};

  /// 作废投票表。
  final Map<int, VoidVote> voidVotes = <int, VoidVote>{};

  /// 操作存档表。
  final Map<int, OperationLog> logs = <int, OperationLog>{};

  final Map<String, int> _sequences = <String, int>{};

  /// 为某类实体分配下一个主键。
  int nextId(String entity) {
    final next = (_sequences[entity] ?? 0) + 1;
    _sequences[entity] = next;
    return next;
  }

  /// 读取某类实体当前已分配到的最大主键，载入存档后用于对齐序列。
  int currentId(String entity) => _sequences[entity] ?? 0;

  /// 把序列推进到不小于 [value]，避免载入后主键回退造成覆盖。
  void bumpSequence(String entity, int value) {
    if (value > (_sequences[entity] ?? 0)) {
      _sequences[entity] = value;
    }
  }

  /// 清空全部数据，测试与「重置演示数据」用。
  void clear() {
    users.clear();
    ledgers.clear();
    members.clear();
    categories.clear();
    entries.clear();
    attachments.clear();
    reviews.clear();
    modifications.clear();
    voidRequests.clear();
    voidVotes.clear();
    logs.clear();
    _sequences.clear();
  }

  /// 各表记录数，界面「关于」页与测试断言用。
  Map<String, int> get counts => <String, int>{
    'users': users.length,
    'ledgers': ledgers.length,
    'members': members.length,
    'categories': categories.length,
    'entries': entries.length,
    'attachments': attachments.length,
    'reviews': reviews.length,
    'modifications': modifications.length,
    'voidRequests': voidRequests.length,
    'voidVotes': voidVotes.length,
    'logs': logs.length,
  };
}
