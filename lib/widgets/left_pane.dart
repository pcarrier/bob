import 'package:flutter/material.dart';
import '../models/project.dart';

class LeftPane extends StatelessWidget {
  final List<Project> projects;
  final Project? selectedProject;
  final Task? selectedTask;
  final Function(Project) onProjectSelected;
  final VoidCallback onImportProject;
  final VoidCallback onCreateProject;
  final Function(Task) onTaskSelected;

  const LeftPane({
    super.key,
    required this.projects,
    required this.selectedProject,
    required this.selectedTask,
    required this.onProjectSelected,
    required this.onImportProject,
    required this.onCreateProject,
    required this.onTaskSelected,
  });

  IconData _getStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.idle:
        return Icons.play_circle_outline;
      case TaskStatus.running:
        return Icons.stop_circle_outlined;
      case TaskStatus.success:
        return Icons.check_circle_outline;
      case TaskStatus.failed:
        return Icons.error_outline;
    }
  }

  Color _getStatusColor(BuildContext context, TaskStatus status) {
    switch (status) {
      case TaskStatus.idle:
        return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
      case TaskStatus.running:
        return Theme.of(context).colorScheme.primary;
      case TaskStatus.success:
        return Colors.green;
      case TaskStatus.failed:
        return Theme.of(context).colorScheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Column(
        children: [
          // Projects section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROJECTS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onCreateProject,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Create'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onImportProject,
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: const Text('Import'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Projects list
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'No projects yet.\nCreate or import to get started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
            )
          else
            SizedBox(
              height: 120,
              child: ListView.builder(
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  final isSelected = project == selectedProject;

                  return ListTile(
                    selected: isSelected,
                    dense: true,
                    leading: Icon(
                      Icons.folder,
                      size: 20,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      project.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () => onProjectSelected(project),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          // Tasks section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text(
                  'TASKS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                ),
                if (selectedProject != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedProject!.name,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            overflow: TextOverflow.ellipsis,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: selectedProject == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Select a project\nto view tasks',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                          ),
                        ],
                      ),
                    ),
                  )
                : selectedProject!.tasks.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            'No tasks in this project.\nAdd scripts to package.json.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: selectedProject!.tasks.length,
                        itemBuilder: (context, index) {
                          final task = selectedProject!.tasks[index];
                          final isSelected = task == selectedTask;

                          return ListTile(
                            selected: isSelected,
                            dense: true,
                            leading: Icon(
                              _getStatusIcon(task.status),
                              size: 20,
                              color: _getStatusColor(context, task.status),
                            ),
                            title: Text(
                              task.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: task.status != TaskStatus.idle
                                ? Text(
                                    task.status == TaskStatus.running
                                        ? 'Running...'
                                        : 'Exit: ${task.lastExitCode ?? 'N/A'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: 11,
                                        ),
                                  )
                                : null,
                            onTap: () => onTaskSelected(task),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
