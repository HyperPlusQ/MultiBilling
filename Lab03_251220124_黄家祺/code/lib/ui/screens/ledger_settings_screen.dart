import 'package:material_ui/material_ui.dart';

import '../../domain/ledger.dart';
import '../../domain/local_date.dart';
import '../../domain/money.dart';
import '../session.dart';
import '../widgets.dart';

/// 账本设置页：基本信息、有效期、金额上限、类别一览，以及创建/加入入口。
class LedgerSettingsScreen extends StatelessWidget {
  const LedgerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final ledger = session.currentLedger!;
    final categories = session.services.ledgerService.categoriesOf(
      ledger.ledgerId,
    );
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text(
              '账本设置',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => showJoinLedgerDialog(context),
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
              label: const Text('加入账本'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => showCreateLedgerDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建账本'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsForm(key: ValueKey(ledger.ledgerId), ledger: ledger),
        const SizedBox(height: 18),
        SectionCard(
          title: '收支类别',
          subtitle: '类别绑定单一方向，创建账本时自动生成',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in categories)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: parseHexColor(c.color).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: parseHexColor(c.color).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: parseHexColor(c.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${c.name} · ${c.direction.label}'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({super.key, required this.ledger});

  final Ledger ledger;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.ledger.name,
  );
  late final TextEditingController _limit = TextEditingController(
    text: widget.ledger.amountLimit.isPositive
        ? widget.ledger.amountLimit.asDecimal
        : '',
  );
  late LocalDate _from = widget.ledger.validFrom;
  late LocalDate _to = widget.ledger.validTo;

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to).toDateTime(),
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
      });
    }
  }

  void _save() {
    final session = Session.of(context);
    guard(context, () {
      Money? limit;
      if (_limit.text.trim().isNotEmpty) {
        limit = Money.parse(_limit.text);
      }
      session.services.ledgerService.updateSettings(
        widget.ledger.ledgerId,
        session.userId,
        name: _name.text,
        validFrom: _from,
        validTo: _to,
        amountLimit: limit ?? Money.zero,
      );
    }, success: '设置已保存');
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final isOwner = session.isOwner;
    final ledger = widget.ledger;
    if (!isOwner) {
      return SectionCard(
        title: '基本信息',
        subtitle: '只有发起者可以修改设置',
        child: Column(
          children: [
            InfoRow('账本名称', ledger.name),
            InfoRow('有效期', '${ledger.validFrom} ~ ${ledger.validTo}'),
            InfoRow(
              '单笔上限',
              ledger.amountLimit.isPositive
                  ? '¥${ledger.amountLimit.formatted}'
                  : '不限制',
            ),
            InfoRow('状态', ledger.status.label),
          ],
        ),
      );
    }
    return SectionCard(
      title: '基本信息',
      subtitle: '修改有效期与金额上限会立即影响后续提交',
      child: Column(
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '账本名称'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(isFrom: true),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('起始 ${_from.toIsoString()}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(isFrom: false),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('结束 ${_to.toIsoString()}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _limit,
            decoration: const InputDecoration(
              labelText: '单笔金额上限（元，留空表示不限制）',
              prefixText: '¥ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: _save, child: const Text('保存设置')),
          ),
        ],
      ),
    );
  }
}

/// 创建账本对话框收集到的表单数据。
class _LedgerForm {
  const _LedgerForm({
    required this.name,
    required this.from,
    required this.to,
    required this.limit,
  });

  final String name;
  final LocalDate from;
  final LocalDate to;
  final Money? limit;
}

/// 弹出创建账本对话框，成功后自动选中新账本。
Future<void> showCreateLedgerDialog(BuildContext context) async {
  final form = await showDialog<_LedgerForm>(
    context: context,
    builder: (_) => const _CreateLedgerDialog(),
  );
  if (form == null || !context.mounted) {
    return;
  }
  final session = Session.of(context);
  guard(context, () {
    final ledger = session.services.ledgerService.create(
      name: form.name,
      validFrom: form.from,
      validTo: form.to,
      ownerId: session.userId,
      amountLimit: form.limit,
    );
    session.selectLedger(ledger);
  }, success: '账本已创建');
}

/// 弹出加入账本对话框，成功后自动选中该账本。
Future<void> showJoinLedgerDialog(BuildContext context) async {
  final code = await promptText(context, title: '加入账本', label: '邀请码');
  if (code == null || code.trim().isEmpty || !context.mounted) {
    return;
  }
  final session = Session.of(context);
  guard(context, () {
    final member = session.services.ledgerService.joinByInviteCode(
      code,
      session.userId,
    );
    final ledger = session.services.ledgerService.requireLedger(
      member.ledgerId,
    );
    session.selectLedger(ledger);
  }, success: '已加入账本');
}

class _CreateLedgerDialog extends StatefulWidget {
  const _CreateLedgerDialog();

  @override
  State<_CreateLedgerDialog> createState() => _CreateLedgerDialogState();
}

class _CreateLedgerDialogState extends State<_CreateLedgerDialog> {
  final _name = TextEditingController();
  final _limit = TextEditingController();
  LocalDate _from = LocalDate.today();
  LocalDate _to = LocalDate.today().plusDays(180);

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to).toDateTime(),
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
      });
    }
  }

  void _submit() {
    Money? limit;
    if (_limit.text.trim().isNotEmpty) {
      try {
        limit = Money.parse(_limit.text);
      } on Exception catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
        return;
      }
    }
    Navigator.of(context)
        .pop(_LedgerForm(name: _name.text, from: _from, to: _to, limit: limit));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建账本'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '账本名称'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(isFrom: true),
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_from.toIsoString()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(isFrom: false),
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_to.toIsoString()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _limit,
              decoration: const InputDecoration(
                labelText: '单笔金额上限（元，可留空）',
                prefixText: '¥ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}
