import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/utils/formatters.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Formatters.ensureInitialized();
  runApp(const ProviderScope(child: FinTrackApp()));
}
