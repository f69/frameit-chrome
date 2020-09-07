import 'dart:io';

import 'package:framechrome/frameit_frame.dart';
import 'package:image/image.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:quiver/check.dart';

final _logger = Logger('process_screenshots');

class FrameProcess {
  FrameProcess({@required this.chromeBinary, @required this.framesProvider});

  final String chromeBinary;
  final FramesProvider framesProvider;

  String rewriteScreenshotName(String name) {
    if (name.contains('framed')) {
      return null;
    }
    return name.replaceAll('samsung-galaxy-s10-plus', 'samsung-galaxy-s10');
  }

  Future<void> processScreenshots(
    Directory dir,
    Directory outDir,
    Map<String, String> titleStrings,
    Map<String, String> keywordStrings,
  ) async {
    checkArgument(dir.existsSync(), message: 'Dir does not exist $dir');
    _logger.info('Processing images in $dir');
    await for (final fileEntity in dir.list(recursive: true)) {
      if (fileEntity is! File) {
        continue;
      }
      final file = fileEntity as File;

      final image = decodeImage(await file.readAsBytes());

      final name =
          rewriteScreenshotName(path.basenameWithoutExtension(file.path));
      if (name == null) {
        continue;
      }
      final outFilePath =
          path.join(outDir.path, path.relative(file.path, from: dir.path));
      await File(outFilePath).parent.create(recursive: true);

      // final outFile = path.join(file.parent.path,
      //     '{path.basenameWithoutExtension(file.path)}_framed.png');

      // find title and keyword
      final title = _findString(titleStrings, name);
      final keyword = _findString(keywordStrings, name);
      if (title == null) {
        continue;
      }
      final frame = framesProvider.frameForScreenshot(name);
      _logger.fine('Rendering $name with title: $title ($keyword) and $frame');

      final css = await _createCss(
        frame,
        image.width,
        image.height,
        title: title,
        keyword: keyword,
      );
      final indexHtml = File('index.html');
      final cssFile = File('index_override.css');
      final screenshotFile = File('screenshot.png');
      await screenshotFile.delete();
      if (!indexHtml.existsSync()) {
        throw StateError('Expected index.html to be in the current directory.');
      }
      await cssFile.writeAsString(css);
      final runStopwatch = Stopwatch()..start();
      final result = await Process.run(chromeBinary, [
        '--headless',
        '--no-sandbox',
        '--screenshot',
        '--hide-scrollbars',
        '--window-size=${image.width},${image.height}',
        'index.html',
      ]);
      if (result.exitCode != 0) {
        throw StateError(
            'Chrome headless did not succeed. ${result.exitCode}: $result');
      }
      await screenshotFile.copy(outFilePath);

      _logger.info('Created (${runStopwatch.elapsedMilliseconds}ms) '
          '$outFilePath');
    }
  }

  Future<String> _createCss(Frame frame, int targetWidth, int targetHeight,
      {String title, String keyword}) async {
    final image = decodeImage(await frame.image.readAsBytes());
    final w = image.width;
    final h = image.height;
    return '''
:root {
  --frame-orig-width: $w;
  --frame-orig-height: $h;

  --frame-orig-offset-x: ${frame.offsetX};
  --frame-orig-offset-y: ${frame.offsetY};

  --target-width: $targetWidth;
  --target-height: $targetHeight;
}
.title:before {
    content: '$title';
}
''';
  }

  String _findString(Map<String, String> strings, String filename) {
    for (final entry in strings.entries) {
      if (filename.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}
