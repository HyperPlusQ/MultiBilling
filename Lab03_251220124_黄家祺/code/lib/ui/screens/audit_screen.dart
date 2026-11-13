import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../domain/operation_log.dart';
import '../session.dart';
import '../widgets.dart';

/// 操作存档页：哈希链校验 + 追加式存档列表。
///
/// 存档只能追加与读取，界面不提供任何修改/删除入口；每条记录展示
/// 前驱哈希与本条哈希，任何篡改都会在整链校验时暴露。
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final logs = services.audit.history(session.ledgerId);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '操作存档',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '共 ${logs.length} 条 · 链尾 '
                      '${services.audit.shortTailHash(session.ledgerId)}…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _verify(context),
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('校验哈希链'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: logs.isEmpty
              ? const EmptyHint(icon: Icons.history_edu_outlined, text: '暂无存档')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  itemCount: logs.length,
                  itemBuilder: (_, i) =>
                      _LogTile(log: logs[logs.length - 1 - i]),
                ),
        ),
      ],
    );
  }

  void _verify(BuildContext context) {
    final session = Session.of(context);
    final result = session.services.audit.verifyChain(session.ledgerId);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          result.valid ? Icons.verified : Icons.gpp_bad,
          color: result.valid
              ? const Color(0xFF2E7D32)
              : const Color(0xFFC62828),
          size: 40,
        ),
        title: Text(result.valid ? '哈希链完好' : '检测到篡改'),
        content: Text(
          result.valid
              ? '已逐条重算并比对 ${result.checkedCount} 条记录，前驱哈希全部衔接，'
                    '未发现篡改。'
              : (result.reason ?? '校验失败'),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final OperationLog log;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final theme = Theme.of(context);
    const encoder = JsonEncoder.withIndent('  ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(_iconOf(log.action), size: 20),
        title: Text(
          log.actionLabel,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          '${session.services.auth.displayNameOf(log.operatorId)} · '
          '${formatDateTime(log.createdAt)} · '
          '${log.targetType} #${log.targetId}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Text(
          log.hash.substring(0, 8),
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HashRow(label: '前驱', value: log.prevHash),
          _HashRow(label: '本条', value: log.hash),
          if (log.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                encoder.convert(log.detail),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconOf(String action) {
    if (action.startsWith('ENTRY')) {
      return Icons.receipt_long_outlined;
    }
    if (action.startsWith('VOID')) {
      return Icons.how_to_vote_outlined;
    }
    if (action.startsWith('MOD')) {
      return Icons.edit_note_outlined;
    }
    if (action.startsWith('LEDGER') || action.startsWith('MEMBER')) {
      return Icons.group_outlined;
    }
    if (action.startsWith('ATTACHMENT')) {
      return Icons.attach_file;
    }
    return Icons.history;
  }
}

class _HashRow extends StatelessWidget {
  const _HashRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
