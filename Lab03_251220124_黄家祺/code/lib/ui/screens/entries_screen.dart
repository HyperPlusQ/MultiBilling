import 'package:material_ui/material_ui.dart';

import '../../domain/category.dart';
import '../../domain/entry.dart';
import '../../domain/enums.dart';
import '../../domain/local_date.dart';
import '../../domain/money.dart';
import '../../repository/repositories.dart';
import '../../service/member_service.dart';
import '../session.dart';
import '../widgets.dart';
import 'entry_detail_screen.dart';

/// 条目列表页：四个板块 + 我的草稿，五维组合筛选，分页。
class EntriesScreen extends StatefulWidget {
  const EntriesScreen({super.key});

  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> {
  late EntryStatus _status;
  final _keyword = TextEditingController();
  final _minAmount = TextEditingController();
  final _maxAmount = TextEditingController();
  int? _categoryId;
  int? _submitterId;
  EntryDirection? _direction;
  LocalDate? _from;
  LocalDate? _to;
  int _page = 1;
  bool _showFilters = false;
  bool _focusConsumed = false;

  static const int _pageSize = 12;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 读取 inherited 的 Session 必须放在 didChangeDependencies，不能在 initState。
    // 只在首次进入时消费总览页传来的板块焦点，之后会话刷新不再重置当前板块。
    if (!_focusConsumed) {
      _focusConsumed = true;
      final session = Session.of(context);
      _status = session.boardFocus ?? EntryStatus.pending;
      session.boardFocus = null;
    }
  }

  @override
  void dispose() {
    _keyword.dispose();
    _minAmount.dispose();
    _maxAmount.dispose();
    super.dispose();
  }

  EntryQuery _buildQuery() {
    Money? parseMin() {
      final text = _minAmount.text.trim();
      return text.isEmpty ? null : Money.parse(text);
    }

    Money? parseMax() {
      final text = _maxAmount.text.trim();
      return text.isEmpty ? null : Money.parse(text);
    }

    return EntryQuery(
      keyword: _keyword.text.trim().isEmpty ? null : _keyword.text.trim(),
      categoryId: _categoryId,
      submitterId: _submitterId,
      status: _status,
      direction: _direction,
      from: _from,
      to: _to,
      minAmount: parseMin(),
      maxAmount: parseMax(),
      page: _page,
      pageSize: _pageSize,
    );
  }

