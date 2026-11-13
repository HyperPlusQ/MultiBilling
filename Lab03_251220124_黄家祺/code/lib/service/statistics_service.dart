import '../domain/category.dart';
import '../domain/entry.dart';
import '../domain/enums.dart';
import '../domain/local_date.dart';
import '../domain/money.dart';
import '../repository/repositories.dart';
import 'auth_service.dart';

/// 总览指标。
class SummaryVO {
  const SummaryVO({
    required this.income,
    required this.expense,
    required this.entryCount,
    required this.memberCount,
  });

  /// 已审核收入合计。
  final Money income;

  /// 已审核支出合计。
  final Money expense;

  /// 参与统计的条目数。
  final int entryCount;

  /// 有已审核条目的成员数。
  final int memberCount;

  /// 结余 = 收入 - 支出。
  Money get balance => income - expense;
}

/// 分组统计的一行。
class StatVO {
  const StatVO({
    required this.label,
    required this.income,
    required this.expense,
    required this.count,
    this.color,
  });

  /// 分组名。
  final String label;

  /// 该组收入。
  final Money income;

  /// 该组支出。
  final Money expense;

  /// 该组条目数。
  final int count;

  /// 图表配色。
  final String? color;

  /// 净额。
  Money get net => income - expense;

  /// 收支绝对值之和，用于计算占比分母。
  Money get volume => income + expense;
}

/// 趋势图上的一个点。
class PointVO {
  const PointVO({
    required this.label,
    required this.income,
    required this.expense,
  });

  /// 横轴标签。
  final String label;

  /// 该期收入。
  final Money income;

  /// 该期支出。
  final Money expense;

  /// 该期净额。
  Money get net => income - expense;
}

/// 统计服务，对应类图中的 `StatisticsService`（需求 REQ-005、REQ-007）。
///
/// 所有方法都通过 [EntryRepository.approvedForStatistics] 取数，
/// 该方法在仓储层固定追加 `status = APPROVED`。统计服务拿不到其他状态
/// 的条目，因此不可能出现「某个报表忘了过滤状态」的遗漏（设计决策 D8）。
class StatisticsService {
  StatisticsService({
    required EntryRepository entries,
    required CategoryRepository categories,
    required AuthService auth,
  }) : _entries = entries,
       _categories = categories,
       _auth = auth;

  final EntryRepository _entries;
  final CategoryRepository _categories;
  final AuthService _auth;

  /// 报表口径说明，界面必须展示在标题下方。
  static const String caliberNote =
      '统计口径：仅计入「已审核」条目，'
      '草稿、未审核、已驳回与无效条目均不参与计算。';

  /// 按筛选条件取已审核条目。
  List<Entry> _approved(int ledgerId, EntryQuery filter) => _entries
      .approvedForStatistics(ledgerId)
      .where((Entry e) => filter.matches(e))
      .toList();

  /// 总览指标。
  SummaryVO summary(int ledgerId, EntryQuery filter) {
    final rows = _approved(ledgerId, filter);
    var income = Money.zero;
    var expense = Money.zero;
    final members = <int>{};
    for (final entry in rows) {
      if (entry.direction == EntryDirection.income) {
        income = income + entry.amount;
      } else {
        expense = expense + entry.amount;
      }
      members.add(entry.submitterId);
    }
    return SummaryVO(
      income: income,
      expense: expense,
      entryCount: rows.length,
      memberCount: members.length,
    );
  }

  /// 按类别分组。
  List<StatVO> byCategory(int ledgerId, EntryQuery filter) {
    final rows = _approved(ledgerId, filter);
    final categories = <int, Category>{
      for (final c in _categories.byLedger(ledgerId)) c.categoryId: c,
    };
    final grouped = <int, List<Entry>>{};
    for (final entry in rows) {
      grouped.putIfAbsent(entry.categoryId, () => <Entry>[]).add(entry);
    }
    final result = grouped.entries.map((MapEntry<int, List<Entry>> g) {
      final category = categories[g.key];
      return StatVO(
        label: category?.name ?? '类别 ${g.key}',
        income: _sum(g.value, EntryDirection.income),
        expense: _sum(g.value, EntryDirection.expense),
        count: g.value.length,
        color: category?.color,
      );
    }).toList()..sort((StatVO a, StatVO b) => b.volume.compareTo(a.volume));
    return result;
  }

  /// 按成员分组。
  List<StatVO> byMember(int ledgerId, EntryQuery filter) {
    final rows = _approved(ledgerId, filter);
    final grouped = <int, List<Entry>>{};
    for (final entry in rows) {
      grouped.putIfAbsent(entry.submitterId, () => <Entry>[]).add(entry);
    }
    final result = grouped.entries.map((MapEntry<int, List<Entry>> g) {
      return StatVO(
        label: _auth.displayNameOf(g.key),
        income: _sum(g.value, EntryDirection.income),
        expense: _sum(g.value, EntryDirection.expense),
        count: g.value.length,
      );
    }).toList()..sort((StatVO a, StatVO b) => b.volume.compareTo(a.volume));
    return result;
  }

  /// 按月趋势。
  List<PointVO> trend(int ledgerId, EntryQuery filter) {
    final rows = _approved(ledgerId, filter);
    final grouped = <String, List<Entry>>{};
    for (final entry in rows) {
      final key =
          '${entry.occurredAt.year}-'
          '${entry.occurredAt.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => <Entry>[]).add(entry);
    }
    final keys = grouped.keys.toList()..sort();
    return keys.map((String key) {
      final parts = key.split('-');
      final label = LocalDate(
        int.parse(parts[0]),
        int.parse(parts[1]),
        1,
      ).toMonthLabel();
      return PointVO(
        label: label,
        income: _sum(grouped[key]!, EntryDirection.income),
        expense: _sum(grouped[key]!, EntryDirection.expense),
      );
    }).toList();
  }

  /// 按金额区间分组，用于金额分布图。
  List<StatVO> byAmountBand(int ledgerId, EntryQuery filter) {
    final rows = _approved(ledgerId, filter);
    final bands = <(String, Money, Money)>[
      ('0 ~ 100', Money.zero, Money.fromYuan(100)),
      ('100 ~ 500', Money.fromYuan(100), Money.fromYuan(500)),
      ('500 ~ 1000', Money.fromYuan(500), Money.fromYuan(1000)),
      ('1000 ~ 5000', Money.fromYuan(1000), Money.fromYuan(5000)),
      ('5000 以上', Money.fromYuan(5000), Money.ofCents(1 << 62)),
    ];
    return bands.map(((String, Money, Money) band) {
      final inBand = rows
          .where((Entry e) => e.amount >= band.$2 && e.amount < band.$3)
          .toList();
      return StatVO(
        label: band.$1,
        income: _sum(inBand, EntryDirection.income),
        expense: _sum(inBand, EntryDirection.expense),
        count: inBand.length,
      );
    }).toList();
  }

  static Money _sum(List<Entry> rows, EntryDirection direction) {
    var total = Money.zero;
    for (final entry in rows) {
      if (entry.direction == direction) {
        total = total + entry.amount;
      }
    }
    return total;
  }
}
