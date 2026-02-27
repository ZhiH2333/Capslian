import 'dart:convert';
import 'dart:io';

const String _kLogPath = '/Users/ethan/Desktop/Capslian/capslian/.cursor/debug-5b5949.log';
const String _kIngestUrl = 'http://127.0.0.1:7244/ingest/2fdc6450-2aec-4da7-960e-8d56c454855f';

/// Writes one NDJSON line to the session debug log (file when path writable, and HTTP ingest).
void debugLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
  final payload = <String, dynamic>{
    'sessionId': '5b5949',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'location': location,
    'message': message,
    'data': data,
    'hypothesisId': hypothesisId,
  };
  final body = jsonEncode(payload);
  try {
    File(_kLogPath).writeAsStringSync('$body\n', mode: FileMode.append);
  } catch (_) {}
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 1);
    client
        .postUrl(Uri.parse(_kIngestUrl))
        .then((req) {
          req.headers.set('Content-Type', 'application/json');
          req.headers.set('X-Debug-Session-Id', '5b5949');
          req.write(body);
          return req.close();
        })
        .then((_) => client.close())
        .catchError((_) => client.close(force: true));
  } catch (_) {}
}
