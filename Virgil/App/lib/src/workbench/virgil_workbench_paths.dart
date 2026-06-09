import 'dart:io';

class VirgilWorkbenchPaths {
  VirgilWorkbenchPaths._();

  static const _configuredRoot = String.fromEnvironment(
    'VIRGIL_WORKSPACE_ROOT',
  );

  static String get workspaceRoot {
    if (_configuredRoot.trim().isNotEmpty) {
      return Directory(_configuredRoot).absolute.path;
    }
    return Directory.current.parent.parent.absolute.path;
  }

  static Directory get books =>
      Directory('$workspaceRoot/Studio/Workbench/Books');

  static Directory get output =>
      Directory('$workspaceRoot/Studio/Runtime/workbench_output');

  static Directory get cloudLibrary =>
      Directory('$workspaceRoot/Studio/CloudLibrary');
}
