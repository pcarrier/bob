import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../config/constants.dart';
import '../models/project.dart';
import '../models/project_template.dart';
import '../services/preferences_service.dart';
import '../services/project_service.dart';
import '../services/task_service.dart';
import '../services/launch_service.dart';
import '../utils/circular_buffer.dart';
import '../utils/task_utils.dart';

class ProjectProvider with ChangeNotifier {
  final ProjectService _projectService = ProjectService();
  final PreferencesService _preferencesService = PreferencesService();
  final TaskService _taskService = TaskService();
  final LaunchService _launchService = LaunchService();

  List<Project> _projects = [];
  Task? _selectedTask;
  Site? _selectedLaunch;
  bool _showingCreationForm = false;
  Project? _configuringProject;
  Project? _creatingLaunchFor;
  bool _showingSettings = false;
  double _leftPaneWidth = AppConstants.leftPaneDefaultWidth;
  bool _isLoadingProjects = true;

  // Circular buffers for task output to prevent memory issues
  final Map<String, CircularBuffer> _taskOutputBuffers = {};

  // Track projects currently being removed to prevent concurrent removal
  final Set<String> _projectsBeingRemoved = {};

  // Track projects currently being added to prevent concurrent addition
  final Set<String> _projectsBeingAdded = {};

  // File watchers for package.json changes
  final Map<String, StreamSubscription<FileSystemEvent>> _packageJsonWatchers = {};

  // Team selection state for launch
  Completer<TeamSelectionResult>? _pendingTeamSelection;
  List<Team> _availableTeams = [];
  String _teamManageUrl = 'https://xmit.co/admin';

  // Settings context
  String? _settingsBannerMessage;

  List<Project> get projects => _projects;
  Task? get selectedTask => _selectedTask;
  Site? get selectedLaunch => _selectedLaunch;
  bool get showingCreationForm => _showingCreationForm;
  Project? get configuringProject => _configuringProject;
  Project? get creatingLaunchFor => _creatingLaunchFor;
  bool get showingSettings => _showingSettings;
  double get leftPaneWidth => _leftPaneWidth;
  bool get isLoadingProjects => _isLoadingProjects;
  Set<String> get projectsBeingImported => _projectsBeingAdded;
  String? get settingsBannerMessage => _settingsBannerMessage;
  PreferencesService get preferencesService => _preferencesService;

  // Team selection getters
  bool get isWaitingForTeamSelection => _pendingTeamSelection != null;
  List<Team> get availableTeams => _availableTeams;
  String get teamManageUrl => _teamManageUrl;

  ProjectProvider() {
    loadProjects();
  }

  Future<void> loadProjects() async {
    _isLoadingProjects = true;
    notifyListeners();

    final savedProjects = await _preferencesService.getProjects();

    final loadedProjects = <Project>[];
    for (final project in savedProjects) {
      final result = await _projectService.reloadProject(project);
      if (result.isSuccess) {
        loadedProjects.add(result.data!);
        // Start watching package.json for this project
        _startWatchingPackageJson(result.data!);
      }
    }

    _projects = loadedProjects;
    _isLoadingProjects = false;
    notifyListeners();
  }

  Future<void> _saveProjects() async {
    await _preferencesService.saveProjects(_projects);
  }

  void _startWatchingPackageJson(Project project) {
    // Don't watch if already watching
    if (_packageJsonWatchers.containsKey(project.path)) {
      return;
    }

    final packageJsonPath = path.join(project.path, 'package.json');
    final packageJsonFile = File(packageJsonPath);

    // Only watch if package.json exists
    if (!packageJsonFile.existsSync()) {
      return;
    }

    // Watch the project directory instead of the file itself
    // This catches all editor save strategies (direct write, temp + rename, delete + create)
    final projectDir = Directory(project.path);
    final watcher = projectDir.watch(events: FileSystemEvent.all, recursive: false);
    final subscription = watcher.listen((event) async {
      // Only react to package.json changes - normalize path for comparison
      final eventPath = path.normalize(event.path);
      final expectedPath = path.normalize(packageJsonPath);

      if (eventPath != expectedPath) {
        return;
      }

      // Debounce: ignore delete events as they're often followed by create
      if (event.type == FileSystemEvent.delete) {
        return;
      }

      // Reload the project when package.json changes
      await _reloadProjectFromPath(project.path);
    }, onError: (error) {
      // Silently ignore watcher errors
    });

    _packageJsonWatchers[project.path] = subscription;
  }

