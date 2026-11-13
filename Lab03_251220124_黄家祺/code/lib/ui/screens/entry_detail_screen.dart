import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../domain/attachment.dart';
import '../../domain/domain_exception.dart';
import '../../domain/entry.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../session.dart';
import '../widgets.dart';
import 'entry_editor_screen.dart';
import 'void_widgets.dart';

/// 条目详情页：字段、附件、审核时间线、作废与修改申请，以及随角色/状态
/// 变化的操作按钮。所有写操作都经服务层校验，界面只负责收集输入。
class EntryDetailScreen extends StatelessWidget {
  const EntryDetailScreen({super.key, required this.entryId});

  final int entryId;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final entry = services.entryService.requireEntry(entryId);
    final ledger = services.ledgerService.requireLedger(entry.ledgerId);
    final category = services.categories.findById(entry.categoryId);
    final theme = Theme.of(context);

    final canEdit = services.permissions.canEdit(entry, session.userId);
    final canReview = services.permissions.canReview(ledger, session.userId);
    final isSubmitter = entry.submitterId == session.userId;
    final canSubmit =
        isSubmitter &&
        (entry.status == EntryStatus.draft ||
            entry.status == EntryStatus.rejected);
    final canModify = entry.status == EntryStatus.approved;
    final attachments = services.attachmentService.ofEntry(entryId);
    final timeline = services.reviewService.timeline(entryId);
    final voidHistory = services.voidService.historyOf(entryId);
    final openMod = services.modifications.findOpenByEntry(entryId);

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StatusChip(entry.status)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              DirectionChip(entry.direction),
                              const SizedBox(width: 10),
                              MoneyText(
                                entry.amount,
                                direction: entry.direction,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              if (entry.strictReview)
                                const _Tag(
                                  text: '严格审核',
                                  color: Color(0xFFEF6C00),
                                ),
                              if (entry.supplementRequested)
                                const _Tag(
                                  text: '待补充',
                                  color: Color(0xFF1E88E5),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InfoRow('类别', category?.name ?? '未分类'),
                          InfoRow(
                            '提交人',
                            services.auth.displayNameOf(entry.submitterId),
                          ),
                          InfoRow('发生时间', formatDateTime(entry.occurredAt)),
                          InfoRow('事由', entry.reason),
                          InfoRow('版本', 'v${entry.version}'),
                          if (entry.lastReviewerId != null)
                            InfoRow(
                              '最近审核人',
                              services.auth.displayNameOf(
                                entry.lastReviewerId!,
                              ),
                            ),
                          if (entry.replacesEntryId != null)
                            InfoRow('替代条目', '#${entry.replacesEntryId}'),
                          if (entry.invalidReason != null)
                            InfoRow(
                              '无效原因',
                              entry.invalidReason!,
                              valueColor: const Color(0xFFC62828),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ActionBar(
                    entry: entry,
                    canEdit: canEdit,
                    canSubmit: canSubmit,
                    canReview: canReview,
                    canModify: canModify,
                    hasProof: attachments.any((a) => a.isProof),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: '附件',
                    subtitle: '重复 / 超限 / 修改已审核条目需要证明材料',
                    trailing: OutlinedButton.icon(
                      onPressed: () => _upload(context, entry),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('上传'),
                    ),
                    child: attachments.isEmpty
                        ? const EmptyHint(icon: Icons.attach_file, text: '暂无附件')
                        : Column(
                            children: [
                              for (final a in attachments)
                                _AttachmentRow(attachment: a),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: '审核时间线',
                    child: timeline.isEmpty
                        ? const EmptyHint(icon: Icons.history, text: '还没有审核记录')
                        : Column(
                            children: [
                              for (final r in timeline)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _reviewIcon(r.action),
                                        size: 18,
                                        color: _reviewColor(r.action),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${services.auth.displayNameOf(r.reviewerId)}'
                                              ' · ${r.action.label} · '
                                              '${formatDateTime(r.createdAt)}',
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                            if (r.comment.isNotEmpty)
                                              Text(
                                                r.comment,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (openMod != null) ...[
                    const SizedBox(height: 16),
                    SectionCard(
                      title: '进行中的修改申请',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '申请人：'
                            '${services.auth.displayNameOf(openMod.applicantId)}',
                          ),
                          const SizedBox(height: 6),
                          for (final line in openMod.describeChanges())
                            Text('· $line'),
                          const SizedBox(height: 6),
                          Text(
                            '等待管理员在审批中心处理。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (voidHistory.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '作废申请',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final v in voidHistory)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: VoidRequestCard(request: v),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _upload(BuildContext context, Entry entry) async {
    final session = Session.of(context);
    final path = await _pick();
    if (path == null || !context.mounted) {
      return;
    }
    await guardAsync(context, () async {
      session.services.attachmentService.upload(
        ledgerId: entry.ledgerId,
        entryId: entry.entryId,
        uploaderId: session.userId,
        source: File(path),
        purpose: AttachmentPurpose.proof,
      );
    }, success: '证明材料已上传');
  }

  static Future<String?> _pick() async {
    if (!Platform.isMacOS) {
      return null;
    }
    const script =
        'set f to choose file with prompt "选择证明材料（PDF / JPG / PNG）"\n'
        'POSIX path of f';
    final result = await Process.run('osascript', ['-e', script]);
    if (result.exitCode != 0) {
      return null;
    }
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  static IconData _reviewIcon(ReviewAction action) => switch (action) {
    ReviewAction.approve => Icons.check_circle,
    ReviewAction.reject => Icons.cancel,
    ReviewAction.requestSupplement => Icons.help,
  };

  static Color _reviewColor(ReviewAction action) => switch (action) {
    ReviewAction.approve => const Color(0xFF2E7D32),
    ReviewAction.reject => const Color(0xFFC62828),
    ReviewAction.requestSupplement => const Color(0xFF1E88E5),
  };
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.entry,
    required this.canEdit,
    required this.canSubmit,
    required this.canReview,
    required this.canModify,
    required this.hasProof,
  });

  final Entry entry;
  final bool canEdit;
  final bool canSubmit;
  final bool canReview;
  final bool canModify;
  final bool hasProof;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final buttons = <Widget>[];

    if (canEdit) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EntryEditorScreen(entry: entry),
            ),
          ),
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('编辑'),
        ),
      );
    }
    if (canSubmit) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => guard(
            context,
            () => services.entryService.submit(entry.entryId, session.userId),
            success: '已提交审核',
          ),
          icon: const Icon(Icons.send, size: 18),
          label: Text(entry.status == EntryStatus.rejected ? '重新提交' : '提交审核'),
        ),
      );
    }
    if (canReview && entry.status == EntryStatus.pending) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => guard(
            context,
            () => services.reviewService.review(
              entryId: entry.entryId,
              action: ReviewAction.approve,
              comment: '',
              adminId: session.userId,
            ),
            success: '已通过',
          ),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('通过'),
        ),
      );
      buttons.add(
        OutlinedButton.icon(
          onPressed: () =>
              _reviewWithComment(context, entry, ReviewAction.reject),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('打回'),
        ),
      );
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _reviewWithComment(
            context,
            entry,
            ReviewAction.requestSupplement,
          ),
          icon: const Icon(Icons.help_outline, size: 18),
          label: const Text('要求补充'),
        ),
      );
    }
    if (canModify) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _applyModification(context, entry, hasProof),
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('申请修改'),
        ),
      );
    }
    if (canReview && entry.status == EntryStatus.approved) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _initiateVoid(context, entry),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('发起作废'),
        ),
      );
    }

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }

  Future<void> _reviewWithComment(
    BuildContext context,
    Entry entry,
    ReviewAction action,
  ) async {
    final session = Session.of(context);
    final comment = await promptText(
      context,
      title: action.label,
      label: '原因（必填）',
      multiline: true,
    );
    if (comment == null || !context.mounted) {
      return;
    }
    guard(
      context,
      () => session.services.reviewService.review(
        entryId: entry.entryId,
        action: action,
        comment: comment,
        adminId: session.userId,
      ),
      success: '已${action.label}',
    );
  }

  Future<void> _initiateVoid(BuildContext context, Entry entry) async {
    final session = Session.of(context);
    final reason = await promptText(
      context,
      title: '发起作废投票',
      label: '作废理由（必填）',
      multiline: true,
    );
    if (reason == null || !context.mounted) {
      return;
    }
    guard(
      context,
      () => session.services.voidService.initiate(
        entryId: entry.entryId,
        reason: reason,
        adminId: session.userId,
      ),
      success: '已发起作废投票',
    );
  }

  Future<void> _applyModification(
    BuildContext context,
    Entry entry,
    bool hasProof,
  ) async {
    final session = Session.of(context);
    if (!hasProof) {
      showSnack(context, '修改已审核条目必须先上传证明材料附件', error: true);
      return;
    }
    final snapshot = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ModificationDialog(entry: entry),
    );
    if (snapshot == null || !context.mounted) {
      return;
    }
    final proof = session.services.attachmentService
        .ofEntry(entry.entryId)
        .firstWhere((a) => a.isProof);
    guard(
      context,
      () => session.services.reviewService.applyModification(
        entryId: entry.entryId,
        applicantId: session.userId,
        proposedSnapshot: snapshot,
        proofAttachmentId: proof.attachmentId,
      ),
      success: '修改申请已提交，等待管理员审批',
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            attachment.contentType.startsWith('image/')
                ? Icons.image_outlined
                : Icons.picture_as_pdf_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${attachment.fileName} · ${attachment.purpose.label} · '
              '${attachment.readableSize}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => _open(context, session),
            child: const Text('打开'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, Session session) async {
    try {
      final file = session.services.attachmentService.openFor(
        attachment.attachmentId,
        session.userId,
      );
      if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      }
    } on DomainException catch (e) {
      if (context.mounted) {
        showSnack(context, e.message, error: true);
      }
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 修改申请表单：只提交发生变化的字段，生成快照。
class _ModificationDialog extends StatefulWidget {
  const _ModificationDialog({required this.entry});

  final Entry entry;

  @override
  State<_ModificationDialog> createState() => _ModificationDialogState();
}

class _ModificationDialogState extends State<_ModificationDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.entry.title,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.entry.amount.asDecimal,
  );
  late final TextEditingController _reason = TextEditingController(
    text: widget.entry.reason,
  );

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final snapshot = <String, Object?>{};
    if (_title.text.trim() != widget.entry.title) {
      snapshot['title'] = _title.text.trim();
    }
    if (_reason.text.trim() != widget.entry.reason) {
      snapshot['reason'] = _reason.text.trim();
    }
    try {
      final amount = Money.parse(_amount.text);
      if (amount != widget.entry.amount) {
        snapshot['amount'] = amount.asDecimal;
      }
    } on DomainException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    Navigator.of(context).pop(snapshot);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('申请修改'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '修改通过后，原条目将置为无效，并生成一条新的待审核条目。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              decoration: const InputDecoration(labelText: '金额（元）'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: '事由'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('提交申请')),
      ],
    );
  }
}
