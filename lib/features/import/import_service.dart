import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// Picks a CSV off the platform and reads it as UTF-8 (§2.9's counterpart).
///
/// Unlike export, this needs no platform branch: the share sheet exists because
/// iOS gives an app nowhere to *write*, but reading goes through the system
/// document picker, which `file_selector` wraps on every platform including
/// iOS. That keeps the whole import path iOS-clean with no hardcoded paths.
abstract final class ImportService {
  /// Returns the file's contents, or null if the user cancelled.
  static Future<ImportedFile?> pick() async {
    const XTypeGroup csvGroup = XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
      uniformTypeIdentifiers: ['public.comma-separated-values-text'],
      mimeTypes: ['text/csv'],
    );

    final XFile? file = await openFile(acceptedTypeGroups: const [csvGroup]);
    if (file == null) return null;

    // Read bytes and decode explicitly rather than `readAsString`, so a file
    // written by Excel with a UTF-8 BOM doesn't turn the first header cell into
    // "﻿Date" and fail the header check.
    final List<int> bytes = await file.readAsBytes();
    final String text = utf8.decode(bytes, allowMalformed: true);
    return ImportedFile(
      name: file.name,
      contents: text.startsWith('﻿') ? text.substring(1) : text,
    );
  }
}

class ImportedFile {
  const ImportedFile({required this.name, required this.contents});

  final String name;
  final String contents;
}
