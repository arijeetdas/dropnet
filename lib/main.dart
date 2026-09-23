import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/platform/device_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Needed before anything builds a device identity or renders platform
  // branding (e.g. telling a Chromebook apart from an Android phone).
  await DeviceEnvironment.initialize();
  runApp(const ProviderScope(child: DropNetApp()));
}
