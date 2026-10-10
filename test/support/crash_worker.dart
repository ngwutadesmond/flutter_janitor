import 'dart:io';
import 'package:flutter_janitor/src/cleaner.dart';
import 'package:flutter_janitor/src/models.dart';

Future<void> main(List<String> args) async {
  await Cleaner(checkpoint: (phase) async {
    if (phase == args[1]) exit(73);
  }).apply(
      projectRoot: args[0],
      backupDir: '.janitor_backup',
      plan: const CleanActionPlan(
          assetPaths: {'assets/remove.png', 'explicit.png'},
          removeDependencies: {'unused'},
          removeDevDependencies: {'unused_dev'}));
}
