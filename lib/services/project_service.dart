import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/project.dart';
import '../models/result.dart';
import '../models/project_template.dart';

class ProjectService {
  Future<Result<Project>> importProject() async {
    try {
      final directoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select project directory',
      );

      if (directoryPath == null) {
        return Result.failure('No directory selected');
      }

      final directory = Directory(directoryPath);

      if (!await directory.exists()) {
        return Result.failure('Directory does not exist: $directoryPath');
      }

      final packageJsonPath = path.join(directoryPath, 'package.json');
      final packageJsonFile = File(packageJsonPath);

      if (!await packageJsonFile.exists()) {
        // Create a default package.json
        final defaultPackageJson = {
          'name': path.basename(directoryPath),
          'version': '1.0.0',
          'description': '',
          'scripts': {},
        };

        await packageJsonFile.writeAsString(
          JsonEncoder.withIndent('  ').convert(defaultPackageJson)
        );
      }

      final content = await packageJsonFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final project = Project.fromPackageJson(directoryPath, json);

      return Result.success(project);
    } on FormatException catch (e) {
      return Result.failure('Invalid JSON format: ${e.message}');
    } on FileSystemException catch (e) {
      return Result.failure('File system error: ${e.message}');
    } catch (e) {
      return Result.failure('Failed to import project: ${e.toString()}');
    }
  }

  Future<Result<Project>> createProject({
    required String projectName,
    required String parentDirectory,
    required ProjectType projectType,
  }) async {
    try {
      final projectPath = path.join(parentDirectory, projectName);
      final directory = Directory(projectPath);

      if (await directory.exists()) {
        return Result.failure('Directory already exists: $projectPath');
      }

      await directory.create(recursive: true);

      final template = ProjectTemplate(projectType);
      final packageJson = template.generatePackageJson(projectName);

      final packageJsonPath = path.join(projectPath, 'package.json');
      final file = File(packageJsonPath);

      await file.writeAsString(
        JsonEncoder.withIndent('  ').convert(packageJson)
      );

      final project = Project.fromPackageJson(projectPath, packageJson);

      return Result.success(project);
    } on FileSystemException catch (e) {
      return Result.failure('File system error: ${e.message}');
    } catch (e) {
      return Result.failure('Failed to create project: ${e.toString()}');
    }
  }

  Future<List<Project>> scanDirectory(String directoryPath) async {
    final projects = <Project>[];
    final directory = Directory(directoryPath);

    if (!await directory.exists()) {
      return projects;
    }

    try {
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File && path.basename(entity.path) == 'package.json') {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final projectPath = path.dirname(entity.path);
            projects.add(Project.fromPackageJson(projectPath, json));
          } catch (e) {
            // Skip invalid package.json files
          }
        }
      }
    } catch (e) {
      // Return partial results if directory scan fails
    }

    return projects;
  }
}
