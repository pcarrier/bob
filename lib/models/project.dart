enum TaskStatus {
  idle,
  running,
  success,
  failed,
}

class Project {
  final String name;
  final String path;
  final List<Task> tasks;

  Project({
    required this.name,
    required this.path,
    required this.tasks,
  });

  factory Project.fromPackageJson(String path, Map<String, dynamic> json) {
    final name = json['name'] as String? ?? 'Unnamed Project';
    final scripts = json['scripts'] as Map<String, dynamic>? ?? {};

    final tasks = scripts.entries
        .map((entry) => Task(
              name: entry.key,
              command: entry.value as String,
            ))
        .toList();

    return Project(
      name: name,
      path: path,
      tasks: tasks,
    );
  }
}

class Task {
  final String name;
  final String command;
  TaskStatus status;
  int? lastExitCode;

  Task({
    required this.name,
    required this.command,
    this.status = TaskStatus.idle,
    this.lastExitCode,
  });
}
