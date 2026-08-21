/// RFC 4180 CSV writing for the spreadsheet export.
///
/// Export only. CSV cannot carry tombstones or settings, so it is NOT a
/// restore path and must never be offered as one
/// (docs/ARCHITECTURE.md § CSV export).
library;

/// UTF-8 byte-order mark, prepended to every CSV the app writes.
///
/// Without it Excel decodes the file as the machine's legacy codepage and
/// mangles every Cyrillic and Uzbek string. Nothing else in Tally emits a
/// BOM; this is the one format read by a program that guesses.
const String kUtf8Bom = '\u{FEFF}';

/// RFC 4180 line terminator. Excel accepts a bare `\n`; enough other
/// spreadsheet importers do not that the spec's `\r\n` is the safer choice.
const String kCsvLineEnding = '\r\n';

/// Quotes one field per RFC 4180: wrap in double quotes when it contains a
/// comma, a quote or a line break, and double up any embedded quote.
///
/// A note reading `weekly shop, "big" one` has to survive verbatim — a
/// spreadsheet that splits it into three columns has silently corrupted the
/// owner's data.
String csvField(String value) {
  final bool needsQuotes = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Joins one row of already-raw values into a CSV line (no terminator).
String csvRow(List<String> fields) => fields.map(csvField).join(',');

/// Renders [rows] (the header included, as the first entry) as a complete CSV
/// document: BOM, CRLF endings, and a trailing terminator on the last row so
/// appending to the file cannot glue two records together.
String csvDocument(List<List<String>> rows) {
  final StringBuffer out = StringBuffer(kUtf8Bom);
  for (final List<String> row in rows) {
    out
      ..write(csvRow(row))
      ..write(kCsvLineEnding);
  }
  return out.toString();
}
