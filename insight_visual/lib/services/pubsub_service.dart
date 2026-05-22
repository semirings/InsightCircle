import 'dart:convert';
import 'dart:io';

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

  static Future<void> triggerIngest({
    required String jobId,
    String phase = 'all',
    String? keywords,
    int? count,
    int? perKeyword,
  }) async {
    final payload = <String, dynamic>{
      'job_id': jobId,
      'phase': phase,
      if (keywords != null && keywords.isNotEmpty) 'keywords': jsonDecode(keywords),
      'max_total': ?count,
      'max_results_per_q': ?perKeyword,
    };
    await publish('ingest-trigger', payload);
  }

  static Future<void> triggerOntology({
    required String jobId,
    required String date,
    String? metaUri,
    String? commentsUri,
    String? transcriptsUri,
  }) async {
    String meta = metaUri ?? 'gs://$kGcsBucket/ingest/$date/${jobId}_meta.jsonl';
    final payload = <String, dynamic>{
      'job_id': jobId,
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
