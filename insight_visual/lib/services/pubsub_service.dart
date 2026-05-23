import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../config/pipeline_config.dart';

class PubSubService {
  PubSubService._();

  static Future<void> publish(String topic, Map<String, dynamic> payload) async {
    final message = jsonEncode(payload);
    final result = await Process.run('gcloud', [
      'pubsub', 'topics', 'publish', topic,
      '--message', message,
      '--project', kGcpProject,
    ]);
    if (result.exitCode != 0) {
      throw Exception('gcloud pubsub publish failed: ${result.stderr}');
    }
  }

  // ── Per-service message builders ─────────────────────────────────────────

  static String _newId() {
    final r = Random.secure();
    return '${DateTime.now().millisecondsSinceEpoch}-'
        '${r.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}';
  }

  static Future<String> triggerIngest({
    String? jobId,
    String phase = 'all',
    String? keywords,
    int? count,
    int? perKeyword,
  }) async {
    final id = jobId ?? _newId();
    final payload = <String, dynamic>{
      'job_id': id,
      'phase': phase,
      if (keywords != null && keywords.isNotEmpty) 'keywords': jsonDecode(keywords),
      'max_total': ?count,
      'max_results_per_q': ?perKeyword,
    };
    await publish('ingest-trigger', payload);
    return id;
  }

  static Future<void> triggerOntology({
    String? jobId,
    required String date,
    String? metaUri,
    String? commentsUri,
    String? transcriptsUri,
  }) async {
    final id  = jobId ?? _newId();
    final meta = metaUri ?? 'gs://$kGcsBucket/ingest/$date/${id}_meta.jsonl';
    final payload = <String, dynamic>{
      'job_id': id,
      'gcs_uri': meta,
      if (commentsUri != null && commentsUri.isNotEmpty)
        'comments_uri': commentsUri,
      if (transcriptsUri != null && transcriptsUri.isNotEmpty)
        'transcripts_uri': transcriptsUri,
    };
    await publish('ingest-completion', payload);
  }

  static Future<void> triggerToken(String videoId) async {
    await publish('whisper-completion', {
      'video_id': videoId,
      'status': 'completed',
    });
  }

  static Future<void> triggerWhisper(String videoId) async {
    await publish('whisper-input', {'video_id': videoId});
  }
}
