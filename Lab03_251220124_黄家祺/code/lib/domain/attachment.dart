import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'domain_exception.dart';
import 'enums.dart';

/// 附件，对应类图中的 `Attachment`。
///
/// 实验二设计里附件存在 MinIO 对象存储、通过预签名 URL 下载。桌面单机版
/// 没有对象存储，改为把文件复制进应用数据目录，用内容摘要作为文件名，
/// 因此 [sha256] 既是去重键也是完整性校验值。
class Attachment {
  Attachment({
    required this.attachmentId,
    required this.ledgerId,
    required this.entryId,
    required this.uploaderId,
    required this.fileKey,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.purpose,
    required this.uploadedAt,
  });

  /// 从 JSON 还原。
  factory Attachment.fromJson(Map<String, Object?> json) => Attachment(
    attachmentId: json['attachmentId']! as int,
    ledgerId: json['ledgerId']! as int,
    entryId: json['entryId']! as int,
    uploaderId: json['uploaderId']! as int,
    fileKey: json['fileKey']! as String,
    fileName: json['fileName']! as String,
    contentType: json['contentType']! as String,
    sizeBytes: json['sizeBytes']! as int,
    sha256: json['sha256']! as String,
    purpose: AttachmentPurpose.values.byName(json['purpose']! as String),
    uploadedAt: DateTime.parse(json['uploadedAt']! as String),
  );

  /// 单文件大小上限：20MB。
  static const int maxSizeBytes = 20 * 1024 * 1024;

  /// 允许的类型，与实验二假设 A7 一致。
  static const List<String> allowedExtensions = <String>[
    '.pdf',
    '.jpg',
    '.jpeg',
    '.png',
  ];

  /// 主键。
  final int attachmentId;

  /// 所属账本。
  final int ledgerId;

  /// 关联条目。
  final int entryId;

  /// 上传人。
  final int uploaderId;

  /// 存储相对路径。
  final String fileKey;

  /// 原始文件名，仅用于展示。
  final String fileName;

  /// MIME 类型。
  final String contentType;

  /// 字节数。
  final int sizeBytes;

  /// 内容摘要。
  final String sha256;

  /// 用途。
  final AttachmentPurpose purpose;

  /// 上传时间。
  final DateTime uploadedAt;

  /// 是否为证明材料。
  bool get isProof => purpose == AttachmentPurpose.proof;

  /// 人类可读的体积。
  String get readableSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// 校验扩展名与体积是否可接受。
  static void assertAcceptable(String fileName, int sizeBytes) {
    final lower = fileName.toLowerCase();
    final ok = allowedExtensions.any(lower.endsWith);
    if (!ok) {
      throw ValidationException('仅支持 PDF / JPG / PNG 附件', field: 'attachment');
    }
    if (sizeBytes <= 0) {
      throw ValidationException('附件内容为空', field: 'attachment');
    }
    if (sizeBytes > maxSizeBytes) {
      throw ValidationException('附件不能超过 20MB', field: 'attachment');
    }
  }

  /// 读取文件并计算 SHA-256。
  static String digestOf(File file) {
    final bytes = file.readAsBytesSync();
    return crypto.sha256.convert(bytes).toString();
  }

  /// 计算一段文本的摘要，供存档哈希链复用同一套算法。
  static String digestText(String text) =>
      crypto.sha256.convert(utf8.encode(text)).toString();

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'attachmentId': attachmentId,
    'ledgerId': ledgerId,
    'entryId': entryId,
    'uploaderId': uploaderId,
    'fileKey': fileKey,
    'fileName': fileName,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'purpose': purpose.name,
    'uploadedAt': uploadedAt.toIso8601String(),
  };

  @override
  String toString() => 'Attachment($attachmentId, $fileName, ${purpose.label})';
}
