import 'package:flutter_test/flutter_test.dart';
import 'package:virgil/src/workbench/virgil_workbench_paths.dart';

void main() {
  test('workbench paths resolve from the workspace root', () {
    expect(
      VirgilWorkbenchPaths.books.path.replaceAll('\\', '/'),
      endsWith('/Studio/Workbench/Books'),
    );
    expect(
      VirgilWorkbenchPaths.output.path.replaceAll('\\', '/'),
      endsWith('/Studio/Runtime/workbench_output'),
    );
    expect(
      VirgilWorkbenchPaths.cloudLibrary.path.replaceAll('\\', '/'),
      endsWith('/Studio/CloudLibrary'),
    );
  });
}
