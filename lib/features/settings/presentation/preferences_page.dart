import 'package:flutter/material.dart';

import '../../../core/widgets/feature_placeholder_page.dart';

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholderPage(
        title: 'Preferensi Aplikasi',
        description: 'Preferensi tersimpan dibangun bersama tabel app_settings.',
        icon: Icons.tune_rounded,
        stage: 2,
      );
}
