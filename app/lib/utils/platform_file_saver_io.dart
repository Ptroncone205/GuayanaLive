import 'dart:io';
import 'dart:typed_data';

import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

Future<String?> saveImageToDevice(Uint8List bytes, String fileName) async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await ImageGallerySaverPlus.saveImage(bytes, name: fileName);
      final success = result != null && (result['isSuccess'] == true || result['filePath'] != null);
      if (success) {
        return result['filePath']?.toString() ?? fileName;
      }
      return null;
    }

    final home = Platform.isWindows ? Platform.environment['USERPROFILE'] : Platform.environment['HOME'];
    final downloadsPath = home != null ? '$home${Platform.pathSeparator}Downloads' : Directory.current.path;
    final downloadsDir = Directory(downloadsPath);
    final saveDir = await (downloadsDir.existsSync() ? downloadsDir : Directory.current).create(recursive: true);
    final saveFile = File('${saveDir.path}${Platform.pathSeparator}$fileName.jpg');
    await saveFile.writeAsBytes(bytes);
    return saveFile.path;
  } catch (_) {
    return null;
  }
}