  void _stopWatchingPackageJson(Project project) {
    final subscription = _packageJsonWatchers.remove(project.path);
    subscription?.cancel();
  }

  Future<void> _reloadProjectFromPath(String projectPath) async {
    final projectIndex = _projects.indexWhere((p) => p.path == projectPath);
    if (projectIndex == -1) {
      return; // Project not found
    }

    final project = _projects[projectIndex];
    final result = await _projectService.reloadProject(project);
    if (result.isSuccess) {
      // Update the project in the list
      _projects = [
        ..._projects.sublist(0, projectIndex),
        result.data!,
        ..._projects.sublist(projectIndex + 1),
      ];
      notifyListeners();
    }
  }

  void addProject(Project project) {
    // Check if this project is already being added or already exists
    if (_projectsBeingAdded.contains(project.path) ||
        _projects.any((p) => p.path == project.path)) {
      return; // Skip if already being added or already exists
    }

    // Mark project as being added
    _projectsBeingAdded.add(project.path);

    try {
      // Create new list instance to trigger Selector rebuild
      _projects = [project, ..._projects];
      _showingCreationForm = false;

      // Start watching package.json for this project
      _startWatchingPackageJson(project);

      notifyListeners();
      _saveProjects();
    } finally {
      // Always remove the lock
      _projectsBeingAdded.remove(project.path);
    }
  }

  Future<void> createAndAddProject({
    required String projectName,
    required String parentDirectory,
    required ProjectType projectType,
  }) async {
    final projectPath = path.normalize(path.join(parentDirectory, projectName));

    // Check if this project is already being added or already exists
    if (_projectsBeingAdded.contains(projectPath) ||
        _projects.any((p) => p.path == projectPath)) {
      return;
    }

    // Mark project as being added
    _projectsBeingAdded.add(projectPath);

    try {
      // Create a stub project with a "create" task
      final createTask = Task(
        name: 'create',
        command: 'Creating ${projectType.displayName} project...',
        type: TaskType.create,
        status: TaskStatus.running,
      );

      final stubProject = Project(
        name: projectName,
        path: projectPath,
        tasks: [createTask],
      );

      // Add stub project to list immediately
      _projects = [stubProject, ..._projects];
      _selectedTask = createTask;
      _selectedLaunch = null;
      _showingCreationForm = false;
      notifyListeners();

      // Clear buffer for create task
      _clearBuffer(stubProject, createTask);

      // Start the actual creation process
      final result = await _projectService.createProject(
        projectName: projectName,
        parentDirectory: parentDirectory,
        projectType: projectType,
        onOutput: (output) {
          // Use circular buffer to prevent unlimited memory growth
          final buffer = _getOrCreateBuffer(stubProject, createTask);
          buffer.append(output);

          // Find the stub project in the list (it may have moved)
          final projectIndex = _projects.indexWhere((p) => p.path == projectPath);
          if (projectIndex != -1) {
            final currentProject = _projects[projectIndex];
            final taskInList = currentProject.tasks.firstWhere((t) => t.name == 'create');
            final updatedTask = taskInList.copyWith(
              output: buffer.content,
            );
            _updateTask(currentProject, taskInList, updatedTask);
            notifyListeners();
          }
        },
      );

      // Find the stub project in the list
      final projectIndex = _projects.indexWhere((p) => p.path == projectPath);
      if (projectIndex == -1) return; // Project was removed during creation

      if (result.isSuccess) {
        // Replace stub project with real project
        _projects = [
          ..._projects.sublist(0, projectIndex),
          result.data!,
          ..._projects.sublist(projectIndex + 1),
        ];
        _selectedTask = null;
        notifyListeners();
        _saveProjects();
      } else {
        // Mark create task as failed
        final currentProject = _projects[projectIndex];
        final taskInList = currentProject.tasks.firstWhere((t) => t.name == 'create');
        final buffer = _getOrCreateBuffer(currentProject, taskInList);
        buffer.append('\n\nError: ${result.error}\n');

        final updatedTask = taskInList.copyWith(
          status: TaskStatus.failed,
          lastExitCode: 1,
          output: buffer.content,
        );

        final updatedProject = Project(
          name: currentProject.name,
          path: currentProject.path,
          tasks: [updatedTask],
        );

        _projects = [
          ..._projects.sublist(0, projectIndex),
          updatedProject,
          ..._projects.sublist(projectIndex + 1),
        ];

        _updateTask(currentProject, taskInList, updatedTask);
        notifyListeners();
      }
    } finally {
      _projectsBeingAdded.remove(projectPath);
    }
  }

