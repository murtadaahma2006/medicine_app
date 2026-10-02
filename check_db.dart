import 'dart:convert';
import 'package:medicine_app/src/core/database/database_helper.dart';
import 'package:medicine_app/src/core/agent/task_repository.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = TaskRepository();
  final tasks = await repo.getTasks();
  if (tasks.isEmpty) {
    print('No tasks found.');
    return;
  }
  final task = tasks.last;
  print('Task: \${task.id} - \${task.title} - Status: \${task.status}');
  print('Payload keys: \${task.payload != null ? jsonDecode(task.payload!).keys : "null"}');
  
  final steps = await repo.getStepsForTask(task.id);
  for (final step in steps) {
    print('Step: \${step.type} - Status: \${step.status} - Output Length: \${step.outputPayload?.length ?? 0}');
    if (step.outputPayload != null && step.outputPayload!.length > 50) {
      print('First 50 chars of payload: \${step.outputPayload!.substring(0, 50)}');
    }
  }
}
