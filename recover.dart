import 'dart:io';

void main() {
  final file = File(r'C:\Users\Murtada A. Shawi\.gemini\antigravity-ide\brain\42eeae8c-4657-481e-8fbe-e538c5dc6cbf\.system_generated\logs\transcript.jsonl');
  final lines = file.readAsLinesSync();
  int count = 0;
  for (final line in lines) {
    if (line.contains('agent_runtime.dart')) {
      print(line.substring(0, line.length < 200 ? line.length : 200));
      print('===');
      count++;
      if (count > 5) break;
    }
  }
}
