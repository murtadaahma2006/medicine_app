import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/src/core/agent/ai_gateway.dart';
import 'package:medicine_app/src/core/agent/models/models.dart';
import 'package:medicine_app/src/core/agent/system_prompts.dart';

void main() {
  group('SystemPrompts & Multimodal AiGateway Tests', () {
    test('يسترجع المطالبات التوجيهية الصحيحة لكل تخصص سريري', () {
      final internalPrompt = SystemPrompts.getPromptForSpecialty('internal_medicine');
      final obgynPrompt = SystemPrompts.getPromptForSpecialty('obgyn');
      final surgeryPrompt = SystemPrompts.getPromptForSpecialty('surgery');

      expect(internalPrompt, contains('internal_medicine'));
      expect(internalPrompt, contains('الطب الباطني'));

      expect(obgynPrompt, contains('obgyn'));
      expect(obgynPrompt, contains('أمراض النساء والتوليد'));

      expect(surgeryPrompt, contains('surgery'));
      expect(surgeryPrompt, contains('الجراحة العامة'));
    });

    test('يدعم خريطة التخصصات الفرعية (Cardiology, Obstetrics, Orthopedics)', () {
      expect(SystemPrompts.getPromptForSpecialty('cardiology'), contains('internal_medicine'));
      expect(SystemPrompts.getPromptForSpecialty('obstetrics'), contains('obgyn'));
      expect(SystemPrompts.getPromptForSpecialty('orthopedics'), contains('surgery'));
    });

    test('AiGateway يمرر التخصص ومسار الملف متعدد الوسائط (Multimodal) إلى المعالج', () async {
      String? capturedPrompt;
      String? capturedPath;

      final gateway = AiGateway(
        maxRetries: 2,
        initialBackoff: const Duration(milliseconds: 1),
        apiCallHandler: (system, user, {filePath, fileBytes, provider}) async {
          capturedPrompt = system;
          capturedPath = filePath;
          return '{"status": "multimodal_ok"}';
        },
        sleepHandler: (_) {},
      );

      const step = AgentStep(
        id: 'mm-step-1',
        taskId: 'mm-task-1',
        sequenceIndex: 0,
        type: AgentStepType.extractConcepts,
      );

      final result = await gateway.executeStep(
        step,
        filePath: '/mock/storage/cardiology.pdf',
        specialty: 'cardiology',
      );

      expect(result.status, AgentStepStatus.done);
      expect(capturedPrompt, contains('internal_medicine'));
      expect(capturedPath, '/mock/storage/cardiology.pdf');
    });
  });
}
