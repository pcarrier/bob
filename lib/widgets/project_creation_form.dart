import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/project_template.dart';
import '../services/project_service.dart';

class ProjectCreationForm extends StatefulWidget {
  final ProjectService projectService;
  final Function(dynamic) onProjectCreated;
  final VoidCallback onCancel;

  const ProjectCreationForm({
    super.key,
    required this.projectService,
    required this.onProjectCreated,
    required this.onCancel,
  });

  @override
  State<ProjectCreationForm> createState() => _ProjectCreationFormState();
}

class _ProjectCreationFormState extends State<ProjectCreationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  ProjectType _selectedType = ProjectType.defaultType;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _selectLocation() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select parent directory',
    );

    if (result != null) {
      setState(() {
        _locationController.text = result;
      });
    }
  }

  Future<void> _createProject() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    final result = await widget.projectService.createProject(
      projectName: _nameController.text,
      parentDirectory: _locationController.text,
      projectType: _selectedType,
    );

    if (!mounted) return;

    setState(() {
      _isCreating = false;
    });

    if (result.isSuccess) {
      widget.onProjectCreated(result.data!);
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.create_new_folder,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Text(
                  'Create New Project',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onCancel,
                ),
              ],
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                hintText: 'my-project',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a project name';
                }
                if (!RegExp(r'^[a-z0-9-_]+$').hasMatch(value)) {
                  return 'Use lowercase letters, numbers, hyphens, and underscores only';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: 'Parent Directory',
                hintText: 'Choose where to create the project',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.folder),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _selectLocation,
                ),
              ),
              readOnly: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a parent directory';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Project Type',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            RadioGroup<ProjectType>(
              onChanged: (value) {
                setState(() {
                  _selectedType = value!;
                });
              },
              child: Column(
                children: ProjectType.values.map((type) {
                  return Card(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedType = type;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Radio<ProjectType>(
                              value: type,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    type.displayName,
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    type.description,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isCreating ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isCreating ? null : _createProject,
                  icon: _isCreating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isCreating ? 'Creating...' : 'Create Project'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
