import 'dart:io';

/// 桌面端文件选择。
///
/// 为了不引入原生插件依赖，macOS 上直接调用系统 `osascript` 弹出原生
/// 选择框；其它平台返回 null，由界面退化为手动输入路径。
/// 选择结果只是一个本地路径，真正的类型/体积校验仍由领域层负责。
Future<String?> pickFilePath() async {
  if (!Platform.isMacOS) {
    return null;
  }
  const script =
      'set f to choose file with prompt "选择附件（PDF / JPG / PNG）"\n'
      'POSIX path of f';
  final result = await Process.run('osascript', ['-e', script]);
  if (result.exitCode != 0) {
    return null;
  }
  final path = (result.stdout as String).trim();
  return path.isEmpty ? null : path;
}
