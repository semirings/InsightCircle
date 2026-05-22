import 'package:googleapis/logging/v2.dart' as logging;
import 'package:googleapis_auth/auth_io.dart';

import '../models/log_entry.dart';

LogEntry _fromApiEntry(logging.LogEntry e) {
  final ts = e.timestamp ?? e.receiveTimestamp ?? '';
  return LogEntry(
    timestamp: ts.isNotEmpty ? DateTime.parse(ts) : DateTime.now(),
    severity: e.severity ?? 'DEFAULT',
    message: e.textPayload ??
        (e.jsonPayload?['message'] as String?) ??
        '',
  );
}

class LoggingService {
  LoggingService._();

  static Future<LoggingService> create() async {
    final svc = LoggingService._();
    await svc._init();
    return svc;
  }

  late final logging.LoggingApi _api;

  Future<void> _init() async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: [logging.LoggingApi.cloudPlatformScope],
    );
    _api = logging.LoggingApi(client);
  }

  Future<List<LogEntry>> fetchLogs(String executionId) async {
    final filter =
        'labels."run.googleapis.com/execution-name"="$executionId"';
    final req = logging.ListLogEntriesRequest(
      filter: filter,
      orderBy: 'timestamp asc',
      pageSize: 500,
    );
    final resp = await _api.entries.list(req);
    return (resp.entries ?? []).map(_fromApiEntry).toList();
  }
}
