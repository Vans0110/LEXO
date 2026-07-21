import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/mobile/mobile_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await LexoBackgroundAudio.ensureInitialized();
  runLexoApp();
}
