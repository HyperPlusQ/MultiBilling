import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'app_services.dart';
import 'ui/app.dart';
import 'ui/session.dart';

/// 程序入口。
///
/// 桌面单机版：确定一个 per-user 的数据目录，装配服务，载入存档；
/// 首次启动（存档不存在）时播种一份演示数据，让界面一打开就有内容可看。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final dataDir = _resolveDataDir();
  if (!dataDir.existsSync()) {
    dataDir.createSync(recursive: true);
  }
  final services = AppServices.create(dataDir: dataDir);
  final loaded = services.load();
  if (!loaded) {
    services.seedDemoData();
  }
  runApp(MultiBillingApp(session: Session(services)));
}

/// 数据目录：macOS 放在 Application Support，其它平台放在用户主目录下。
Directory _resolveDataDir() {
  final home = Platform.environment['HOME'] ?? Directory.current.path;
  if (Platform.isMacOS) {
    return Directory('$home/Library/Application Support/MultiBilling');
  }
  return Directory('$home/.multibilling');
}
