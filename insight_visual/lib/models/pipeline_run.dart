import 'step_result.dart';

enum RunMode { runAll, runFromStep, runSingle }

class PipelineRun {
  final String runId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final RunMode mode;
  final String? startStepId;
  final List<StepResult> steps;

  const PipelineRun({
    required this.runId,
    required this.startedAt,
    this.completedAt,
    required this.mode,
    this.startStepId,
    required this.steps,
  });

  factory PipelineRun.fromJson(Map<String, dynamic> json) {
    return PipelineRun(
      runId: json['runId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: (json['completedAt'] as String?) != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      mode: RunMode.values.byName(json['mode'] as String),
      startStepId: json['startStepId'] as String?,
      steps: (json['steps'] as List<dynamic>)
          .map((e) => StepResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'runId': runId,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'mode': mode.name,
        'startStepId': startStepId,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}