  Future<void> retryCreateProject(Project project) async {
    // Verify this is a failed creation task
    final createTask = project.tasks.firstWhere(
      (t) => t.type == TaskType.create,
      orElse: () => throw StateError('No create task found'),
    );

    if (createTask.status != TaskStatus.failed) {
      return; // Only retry failed tasks
    }

    // Reset task to running
    _clearBuffer(project, createTask);
    final runningTask = createTask.copyWith(
      status: TaskStatus.running,
      output: '',
      lastExitCode: null,
    );

    final updatedProject = Project(
      name: project.name,
      path: project.path,
      tasks: [runningTask],
    );

    final projectIndex = _projects.indexWhere((p) => p.path == project.path);
    if (projectIndex == -1) return;

    _projects = [
      ..._projects.sublist(0, projectIndex),
      updatedProject,
      ..._projects.sublist(projectIndex + 1),
    ];

    _selectedTask = runningTask;
    notifyListeners();

    // Determine project type from the failed attempt (default to defaultType)
    // We could store this in the task command or project metadata in future
    final projectType = ProjectType.defaultType;

    final result = await _projectService.createProject(
      projectName: project.name,
      parentDirectory: path.dirname(project.path),
      projectType: projectType,
      onOutput: (output) {
        final buffer = _getOrCreateBuffer(updatedProject, runningTask);
        buffer.append(output);

        final currentProjectIndex = _projects.indexWhere((p) => p.path == project.path);
        if (currentProjectIndex != -1) {
          final currentProject = _projects[currentProjectIndex];
          final taskInList = currentProject.tasks.firstWhere((t) => t.name == 'create');
          final updatedTask = taskInList.copyWith(
            output: buffer.content,
          );
          _updateTask(currentProject, taskInList, updatedTask);
          notifyListeners();
        }
      },
    );

    final finalProjectIndex = _projects.indexWhere((p) => p.path == project.path);
    if (finalProjectIndex == -1) return;

    if (result.isSuccess) {
      // Replace with real project
      _projects = [
        ..._projects.sublist(0, finalProjectIndex),
        result.data!,
        ..._projects.sublist(finalProjectIndex + 1),
      ];
      _selectedTask = null;
      notifyListeners();
      _saveProjects();
    } else {
      // Mark as failed again
      final currentProject = _projects[finalProjectIndex];
      final taskInList = currentProject.tasks.firstWhere((t) => t.name == 'create');
      final buffer = _getOrCreateBuffer(currentProject, taskInList);
      buffer.append('\n\nError: ${result.error}\n');

      final failedTask = taskInList.copyWith(
        status: TaskStatus.failed,
        lastExitCode: 1,
        output: buffer.content,
      );

      final failedProject = Project(
        name: currentProject.name,
        path: currentProject.path,
        tasks: [failedTask],
      );

      _projects = [
        ..._projects.sublist(0, finalProjectIndex),
        failedProject,
        ..._projects.sublist(finalProjectIndex + 1),
      ];

      _updateTask(currentProject, taskInList, failedTask);
      notifyListeners();
    }
  }

  void reorderProjects(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    // Create new list instance to trigger Selector rebuild
    final updatedProjects = List<Project>.from(_projects);
    final project = updatedProjects.removeAt(oldIndex);
    updatedProjects.insert(newIndex, project);
    _projects = updatedProjects;

    // Only notify and save if the order actually changed
    if (oldIndex != newIndex) {
      notifyListeners();
      _saveProjects();
    }
  }

