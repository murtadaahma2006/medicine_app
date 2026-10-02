import 'package:flutter/material.dart';

import '../../../../core/agent/models/models.dart';
import '../../../../core/agent/task_repository.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/tokens.dart';

class AiTaskHistoryPage extends StatefulWidget {
  const AiTaskHistoryPage({super.key, required this.repository});
  final TaskRepository repository;

  @override
  State<AiTaskHistoryPage> createState() => _AiTaskHistoryPageState();
}

class _AiTaskHistoryPageState extends State<AiTaskHistoryPage> {
  Future<void> _confirmDelete(BuildContext context, AgentTask task) async {
    // إذا كانت مكتملة وتم استيرادها (done)
    if (task.status == AgentTaskStatus.done) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف سجل العملية'),
          content: const Text(
            'هذه العملية مكتملة وتم استيرادها بنجاح.\nحذف هذا السجل سيحذفه من قائمة العمليات فقط، ولن يحذف المحاضرة من التطبيق. هل تريد الاستمرار؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف السجل'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await widget.repository.deleteTask(task.id);
      }
    } 
    // إذا كانت مكتملة ولكن قيد الموافقة (لم يتم استيرادها)
    else if (task.status == AgentTaskStatus.pendingApproval) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف المحاضرة المعلقة'),
          content: const Text(
            'هذه المحاضرة مكتملة وبانتظار اعتمادك. إذا حذفتها الآن ستفقد المحتوى الذي تم توليده بالكامل ولن تتمكن من استيراده. هل أنت متأكد من الحذف؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف نهائياً'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await widget.repository.deleteTask(task.id);
      }
    }
    // لأي حالة أخرى (running, paused, failed, queued)
    else {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف المهمة'),
          content: const Text(
            'هل أنت متأكد أنك تريد حذف هذه المهمة من السجل بشكل نهائي؟ سيتوقف أي عمل قيد التنفيذ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await widget.repository.deleteTask(task.id);
      }
    }
  }

  Color _getStatusColor(AgentTaskStatus status, Brightness b) {
    switch (status) {
      case AgentTaskStatus.done:
        return AppColors.success(b);
      case AgentTaskStatus.failed:
        return AppColors.error(b);
      case AgentTaskStatus.running:
      case AgentTaskStatus.queued:
        return AppColors.primary(b);
      case AgentTaskStatus.paused:
        return AppColors.gold(b);
      case AgentTaskStatus.pendingApproval:
        return Colors.teal;
    }
  }

  String _getStatusLabel(AgentTaskStatus status) {
    switch (status) {
      case AgentTaskStatus.done:
        return 'مكتمل ومستورد';
      case AgentTaskStatus.failed:
        return 'فشل';
      case AgentTaskStatus.running:
        return 'قيد المعالجة';
      case AgentTaskStatus.queued:
        return 'في الانتظار';
      case AgentTaskStatus.paused:
        return 'متوقف مؤقتاً';
      case AgentTaskStatus.pendingApproval:
        return 'بانتظار الاعتماد';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;

    return Scaffold(
      backgroundColor: AppColors.background(b),
      appBar: AppBar(
        title: Text(
          'سجل عمليات الذكاء الاصطناعي',
          style: AppType.screenTitle.copyWith(
            fontSize: 20,
            color: AppColors.text(b),
          ),
        ),
        backgroundColor: AppColors.surface(b),
        elevation: 0,
        centerTitle: false,
      ),
      body: StreamBuilder<List<AgentTask>>(
        stream: widget.repository.watchTasks(),
        initialData: const <AgentTask>[],
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<AgentTask> tasks = snapshot.data ?? <AgentTask>[];

          if (tasks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: EmptyState(
                  icon: Icons.history_rounded,
                  title: 'السجل فارغ',
                  subtitle: 'لم تقم بأي عمليات لصناعة المحتوى حتى الآن.',
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final task = tasks[index];
              final statusColor = _getStatusColor(task.status, b);
              final statusLabel = _getStatusLabel(task.status);

              return AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    task.title,
                    style: AppType.cardTitle.copyWith(
                      color: AppColors.text(b),
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'الملف: ${task.filePath.split("/").last}',
                        style: AppType.caption.copyWith(color: AppColors.textSecondary(b)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'التاريخ: ${task.createdAt.toLocal().toString().substring(0, 16)}',
                        style: AppType.caption.copyWith(color: AppColors.textSecondary(b)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                    tooltip: 'حذف من السجل',
                    onPressed: () => _confirmDelete(context, task),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
