import 'dart:async';

import 'package:googleapis/run/v2.dart' as run;
import 'package:googleapis_auth/auth_io.dart';

import '../models/execution_status.dart';

final _scopes = [run.CloudRunApi.cloudPlatformScope];
const _pollInterval = Duration(seconds: 5);

class CloudRunService {
  CloudRunService._();

  static Future<CloudRunService> create() async {
    final svc = CloudRunService._();
    await svc._init();
    return svc;
  }

  late final run.CloudRunApi _api;

  Future<void> _init() async {
    final client = await clientViaApplicationDefaultCredentials(scopes: _scopes);
    _api = run.CloudRunApi(client);
  }

  // Returns the execution name (projects/P/locations/L/jobs/J/executions/E).
  Future<String> triggerExecution(String jobName, String region) async {
    final parent = 'projects/-/locations/$region/jobs/$jobName';
    final resp = await _api.projects.locations.jobs.run(
      run.GoogleCloudRunV2RunJobRequest(),
      parent,
    );
    final name = resp.metadata?['name'] as String?;
    if (name == null) throw Exception('Cloud Run run() returned no execution name');
    return name;
  }

  Future<ExecutionStatus> pollExecution(String executionId) async {
    final exec = await _api.projects.locations.jobs.executions.get(executionId);
    return _statusFromExecution(exec);
  }

  Stream<ExecutionStatus> watchExecution(String executionId) async* {
    while (true) {
      final status = await pollExecution(executionId);
      yield status;
      if (status == ExecutionStatus.succeeded || status == ExecutionStatus.failed) break;
      await Future<void>.delayed(_pollInterval);
    }
  }

  ExecutionStatus _statusFromExecution(run.GoogleCloudRunV2Execution exec) {
    final conditions = exec.conditions ?? [];
    for (final c in conditions) {
      if (c.type == 'Completed') {
        if (c.state == 'CONDITION_SUCCEEDED') return ExecutionStatus.succeeded;
        if (c.state == 'CONDITION_FAILED')    return ExecutionStatus.failed;
      }
    }
    final phase = exec.observedGeneration;
    if (phase == null) return ExecutionStatus.pending;
    return ExecutionStatus.running;
  }
}