  void _resetFilters() {
    setState(() {
      _keyword.clear();
      _minAmount.clear();
      _maxAmount.clear();
      _categoryId = null;
      _submitterId = null;
      _direction = null;
      _from = null;
      _to = null;
      _page = 1;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _from : _to)?.toDateTime() ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = LocalDate.fromDateTime(picked);
        } else {
          _to = LocalDate.fromDateTime(picked);
        }
        _page = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final ledgerId = session.ledgerId;
    final counts = services.entryService.boardCounts(ledgerId, session.userId);
    final categories = services.ledgerService.categoriesOf(ledgerId);
    final members = services.memberService.memberViews(ledgerId);
    final page = services.entryService.search(
      ledgerId,
      _buildQuery(),
      session.userId,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in const [
                      EntryStatus.pending,
                      EntryStatus.approved,
                      EntryStatus.rejected,
                      EntryStatus.invalid,
                      EntryStatus.draft,
                    ])
                      ChoiceChip(
                        selected: _status == status,
                        label: Text(
                          '${status == EntryStatus.draft ? '我的草稿' : status.label}'
                          ' (${counts[status] ?? 0})',
                        ),
                        onSelected: (_) => setState(() {
                          _status = status;
                          _page = 1;
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyword,
                  decoration: InputDecoration(
                    hintText: '搜索标题或事由',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _keyword.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() {
                              _keyword.clear();
                              _page = 1;
                            }),
                          ),
                  ),
                  onChanged: (_) => setState(() => _page = 1),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => setState(() => _showFilters = !_showFilters),
                icon: Icon(
                  _showFilters ? Icons.filter_alt_off : Icons.filter_alt,
                  size: 18,
                ),
                label: Text(_showFilters ? '收起筛选' : '高级筛选'),
              ),
            ],
          ),
        ),
        if (_showFilters)
          _FilterPanel(
            categories: categories,
            members: members,
            categoryId: _categoryId,
            submitterId: _submitterId,
            direction: _direction,
            from: _from,
            to: _to,
            minAmount: _minAmount,
            maxAmount: _maxAmount,
            onCategory: (v) => setState(() {
              _categoryId = v;
              _page = 1;
            }),
            onSubmitter: (v) => setState(() {
              _submitterId = v;
              _page = 1;
            }),
            onDirection: (v) => setState(() {
              _direction = v;
              _page = 1;
            }),
            onPickFrom: () => _pickDate(isFrom: true),
            onPickTo: () => _pickDate(isFrom: false),
            onClearRange: () => setState(() {
              _from = null;
              _to = null;
              _page = 1;
            }),
            onAmountChanged: () => setState(() => _page = 1),
            onReset: _resetFilters,
          ),
        const Divider(height: 16),
        Expanded(
          child: page.items.isEmpty
              ? const EmptyHint(icon: Icons.search_off, text: '没有符合条件的条目')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) => _EntryRow(entry: page.items[i]),
                ),
        ),
        _Pager(
          page: page.page,
          pageCount: page.pageCount,
          total: page.total,
          onPrev: page.page > 1 ? () => setState(() => _page -= 1) : null,
          onNext: page.hasNext ? () => setState(() => _page += 1) : null,
        ),
      ],
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.categories,
    required this.members,
    required this.categoryId,
    required this.submitterId,
    required this.direction,
    required this.from,
    required this.to,
    required this.minAmount,
    required this.maxAmount,
    required this.onCategory,
    required this.onSubmitter,
    required this.onDirection,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClearRange,
    required this.onAmountChanged,
    required this.onReset,
  });

  final List<Category> categories;
  final List<MemberView> members;
  final int? categoryId;
  final int? submitterId;
  final EntryDirection? direction;
  final LocalDate? from;
  final LocalDate? to;
  final TextEditingController minAmount;
  final TextEditingController maxAmount;
  final ValueChanged<int?> onCategory;
  final ValueChanged<int?> onSubmitter;
  final ValueChanged<EntryDirection?> onDirection;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClearRange;
  final VoidCallback onAmountChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int?>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: '类别'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全部类别')),
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c.categoryId,
                        child: Text(c.name),
                      ),
                  ],
                  onChanged: onCategory,
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int?>(
                  initialValue: submitterId,
                  decoration: const InputDecoration(labelText: '提交人'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全部成员')),
                    for (final m in members.where((m) => !m.hasLeft))
                      DropdownMenuItem(
                        value: m.member.userId,
                        child: Text(m.displayName),
                      ),
                  ],
                  onChanged: onSubmitter,
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<EntryDirection?>(
                  initialValue: direction,
                  decoration: const InputDecoration(labelText: '方向'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('全部方向')),
                    DropdownMenuItem(
                      value: EntryDirection.income,
                      child: Text('收入'),
                    ),
                    DropdownMenuItem(
                      value: EntryDirection.expense,
                      child: Text('支出'),
                    ),
                  ],
                  onChanged: onDirection,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onPickFrom,
                icon: const Icon(Icons.event, size: 18),
                label: Text(from == null ? '起始日期' : from!.toIsoString()),
              ),
              OutlinedButton.icon(
                onPressed: onPickTo,
                icon: const Icon(Icons.event, size: 18),
                label: Text(to == null ? '结束日期' : to!.toIsoString()),
              ),
              if (from != null || to != null)
                TextButton(onPressed: onClearRange, child: const Text('清除日期')),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: minAmount,
                  decoration: const InputDecoration(labelText: '最小金额'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onAmountChanged(),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: maxAmount,
                  decoration: const InputDecoration(labelText: '最大金额'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onAmountChanged(),
                ),
              ),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('重置全部'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final category = session.services.categories.findById(entry.categoryId);
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EntryDetailScreen(entryId: entry.entryId),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: parseHexColor(category?.color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (entry.strictReview) ...[
                        const SizedBox(width: 6),
                        const _MiniBadge(
                          text: '严格审核',
                          color: Color(0xFFEF6C00),
                        ),
                      ],
                      if (entry.supplementRequested) ...[
                        const SizedBox(width: 6),
                        const _MiniBadge(text: '待补充', color: Color(0xFF1E88E5)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${category?.name ?? '未分类'} · '
                    '${session.services.auth.displayNameOf(entry.submitterId)} · '
                    '${formatDate(entry.occurredAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            StatusChip(entry.status, dense: true),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerRight,
                child: MoneyText(
                  entry.amount,
                  direction: entry.direction,
                  showSign: true,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10)),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Text(
            '共 $total 条 · 第 $page / ${pageCount == 0 ? 1 : pageCount} 页',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}
