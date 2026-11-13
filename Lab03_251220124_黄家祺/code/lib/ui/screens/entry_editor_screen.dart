import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../domain/attachment.dart';
import '../../domain/domain_exception.dart';
import '../../domain/entry.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../service/entry_service.dart';
import '../file_picker.dart';
import '../session.dart';
import '../widgets.dart';

/// 新建 / 编辑条目页。
///
/// 草稿与被驳回条目可编辑。提交前先做预检：若命中重复或超限需要证明材料，
/// 必须先上传 PROOF 附件才允许提交，这与后端校验完全一致。
class EntryEditorScreen extends StatefulWidget {
  const EntryEditorScreen({super.key, this.entry});

  /// 传入则为编辑模式。
  final Entry? entry;

  @override
  State<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends State<EntryEditorScreen> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  int? _categoryId;
  DateTime _occurredAt = DateTime.now();
  int? _entryId;
  AttachmentPurpose _purpose = AttachmentPurpose.proof;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null) {
      _entryId = entry.entryId;
      _title.text = entry.title;
      _amount.text = entry.amount.asDecimal;
      _reason.text = entry.reason;
      _categoryId = entry.categoryId;
      _occurredAt = entry.occurredAt;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  EntryCommand _command() {
    if (_categoryId == null) {
      throw ValidationException('请选择类别', field: 'categoryId');
    }
    return EntryCommand(
      categoryId: _categoryId!,
      title: _title.text,
      amount: Money.parse(_amount.text),
      occurredAt: _occurredAt,
      reason: _reason.text,
    );
  }

  void _saveDraft() {
    final session = Session.of(context);
    guard(context, () {
      final cmd = _command();
      if (_entryId == null) {
        final created = session.services.entryService.createDraft(
          session.ledgerId,
          cmd,
          session.userId,
        );
        setState(() => _entryId = created.entryId);
      } else {
        session.services.entryService.updateDraft(
          _entryId!,
          cmd,
          session.userId,
        );
      }
    }, success: '草稿已保存');
  }

  void _submit() {
    final session = Session.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final services = session.services;
    try {
      final cmd = _command();
      final int id;
      if (_entryId == null) {
        id = services.entryService
            .createDraft(session.ledgerId, cmd, session.userId)
            .entryId;
      } else {
        services.entryService.updateDraft(_entryId!, cmd, session.userId);
        id = _entryId!;
      }
      final preview = services.entryService.preview(id, session.userId);
      if (!preview.canSubmit) {
        setState(() => _entryId = id);
        messenger.showSnackBar(SnackBar(content: Text(preview.blockingReason)));
        return;
      }
      services.entryService.submit(id, session.userId);
      session.touch();
      messenger.showSnackBar(const SnackBar(content: Text('已提交，等待管理员审核')));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on DomainException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickOccurredAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
    });
  }

  Future<void> _upload() async {
    final session = Session.of(context);
    final path = await pickFilePath();
    if (path == null || !mounted) {
      return;
    }
    await guardAsync(context, () async {
      session.services.attachmentService.upload(
        ledgerId: session.ledgerId,
        entryId: _entryId!,
        uploaderId: session.userId,
        source: File(path),
        purpose: _purpose,
      );
    }, success: '附件已上传');
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final categories = session.services.ledgerService.categoriesOf(
      session.ledgerId,
    );
    final isEdit = widget.entry != null;
    final attachments = _entryId == null
        ? <Attachment>[]
        : session.services.attachmentService.ofEntry(_entryId!);

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '编辑条目' : '新建条目')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: '标题'),
                maxLength: Entry.maxTitleLength,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: '类别（决定收支方向）'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(
                      value: c.categoryId,
                      child: Text('${c.name}（${c.direction.label}）'),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                decoration: const InputDecoration(
                  labelText: '金额（元）',
                  prefixText: '¥ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickOccurredAt,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: '发生时间'),
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 18),
                      const SizedBox(width: 8),
                      Text(formatDateTime(_occurredAt)),
                      const Spacer(),
                      const Icon(Icons.edit_calendar, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(labelText: '事由'),
                maxLines: 3,
                maxLength: Entry.maxReasonLength,
              ),
              const SizedBox(height: 8),
              if (_entryId != null) ...[
                _AttachmentSection(
                  attachments: attachments,
                  purpose: _purpose,
                  onPurpose: (p) => setState(() => _purpose = p),
                  onUpload: _upload,
                ),
                const SizedBox(height: 8),
              ] else
                Text(
                  '提示：保存草稿后即可上传票据 / 证明材料。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saveDraft,
                      child: const Text('保存草稿'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('提交审核'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.attachments,
    required this.purpose,
    required this.onPurpose,
    required this.onUpload,
  });

  final List<Attachment> attachments;
  final AttachmentPurpose purpose;
  final ValueChanged<AttachmentPurpose> onPurpose;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '附件',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (attachments.isEmpty)
          Text(
            '尚未上传附件',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final a in attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${a.fileName} · ${a.purpose.label} · ${a.readableSize}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<AttachmentPurpose>(
                initialValue: purpose,
                decoration: const InputDecoration(labelText: '用途'),
                items: [
                  for (final p in AttachmentPurpose.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (p) {
                  if (p != null) {
                    onPurpose(p);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('选择文件上传'),
            ),
          ],
        ),
      ],
    );
  }
}
