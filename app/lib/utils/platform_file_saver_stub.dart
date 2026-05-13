import 'dart:typed_data';
import 'dart:html' as html;

Future<String?> saveImageToDevice(Uint8List bytes, String fileName) async {
  try {
    final blob = html.Blob([bytes], 'image/jpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = '$fileName.jpg'
      ..style.display = 'none';

    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);

    return 'download';
  } catch (_) {
    return null;
  }
}
