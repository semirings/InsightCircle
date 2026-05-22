class LogEntry {
  final DateTime timestamp;
  final String severity;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.severity,
    required this.message,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'] as String? ?? json['receiveTimestamp'] as String? ?? '';
    return LogEntry(
      timestamp: ts.isNotEmpty ? DateTime.parse(ts) : DateTime.now(),
      severity: json['severity'] as String? ?? 'DEFAULT',
      message: (json['textPayload'] as String?) ??
          (json['jsonPayload']?['message'] as String?) ??
          '',
    );
  }
}
