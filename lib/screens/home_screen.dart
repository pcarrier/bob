import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/project_service.dart';
import '../widgets/left_pane.dart';
import '../widgets/right_pane.dart';
import '../widgets/project_creation_form.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ProjectService _projectService = ProjectService();
  final List<Project> _projects = [];
  Project? _selectedProject;
  Task? _selectedTask;
  bool _showingCreationForm = false;

  void _addProject(Project project) {
    setState(() {
      _projects.add(project);
      _selectedProject = project;
      _showingCreationForm = false;
    });
  }

  void _selectProject(Project project) {
    setState(() {
      _selectedProject = project;
      _selectedTask = null;
      _showingCreationForm = false;
    });
  }

  void _selectTask(Task task) {
    setState(() {
      _selectedTask = task;
      _showingCreationForm = false;
    });
  }

  Future<void> _handleImportProject() async {
    final result = await _projectService.importProject();

    if (!mounted) return;

    if (result.isSuccess) {
      _addProject(result.data!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _showCreationForm() {
    setState(() {
      _showingCreationForm = true;
      _selectedTask = null;
    });
  }

  void _hideCreationForm() {
    setState(() {
      _showingCreationForm = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Oncle Bob'),
        elevation: 2,
      ),
      body: Row(
        children: [
          LeftPane(
            projects: _projects,
            selectedProject: _selectedProject,
            selectedTask: _selectedTask,
            onProjectSelected: _selectProject,
            onImportProject: _handleImportProject,
            onCreateProject: _showCreationForm,
            onTaskSelected: _selectTask,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: RightPane(
              selectedTask: _selectedTask,
              customContent: _showingCreationForm
                  ? ProjectCreationForm(
                      projectService: _projectService,
                      onProjectCreated: (project) => _addProject(project),
                      onCancel: _hideCreationForm,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
