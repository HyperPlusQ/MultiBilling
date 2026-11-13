import 'dart:io';

import '../domain/attachment.dart';
import '../domain/domain_exception.dart';
import '../domain/enums.dart';
import '../policy/permission_policy.dart';
import '../repository/memory_database.dart';
import '../repository/repositories.dart';
import 'audit_log_service.dart';

/// 附件服务，对应类图中的 `AttachmentService`。
///
/// 实验二设计用 MinIO + 预签名 URL；桌面版改为把文件复制进应用数据目录，
/// 以内容 SHA-256 作为存储文件名，天然去重。下载不需要签名，
/// 但仍校验调用者是否为该账本成员。
class AttachmentService {
  AttachmentService({
    required MemoryDatabase db,
    required AttachmentRepository attachments,
    required PermissionPolicy permissions,
    required AuditLogService audit,
    required Directory storageRoot,
  }) : _db = db,
       _attachments = attachments,
       _permissions = permissions,
       _audit = audit,
       _storageRoot = storageRoot;

  final MemoryDatabase _db;
  final AttachmentRepository _attachments;
  final PermissionPolicy _permissions;
  final AuditLogService _audit;
  final Directory _storageRoot;

  /// 上传一个本地文件作为条目附件。
  Attachment upload({
    required int ledgerId,
    required int entryId,
    required int uploaderId,
    required File source,
    required AttachmentPurpose purpose,
  }) {
    if (!_permissions.canView(ledgerId, uploaderId)) {
      throw ForbiddenException('你不是该账本成员，不能上传附件');
    }
    if (!source.existsSync()) {
      throw NotFoundException('待上传的文件');
    }
    final fileName = source.uri.pathSegments.last;
    final size = source.lengthSync();
    Attachment.assertAcceptable(fileName, size);
    final digest = Attachment.digestOf(source);
    final extension = _extensionOf(fileName);
    final stored = File('${_storageRoot.path}/$digest$extension');
    if (!stored.existsSync()) {
      if (!_storageRoot.existsSync()) {
        _storageRoot.createSync(recursive: true);
      }
      source.copySync(stored.path);
    }
    final attachment = Attachment(
      attachmentId: _db.nextId('attachment'),
      ledgerId: ledgerId,
      entryId: entryId,
      uploaderId: uploaderId,
      fileKey: stored.path,
      fileName: fileName,
      contentType: _contentTypeOf(extension),
      sizeBytes: size,
      sha256: digest,
      purpose: purpose,
      uploadedAt: DateTime.now(),
    );
    _attachments.save(attachment);
    _audit.record(
      DomainEvent(
        ledgerId: ledgerId,
        operatorId: uploaderId,
        action: 'ATTACHMENT_UPLOAD',
        targetType: 'Attachment',
        targetId: attachment.attachmentId,
        detail: <String, Object?>{
          'entryId': entryId,
          'fileName': fileName,
          'purpose': purpose.name,
          'sha256': digest,
        },
      ),
    );
    return attachment;
  }

  /// 断言条目已具备证明材料，供提交与修改申请前置校验。
  void assertProofPresent(int entryId) {
    if (!_attachments.hasPurpose(entryId, AttachmentPurpose.proof)) {
      throw ProofRequiredException('该操作需要上传证明材料附件');
    }
  }

  /// 某条目的附件列表。
  List<Attachment> ofEntry(int entryId) => _attachments.byEntry(entryId);

  /// 读取附件内容，先校验成员身份。
  File openFor(int attachmentId, int userId) {
    final attachment = _attachments.findById(attachmentId);
    if (attachment == null) {
      throw NotFoundException('附件 $attachmentId');
    }
    if (!_permissions.canView(attachment.ledgerId, userId)) {
      throw ForbiddenException('你不是该账本成员，不能查看附件');
    }
    final file = File(attachment.fileKey);
    if (!file.existsSync()) {
      throw NotFoundException('附件文件已丢失');
    }
    return file;
  }

  /// 校验附件内容是否仍与记录的摘要一致。
  bool verifyIntegrity(int attachmentId) {
    final attachment = _attachments.findById(attachmentId);
    if (attachment == null) {
      return false;
    }
    final file = File(attachment.fileKey);
    if (!file.existsSync()) {
      return false;
    }
    return Attachment.digestOf(file) == attachment.sha256;
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot).toLowerCase();
  }

  static String _contentTypeOf(String extension) {
    switch (extension) {
      case '.pdf':
        return 'application/pdf';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }
}
