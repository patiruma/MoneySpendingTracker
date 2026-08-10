import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a CSV export off to the platform (§2.9, §2.10). iOS has no
/// user-visible filesystem, so mobile always goes through the share sheet;
/// desktop gets a save dialog since there's a real place to put the file.
abstract final class ExportService {
  static Future<void> save(String csv, String suggestedFileName) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/$suggestedFileName');
      await file.writeAsString(csv, encoding: utf8);
      await Share.shareXFiles(
        [XFile(file.path)],
        fileNameOverrides: [suggestedFileName],
      );
      return;
    }

    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: suggestedFileName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return;
    // `utf8.encode`, not `csv.codeUnits`: codeUnits are UTF-16 units, and
    // Uint8List truncates each to a byte — which silently mangles any non-ASCII
    // character in a note or label name (an accent, a currency sign, an emoji).
    final XFile file = XFile.fromData(
      Uint8List.fromList(utf8.encode(csv)),
      mimeType: 'text/csv',
      name: suggestedFileName,
    );
    await file.saveTo(location.path);
  }
}