  Future<void> removeProject(Project project) async {
    // Check if this project is already being removed
    if (_projectsBeingRemoved.contains(project.path)) {
      return; // Skip if already being removed
    }

    // Mark project as being removed
    _projectsBeingRemoved.add(project.path);

    try {
      // Stop all running tasks for this project before removing
      final stopFutures = <Future<void>>[];
      for (final task in project.tasks) {
        if (_taskService.isTaskRunning(project, task)) {
          stopFutures.add(_taskService.stopTask(project, task));
        }
      }

      // Stop all running launchs for this project
      for (final target in project.sites) {
        if (target.status == TaskStatus.running) {
          final launchId = '${project.path}:${target.name}';
          _launchService.cancelLaunch(launchId);
        }
      }

      // Cancel any pending team selection
      if (_pendingTeamSelection != null && !_pendingTeamSelection!.isCompleted) {
        cancelTeamSelection();
      }

      await Future.wait(stopFutures);

      // Stop watching package.json for this project
      _stopWatchingPackageJson(project);

      // Clear all buffers for this project
      _clearProjectBuffers(project);

      // Create new list instance to trigger Selector rebuild
      _projects = _projects.where((p) => p != project).toList();
      // Clear selected task if it belongs to the removed project
      if (_selectedTask != null && project.tasks.contains(_selectedTask)) {
        _selectedTask = null;
      }
      // Clear selected launch if it belongs to the removed project
      if (_selectedLaunch != null && project.sites.contains(_selectedLaunch)) {
        _selectedLaunch = null;
      }
      notifyListeners();
      await _saveProjects();
    } finally {
      // Always remove the lock, even if there was an error
      _projectsBeingRemoved.remove(project.path);
    }
  }

  void selectTask(Task task) {
    _selectedTask = task;
    _selectedLaunch = null;
    _showingCreationForm = false;
    _configuringProject = null;
    _showingSettings = false;
    notifyListeners();
  }

  void selectLaunch(Site launch) {
    _selectedLaunch = launch;
    _selectedTask = null;
    _showingCreationForm = false;
    _configuringProject = null;
    _showingSettings = false;
    notifyListeners();
  }

  void showCreationForm() {
    _showingCreationForm = true;
    _selectedTask = null;
    _selectedLaunch = null;
    _configuringProject = null;
    _showingSettings = false;
    notifyListeners();
  }

  void hideCreationForm() {
    _showingCreationForm = false;
    notifyListeners();
  }

  void showProjectConfiguration(Project project) {
    _configuringProject = project;
    _selectedTask = null;
    _selectedLaunch = null;
    _showingCreationForm = false;
    _showingSettings = false;
    notifyListeners();
  }

  void hideProjectConfiguration() {
    _configuringProject = null;
    notifyListeners();
  }

  void showSettings({String? bannerMessage}) {
    _showingSettings = true;
    _settingsBannerMessage = bannerMessage;
    _selectedTask = null;
    _selectedLaunch = null;
    _showingCreationForm = false;
    _configuringProject = null;
    notifyListeners();
  }

  void hideSettings() {
    _settingsBannerMessage = null;
    _showingSettings = false;
    notifyListeners();
  }

  void showLaunchCreation(Project project) {
    _creatingLaunchFor = project;
    _selectedTask = null;
    _selectedLaunch = null;
    _showingCreationForm = false;
    _configuringProject = null;
    _showingSettings = false;
    notifyListeners();
  }

  void hideLaunchCreation() {
    _creatingLaunchFor = null;
    notifyListeners();
  }

  void updateProjectAfterLaunchCreation(Project updatedProject) {
    final index = _projects.indexWhere((p) => p.path == updatedProject.path);
    if (index != -1) {
      // Create new list instance to trigger Selector rebuild
      _projects = [
        ..._projects.sublist(0, index),
        updatedProject,
        ..._projects.sublist(index + 1),
      ];
      _creatingLaunchFor = null;
      // Auto-select the newly created site
      if (updatedProject.sites.isNotEmpty) {
        _selectedLaunch = updatedProject.sites.last;
        _selectedTask = null;
        // Auto-start the launch
        toggleLaunch(updatedProject, updatedProject.sites.last);
      }
      notifyListeners();
      _saveProjects();
    }
  }

  void updateProjectAfterConfiguration(Project updatedProject) {
    final index = _projects.indexWhere((p) => p.path == updatedProject.path);
    if (index != -1) {
      // Create new list instance to trigger Selector rebuild
      _projects = [
        ..._projects.sublist(0, index),
        updatedProject,
        ..._projects.sublist(index + 1),
      ];
      _configuringProject = null;
      notifyListeners();
      _saveProjects();
    }
  }

