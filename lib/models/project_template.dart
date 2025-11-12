enum ProjectType {
  defaultType('Default', 'Basic Node.js project'),
  eleventy('11ty', 'Eleventy static site generator');

  final String displayName;
  final String description;

  const ProjectType(this.displayName, this.description);
}

class ProjectTemplate {
  final ProjectType type;

  ProjectTemplate(this.type);

  Map<String, dynamic> generatePackageJson(String projectName) {
    switch (type) {
      case ProjectType.defaultType:
        return {
          'name': projectName,
          'version': '1.0.0',
          'description': '',
          'main': 'index.js',
          'scripts': {
            'start': 'node index.js',
            'test': 'echo "Error: no test specified" && exit 1',
          },
          'keywords': [],
          'author': '',
          'license': 'ISC',
        };

      case ProjectType.eleventy:
        return {
          'name': projectName,
          'version': '1.0.0',
          'description': 'An Eleventy static site',
          'scripts': {
            'build': 'eleventy',
            'start': 'eleventy --serve',
            'watch': 'eleventy --watch',
            'debug': 'DEBUG=Eleventy* eleventy',
          },
          'devDependencies': {
            '@11ty/eleventy': '^2.0.0',
          },
          'keywords': ['eleventy', 'static-site'],
          'author': '',
          'license': 'MIT',
        };
    }
  }
}
