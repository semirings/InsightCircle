import '../models/pipeline_step.dart';

const kGcpProject  = 'creator-d4m-2026-1774038056';
const kBqDataset   = 'insight_metadata';
const kGcsBucket   = 'insightcircle_bucket';
const kCalcService    = 'insight-calc';
const kTokenService   = 'insight-token';
const kIngestService  = 'insight-ingest';
const kRegion      = 'us-central1';

const kPipelineSteps = <PipelineStep>[
  PipelineStep(
    id: 'II',
    name: 'Ingest',
    serviceType: 'Pub/Sub · ingest-trigger',
    jobName: 'ingest-trigger',
    region: kRegion,
  ),
  PipelineStep(
    id: 'I2',
    name: 'Ontology',
    serviceType: 'Pub/Sub · ingest-completion',
    jobName: 'ingest-completion',
    region: kRegion,
  ),
  PipelineStep(
    id: 'IT',
    name: 'Token',
    serviceType: 'Cloud Run · REST',
    jobName: kTokenService,
    region: kRegion,
  ),
  PipelineStep(
    id: 'IC',
    name: 'Calc',
    serviceType: 'Cloud Run · REST',
    jobName: kCalcService,
    region: kRegion,
  ),
  PipelineStep(
    id: 'IS',
    name: 'Store',
    serviceType: 'BigQuery · $kBqDataset',
    jobName: 'bq-query',
    region: kRegion,
  ),
  PipelineStep(
    id: 'IW',
    name: 'Whisper',
    serviceType: 'Pub/Sub · whisper-input',
    jobName: 'whisper-input',
    region: kRegion,
  ),
];
