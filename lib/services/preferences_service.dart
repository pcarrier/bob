import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import '../models/project.dart';

// Top-level functions for isolate execution
List<Project> _decodeProjects(String projectsJson) {
  try {
    final List<dynamic> decoded = jsonDecode(projectsJson) as List<dynamic>;
    return decoded
        .map((item) => Project.fromJson(item as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return [];
  }
}

String _encodeProjects(List<Map<String, dynamic>> projectsData) {
  return jsonEncode(projectsData);
}

class PreferencesService {
  static const String _parentDirectoryKey = 'parent_directory';
  static const String _projectsKey = 'projects';
  static const String _xmitApiKeyKey = 'xmit_api_key';

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<String> getParentDirectory() async {
    if (_prefs == null) {
      await initialize();
    }

    final savedDirectory = _prefs!.getString(_parentDirectoryKey);

    if (savedDirectory != null && savedDirectory.isNotEmpty) {
      return savedDirectory;
    }

    return await _getDefaultDocumentsDirectory();
  }

  Future<void> setParentDirectory(String directory) async {
    if (_prefs == null) {
      await initialize();
    }

    await _prefs!.setString(_parentDirectoryKey, directory);
  }

  Future<List<Project>> getProjects() async {
    if (_prefs == null) {
      await initialize();
    }

    final projectsJson = _prefs!.getString(_projectsKey);

    if (projectsJson == null || projectsJson.isEmpty) {
      return [];
    }

    // Decode JSON in a separate isolate to avoid blocking the UI
    return await compute(_decodeProjects, projectsJson);
  }

  Future<void> saveProjects(List<Project> projects) async {
    if (_prefs == null) {
      await initialize();
    }

    // Encode JSON in a separate isolate to avoid blocking the UI
    final projectsData = projects.map((p) => p.toJson()).toList();
    final projectsJson = await compute(_encodeProjects, projectsData);
    await _prefs!.setString(_projectsKey, projectsJson);
  }


  Future<String?> getXmitApiKey() async {
    if (_prefs == null) {
      await initialize();
    }

    return _prefs!.getString(_xmitApiKeyKey);
  }

  Future<void> setXmitApiKey(String apiKey) async {
    if (_prefs == null) {
      await initialize();
    }

    await _prefs!.setString(_xmitApiKeyKey, apiKey);
  }

  Future<String> _getDefaultDocumentsDirectory() async {
    try {
      if (Platform.isWindows) {
        final documentsDir = await getApplicationDocumentsDirectory();
        return documentsDir.path;
      } else if (Platform.isMacOS) {
        final homeDir = Platform.environment['HOME'];
        if (homeDir != null) {
          return path.join(homeDir, 'Documents');
        }
      } else if (Platform.isLinux) {
        final homeDir = Platform.environment['HOME'];
        if (homeDir != null) {
          return path.join(homeDir, 'Documents');
        }
      }

      // Fallback to application documents directory
      final documentsDir = await getApplicationDocumentsDirectory();
      return documentsDir.path;
    } catch (e) {
      // Last resort fallback to current directory
      return Directory.current.path;
    }
  }
}