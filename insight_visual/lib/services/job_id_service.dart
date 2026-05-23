import 'dart:io';

class JobIdService {
  static final _file = File(
    '${Platform.environment['HOME']}/.insightcircle/job_id',
  );

  static Future<String?> load() async {
    try {
      if (await _file.exists()) {
        final s = (await _file.readAsString()).trim();
        return s.isEmpty ? null : s;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save(String jobId) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jobId);
    } catch (_) {}
  }
}
