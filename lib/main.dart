import 'package:flutter/material.dart';

import 'app.dart';
import 'sqlite_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = await SqliteLedgerRepository.open();
    runApp(CashflowApp(repository: repository));
  } catch (error) {
    runApp(StartupErrorApp(message: '$error'));
  }
}
