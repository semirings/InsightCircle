import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

import '../models/pipeline_run.dart';
import '../models/step_result.dart';

// Firestore REST API base — swap in real project ID at runtime.
const _projectId = 'creator-d4m-2026-1774038056';
const _collection = 'pipeline_runs';

String _baseUrl() =>
    'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/$_collection';

class HistoryService {
  HistoryService._();

  static Future<HistoryService> create() async {
    final svc = HistoryService._();
    await svc._init();
    return svc;
  }

  late final http.Client _client;

  Future<void> _init() async {
    _client = await clientViaApplicationDefaultCredentials(
      scopes: ['https://www.googleapis.com/auth/datastore'],
    );
  }

  Future<void> recordRun(PipelineRun run) async {
    final url = Uri.parse('${_baseUrl()}/${run.runId}');
    final body = jsonEncode(_runToFirestore(run));
    final resp = await _client.patch(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (resp.statusCode >= 400) {
      throw Exception('Firestore write failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<List<StepResult>> getRunsForStep(String stepId, {int limit = 20}) async {
    final url = Uri.parse(
      '${_baseUrl()}?pageSize=$limit&orderBy=startedAt desc',
    );
    final resp = await _client.get(url);
    if (resp.statusCode >= 400) {
      throw Exception('Firestore query failed: ${resp.statusCode}');
    }
    final docs = (jsonDecode(resp.body)['documents'] as List<dynamic>?) ?? [];
    final results = <StepResult>[];
    for (final doc in docs) {
      final run = _runFromFirestore(doc as Map<String, dynamic>);
      results.addAll(run.steps.where((s) => s.stepId == stepId));
    }
    return results;
  }

  Future<List<PipelineRun>> getAllRuns({int limit = 50}) async {
    final url = Uri.parse(
      '${_baseUrl()}?pageSize=$limit&orderBy=startedAt desc',
    );
    final resp = await _client.get(url);
    if (resp.statusCode >= 400) {
      throw Exception('Firestore query failed: ${resp.statusCode}');
    }
    final docs = (jsonDecode(resp.body)['documents'] as List<dynamic>?) ?? [];
    return docs
        .map((d) => _runFromFirestore(d as Map<String, dynamic>))
        .toList();
  }

  // ── Firestore serialisation ────────────────────────────────────────────────

  Map<String, dynamic> _runToFirestore(PipelineRun run) {
    return {
      'fields': {
        'runId':       _strField(run.runId),
        'startedAt':   _strField(run.startedAt.toIso8601String()),
        'completedAt': _strField(run.completedAt?.toIso8601String() ?? ''),
        'mode':        _strField(run.mode.name),
        'startStepId': _strField(run.startStepId ?? ''),
        'steps':       _arrayField(run.steps.map((s) => s.toJson()).toList()),
      },
    };
  }

  PipelineRun _runFromFirestore(Map<String, dynamic> doc) {
    final fields = doc['fields'] as Map<String, dynamic>;
    String str(String k) =>
        (fields[k] as Map<String, dynamic>?)?['stringValue'] as String? ?? '';
    final completedAt = str('completedAt');
    return PipelineRun.fromJson({
      'runId': str('runId'),
      'startedAt': str('startedAt'),
      'completedAt': completedAt.isNotEmpty ? completedAt : null,
      'mode': str('mode'),
      'startStepId': str('startStepId').isNotEmpty ? str('startStepId') : null,
      'steps': _arrayFromFirestore(fields['steps']),
    });
  }

  List<dynamic> _arrayFromFirestore(dynamic field) {
    if (field == null) return [];
    final values =
        (field as Map<String, dynamic>)['arrayValue']?['values'] as List<dynamic>?;
    return values
            ?.map((v) =>
                (v as Map<String, dynamic>)['mapValue']?['fields'] ?? {})
            .toList() ??
        [];
  }

  Map<String, dynamic> _strField(String v) => {'stringValue': v};

  Map<String, dynamic> _arrayField(List<dynamic> items) => {
        'arrayValue': {
          'values': items
              .map((item) => {
                    'mapValue': {
                      'fields': (item as Map<String, dynamic>).map(
                        (k, v) => MapEntry(k, _strField(v.toString())),
                      ),
                    },
                  })
              .toList(),
        },
      };
}