  void setLeftPaneWidth(double width, double windowWidth) {
    // Ensure left pane is at least leftMinPaneWidth
    // Ensure right pane is at least rightMinPaneWidth (so left pane max is windowWidth - rightMinPaneWidth - separator)
    final minWidth = AppConstants.leftMinPaneWidth;
    final maxWidth = windowWidth - AppConstants.rightMinPaneWidth - AppConstants.paneSeparatorWidth;

    // Ensure maxWidth is at least minWidth to avoid clamp errors
    final safeMaxWidth = maxWidth < minWidth ? minWidth : maxWidth;
    _leftPaneWidth = width.clamp(minWidth, safeMaxWidth);
    notifyListeners();
  }

  /// Gets or creates a circular buffer for a task
  CircularBuffer _getOrCreateBuffer(Project project, Task task) {
    final key = TaskUtils.getTaskKey(project, task);
    return _taskOutputBuffers.putIfAbsent(key, () => CircularBuffer());
  }

  /// Clears the buffer for a task
  void _clearBuffer(Project project, Task task) {
    final key = TaskUtils.getTaskKey(project, task);
    _taskOutputBuffers[key]?.clear();
  }

  /// Removes all buffers for a project
  void _clearProjectBuffers(Project project) {
    _taskOutputBuffers.removeWhere((key, _) => key.startsWith('${project.path}:'));
  }

  void _updateTask(Project project, Task oldTask, Task newTask) {
    final index = project.tasks.indexOf(oldTask);
    if (index != -1) {
      project.tasks[index] = newTask;
      // Update selectedTask reference if it's the same task
      if (_selectedTask == oldTask) {
        _selectedTask = newTask;
      }
    }
  }

  Future<void> toggleTask(Project project, Task task) async {
    // Handle create tasks specially - they use retryCreateProject
    if (task.type == TaskType.create) {
      if (task.status == TaskStatus.failed) {
        await retryCreateProject(project);
      }
      // Ignore clicks on running create tasks
      return;
    }

    if (_taskService.isTaskRunning(project, task)) {
      // Stop the task - status will be updated in onExit callback
      await _taskService.stopTask(project, task);
    } else {
      // Start the task - clear buffer and reset output
      _clearBuffer(project, task);
      Task currentTask = task;
      final updatedTask = task.copyWith(
        status: TaskStatus.running,
        output: '',
        lastExitCode: null,
      );
      _updateTask(project, task, updatedTask);
      currentTask = updatedTask;

      // Focus the task when starting
      _selectedTask = currentTask;
      _selectedLaunch = null;
      _showingCreationForm = false;
      _configuringProject = null;
      _creatingLaunchFor = null;
      _showingSettings = false;

      notifyListeners();

      _taskService.startTask(
        project,
        currentTask,
        (output) {
          // Use circular buffer to prevent unlimited memory growth
          final buffer = _getOrCreateBuffer(project, currentTask);
          buffer.append(output);

          final taskInList =
              project.tasks.firstWhere((t) => t.name == currentTask.name);
          final updatedTask = taskInList.copyWith(
            output: buffer.content,
          );
          _updateTask(project, taskInList, updatedTask);
          notifyListeners();
        },
        (exitCode) async {
          final taskInList =
              project.tasks.firstWhere((t) => t.name == currentTask.name);

          // Check if task was explicitly stopped by user
          final wasStopped = _taskService.wasTaskExplicitlyStopped(project, taskInList);

          final updatedTask = taskInList.copyWith(
            status: wasStopped
                ? TaskStatus.idle // User stopped it, return to idle
                : (exitCode == 0 ? TaskStatus.success : TaskStatus.failed),
            lastExitCode: wasStopped ? null : exitCode,
          );
          _updateTask(project, taskInList, updatedTask);
          notifyListeners();

        },
      );
    }
  }

  void _updateLaunchTarget(Project project, Site oldTarget, Site newTarget) {
    final index = project.sites.indexOf(oldTarget);
    if (index != -1) {
      project.sites[index] = newTarget;
      // Update selectedLaunch reference if it's the same target
      if (_selectedLaunch == oldTarget) {
        _selectedLaunch = newTarget;
      }
    }
  }

