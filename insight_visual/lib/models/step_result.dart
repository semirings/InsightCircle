import 'execution_status.dart';

class StepResult {
  final String stepId;
  final String executionId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final ExecutionStatus status;
  final int? rowCount;
  final int? byteCount;
  final String? errorMessage;

  const StepResult({
    required this.stepId,
    required this.executionId,
    required this.startedAt,
    this.completedAt,
    required this.status,
    this.rowCount,
    this.byteCount,
    this.errorMessage,
  });

  Duration? get duration => completedAt?.difference(startedAt);

  factory StepResult.fromJson(Map<String, dynamic> json) {
    return StepResult(
      stepId: json['stepId'] as String,
      executionId: json['executionId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      status: ExecutionStatus.values.byName(json['status'] as String),
      rowCount: json['rowCount'] as int?,
      byteCount: json['byteCount'] as int?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'stepId': stepId,
        'executionId': executionId,
        'startedAt': startedAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'status': status.name,
        if (rowCount != null) 'rowCount': rowCount,
        if (byteCount != null) 'byteCount': byteCount,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };
}
