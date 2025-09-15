import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> testExecutable(FutureOr<void> Function() main) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await main();
}