  Future<void> toggleLaunch(Project project, Site target) async {
    if (target.status == TaskStatus.running) {
      // Stop the launch
      final launchId = '${project.path}:${target.name}';
      _launchService.cancelLaunch(launchId);

      // Cancel any pending team selection
      if (_pendingTeamSelection != null && !_pendingTeamSelection!.isCompleted) {
        cancelTeamSelection();
      }
      return;
    }

    // Get auth key from preferences
    final authKey = await _preferencesService.getXmitApiKey();

    if (authKey == null || authKey.isEmpty) {
      // Show settings if API key is not configured
      showSettings(bannerMessage: 'You need an Xmit API key to upload projects.');
      return;
    }

    // Start launch
    Site currentTarget = target;
    final updatedTarget = target.copyWith(
      status: TaskStatus.running,
      steps: [],
    );
    _updateLaunchTarget(project, target, updatedTarget);
    currentTarget = updatedTarget;

    // Focus the launch when starting
    _selectedLaunch = currentTarget;
    _selectedTask = null;
    _showingCreationForm = false;

    notifyListeners();

    final result = await _launchService.launch(
      projectPath: project.path,
      project: project,
      target: currentTarget,
      authKey: authKey,
      onStepUpdate: (step) {
        final targetInList = project.sites.firstWhere((t) => t.name == currentTarget.name);

        // Find existing step with same title or add new one
        final steps = List<LaunchStep>.from(targetInList.steps);
        final existingIndex = steps.indexWhere((s) => s.title == step.title);

        if (existingIndex != -1) {
          steps[existingIndex] = step;
        } else {
          steps.add(step);
        }

        final updatedTarget = targetInList.copyWith(steps: steps);
        _updateLaunchTarget(project, targetInList, updatedTarget);
        notifyListeners();
      },
      onTaskUpdate: (task) {
        // Update task in the list if it's the build task
        final taskInList = project.tasks.firstWhere((t) => t.name == task.name);
        if (taskInList != task) {
          _updateTask(project, taskInList, task);
          notifyListeners();
        }
      },
      onTeamSelectionRequired: (teamListResponse) async {
        // Store teams and management URL, then signal UI to show selection dialog
        _pendingTeamSelection = Completer<TeamSelectionResult>();
        _availableTeams = teamListResponse.teams;
        _teamManageUrl = teamListResponse.manageUrl;
        notifyListeners();

        // Wait for UI to complete the selection
        return await _pendingTeamSelection!.future;
      },
    );

    // Update final status
    final targetInList = project.sites.firstWhere((t) => t.name == currentTarget.name);
    final finalTarget = targetInList.copyWith(
      status: result.success ? TaskStatus.success : TaskStatus.failed,
    );
    _updateLaunchTarget(project, targetInList, finalTarget);
    notifyListeners();
  }

  /// Complete team selection with chosen team ID
  void completeTeamSelection(String teamId) {
    if (_pendingTeamSelection != null && !_pendingTeamSelection!.isCompleted) {
      _pendingTeamSelection!.complete(TeamSelected(teamId));
      _pendingTeamSelection = null;
      _availableTeams = [];
      notifyListeners();
    }
  }

  /// Cancel team selection
  void cancelTeamSelection() {
    if (_pendingTeamSelection != null && !_pendingTeamSelection!.isCompleted) {
      _pendingTeamSelection!.complete(const TeamSelectionCancelled());
      _pendingTeamSelection = null;
      _availableTeams = [];
      _teamManageUrl = 'https://xmit.co/admin';
      notifyListeners();
    }
  }

  /// Refresh team list
  void refreshTeamList() {
    if (_pendingTeamSelection != null && !_pendingTeamSelection!.isCompleted) {
      _pendingTeamSelection!.complete(const RefreshTeamList());
      _pendingTeamSelection = null;
      // Don't clear teams - will be refreshed
      notifyListeners();
    }
  }

  /// Request to create a new team
  void requestTeamCreation() {
    if (_pendingTeamSelection != null && !_pendingTeamSelection!.isCompleted) {
      _pendingTeamSelection!.complete(const CreateNewTeam());
      _pendingTeamSelection = null;
      // Don't clear teams yet
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _taskService.dispose();
    _taskOutputBuffers.clear();

    // Cancel all package.json watchers
    for (final subscription in _packageJsonWatchers.values) {
      subscription.cancel();
    }
    _packageJsonWatchers.clear();

    super.dispose();
  }
}
