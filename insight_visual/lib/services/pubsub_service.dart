import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../config/pipeline_config.dart';

class PubSubService {
  PubSubService._();

  static Future<void> publish(String topic, Map<String, dynamic> payload) async {
    final message = jsonEncode(payload);
    const gcloud = '/opt/homebrew/share/google-cloud-sdk/bin/gcloud';
    final result = await Process.run(gcloud, [
      'pubsub', 'topics', 'publish', topic,
      '--message', message,
      '--project', kGcpProject,
    ]);
    if (result.exitCode != 0) {
      throw Exception('gcloud pubsub publish failed: ${result.stderr}');
    }
  }

  // ── Per-service message builders ─────────────────────────────────────────

  static String? _extractVideoId(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(raw)) return raw;
    try {
      final uri = Uri.parse(raw);
      if (uri.host == 'youtu.be' || uri.host == 'www.youtu.be') {
        final id = uri.pathSegments.firstOrNull ?? '';
        if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) return id;
      }
      if (uri.host.contains('youtube.com')) {
        final v = uri.queryParameters['v'] ?? '';
        if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v)) return v;
        final m = RegExp(r'/(?:shorts|embed|v)/([A-Za-z0-9_-]{11})').firstMatch(uri.path);
        if (m != null) return m.group(1);
      }
    } catch (_) {}
    return null;
  }

  static List<String> extractVideoIds(List<String> urls) =>
      urls.map(_extractVideoId).whereType<String>().toList();

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
    int? minViews,
    int? maxViews,
    int? minSubscribers,
    int? maxSubscribers,
    bool skipDuplicates = true,
    List<String>? videoIds,
  }) async {
    final id = jobId ?? _newId();
    final kws = (keywords != null && keywords.isNotEmpty && keywords != '[]')
        ? jsonDecode(keywords) as List
        : null;
    final payload = <String, dynamic>{
      'job_id': id,
      'phase': phase,
      if (videoIds != null && videoIds.isNotEmpty)
        'video_ids': videoIds
      else if (kws != null && kws.isNotEmpty)
        'keywords': kws,
      'max_total': ?count,
      'min_views': ?minViews,
      'max_views': ?maxViews,
      'min_subscribers': ?minSubscribers,
      'max_subscribers': ?maxSubscribers,
      if (skipDuplicates) 'skip_duplicates': true,
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
    final id   = jobId ?? _newId();
    final base = date.isNotEmpty ? 'gs://$kGcsBucket/ingest/$date/$id' : null;
    final meta     = (metaUri?.isNotEmpty        == true) ? metaUri!        : '${base}_meta.jsonl';
    final comments = (commentsUri?.isNotEmpty    == true) ? commentsUri!    : base != null ? '${base}_comments.jsonl'    : null;
    final transcripts = (transcriptsUri?.isNotEmpty == true) ? transcriptsUri! : base != null ? '${base}_transcripts.jsonl' : null;
    final payload = <String, dynamic>{
      'job_id':   id,
      'gcs_uri':  meta,
      'comments_uri':    ?comments,
      'transcripts_uri': ?transcripts,
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
