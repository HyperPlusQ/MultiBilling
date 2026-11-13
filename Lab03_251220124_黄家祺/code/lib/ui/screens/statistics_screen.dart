import 'package:material_ui/material_ui.dart';

import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../repository/repositories.dart';
import '../../service/statistics_service.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

/// 统计页：总览指标 + 按类别 / 按成员 / 按月趋势 / 金额分布。
///
/// 所有数据都来自 StatisticsService，口径固定为「仅已审核」。
/// 图表用纯 Flutter 组件绘制，不引入第三方图表库。
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  EntryDirection? _direction;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final ledgerId = session.ledgerId;
    final filter = EntryQuery(direction: _direction);
    final summary = services.statistics.summary(ledgerId, filter);
    final byCategory = services.statistics.byCategory(ledgerId, filter);
    final byMember = services.statistics.byMember(ledgerId, filter);
    final trend = services.statistics.trend(ledgerId, filter);
    final bands = services.statistics.byAmountBand(ledgerId, filter);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text(
              '统计',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            SegmentedButton<EntryDirection?>(
              segments: const [
                ButtonSegment(value: null, label: Text('全部')),
                ButtonSegment(value: EntryDirection.income, label: Text('收入')),
                ButtonSegment(value: EntryDirection.expense, label: Text('支出')),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          StatisticsService.caliberNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _Metric(label: '收入', money: summary.income, color: AppTheme.income),
            _Metric(
              label: '支出',
              money: summary.expense,
              color: AppTheme.expense,
            ),
            _Metric(
              label: '结余',
              money: summary.balance,
              color: summary.balance.cents >= 0
                  ? AppTheme.income
                  : AppTheme.expense,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '按类别',
          subtitle: '按收支总量降序',
          child: byCategory.isEmpty
              ? const EmptyHint(icon: Icons.pie_chart_outline, text: '暂无已审核数据')
              : _BarList(
                  rows: [
                    for (final s in byCategory)
                      _BarData(
                        label: s.label,
                        value: s.volume,
                        color: parseHexColor(s.color),
                        caption: '${s.count} 笔',
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '按成员',
          subtitle: '按收支总量降序',
          child: byMember.isEmpty
              ? const EmptyHint(icon: Icons.group_outlined, text: '暂无已审核数据')
              : _BarList(
                  rows: [
                    for (final s in byMember)
                      _BarData(
                        label: s.label,
                        value: s.volume,
                        color: theme.colorScheme.primary,
                        caption: '${s.count} 笔',
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '按月趋势',
          child: trend.isEmpty
              ? const EmptyHint(icon: Icons.show_chart, text: '暂无已审核数据')
              : Column(
                  children: [
                    for (final p in trend)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _TrendRow(point: p),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '金额分布',
          child: _BarList(
            rows: [
              for (final s in bands)
                _BarData(
                  label: s.label,
                  value: Money.ofCents(s.count * 100),
                  color: theme.colorScheme.tertiary,
                  caption: '${s.count} 笔',
                  isCount: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.money,
    required this.color,
  });

  final String label;
  final Money money;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '¥${money.formatted}',
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarData {
  const _BarData({
    required this.label,
    required this.value,
    required this.color,
    required this.caption,
    this.isCount = false,
  });

  final String label;
  final Money value;
  final Color color;
  final String caption;
  final bool isCount;
}

class _BarList extends StatelessWidget {
  const _BarList({required this.rows});

  final List<_BarData> rows;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(
      1,
      (m, r) => r.value.cents > m ? r.value.cents : m,
    );
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: _Track(ratio: r.value.cents / max, color: r.color),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      r.isCount ? r.caption : '¥${r.value.formatted}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = ratio.clamp(0.0, 1.0);
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped == 0 ? 0.001 : clamped,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.point});

  final PointVO point;

  @override
  Widget build(BuildContext context) {
    final max = [
      point.income.cents,
      point.expense.cents,
      1,
    ].reduce((a, b) => a > b ? a : b);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            point.label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Column(
            children: [
              _Track(ratio: point.income.cents / max, color: AppTheme.income),
              const SizedBox(height: 4),
              _Track(ratio: point.expense.cents / max, color: AppTheme.expense),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+¥${point.income.formatted}',
                style: const TextStyle(color: AppTheme.income, fontSize: 12),
              ),
              Text(
                '-¥${point.expense.formatted}',
                style: const TextStyle(color: AppTheme.expense, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
