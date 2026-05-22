class PipelineStep {
  final String id;
  final String name;
  final String serviceType;
  final String jobName;
  final String region;

  const PipelineStep({
    required this.id,
    required this.name,
    required this.serviceType,
    required this.jobName,
    required this.region,
  });
}
