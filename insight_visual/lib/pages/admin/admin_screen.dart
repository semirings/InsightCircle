import 'dart:math';

import 'package:flutter/material.dart';

import '../../config/pipeline_config.dart';
import '../../models/execution_status.dart';
import '../../models/log_entry.dart';
import '../../models/pipeline_run.dart';
import '../../models/pipeline_step.dart';
import '../../models/step_result.dart';
import '../../services/bigquery_service.dart';
import '../../services/cloud_run_service.dart';
import '../../services/history_service.dart';
import '../../services/job_id_service.dart';
import '../../services/logging_service.dart';
import '../../services/pubsub_service.dart';
import '../../theme.dart';
import '../../widgets/admin/service_cards.dart';

// ── Constants ──────────────────────────────────────────────────────────────

const _kColLeft  = 260.0;
const _kGap      = 10.0;

// ── Page entry point ───────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  CloudRunService? _cloudRun;
  HistoryService?  _history;
  LoggingService?  _logging;
  BigQueryService? _bigQuery;
  bool _servicesReady = false;

  final Map<String, ExecutionStatus>       _liveStatus = {};
  final Map<String, List<StepResult>>      _stepRuns   = {};
  final Map<String, Map<String, String>>   _stepParams = {};
  List<String>               _bqTables        = [];
  bool                       _bqTablesLoading = true;
  List<String>               _itVideoIds       = [];
  bool                       _itVideoIdsLoading = false;
  List<Map<String, String>>  _icScripts       = [];
  String?                    _activeJobId;
  final Map<String, List<Map<String, dynamic>>> _stepPreview = {};

  StepResult? _selectedRun;
  int  _detailTab   = 0;
  List<LogEntry> _logs = [];
  bool _logsLoading = false;

  bool    _running       = false;
  String? _runFromStepId;

  @override
  void initState() {
    super.initState();
    _loadPersistedJobId();
    _initServices();
  }

  Future<void> _loadPersistedJobId() async {
    final id = await JobIdService.load();
    if (mounted && id != null) setState(() => _activeJobId = id);
  }

  Future<void> _initServices() async {
    try {
      final cr      = await CloudRunService.create();
      final hs      = await HistoryService.create();
      final ls      = await LoggingService.create();
      final scripts = await cr.fetchScripts(kGcpProject, kRegion, kCalcService)
          .catchError((_) => <Map<String, String>>[]);
      if (!mounted) return;
      setState(() {
        _cloudRun      = cr;
        _history       = hs;
        _logging       = ls;
        _icScripts     = scripts;
        _servicesReady = true;
      });
      await _loadHistory();
    } catch (e) {
      if (mounted) setState(() => _servicesReady = false);
    }
    _fetchBqTables();
  }

  Future<void> _fetchBqTables() async {
    setState(() => _bqTablesLoading = true);
    try {
      final bq     = await BigQueryService.create();
      final tables = await bq.listTables(kGcpProject, kBqDataset);
      if (!mounted) return;
      setState(() {
        _bigQuery        = bq;
        _bqTables        = tables;
        _bqTablesLoading = false;
      });
      _fetchItVideoIds();
    } catch (e) {
      if (mounted) setState(() => _bqTablesLoading = false);
    }
  }

  Future<void> _fetchItVideoIds() async {
    final bq = _bigQuery;
    if (bq == null) return;
    setState(() => _itVideoIdsLoading = true);
    try {
      final rows = await bq.fetchTablePreview(
        kGcpProject, kBqDataset, 'yt_metadata',
        maxRows: 2000,
      );
      if (!mounted) return;
      setState(() {
        _itVideoIds = rows
            .map((r) => (r['id'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        _itVideoIdsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _itVideoIdsLoading = false);
    }
  }

  Future<void> _loadHistory() async {
    final h = _history;
    if (h == null) return;
    for (final step in kPipelineSteps) {
      final runs = await h.getRunsForStep(step.id);
      if (mounted) setState(() => _stepRuns[step.id] = runs);
    }
  }

  void _updateStepParams(String stepId, Map<String, String> params) {
    _stepParams[stepId] = params;
  }

  // ── Dispatch ───────────────────────────────────────────────────────────

  static String _newId() {
    final r = Random.secure();
    return '${DateTime.now().millisecondsSinceEpoch}-'
        '${r.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}';
  }

  Future<ExecutionStatus> _dispatchStep(
    PipelineStep step,
    Map<String, String> params,
  ) async {
    switch (step.id) {
      case 'II':
        final jobId = await PubSubService.triggerIngest(
          phase:           params['phase'] ?? 'all',
          keywords:        (params['keywords'] ?? '').isEmpty ? null : params['keywords'],
          count:           int.tryParse(params['count'] ?? ''),
          minViews:        int.tryParse(params['minViews'] ?? ''),
          maxViews:        int.tryParse(params['maxViews'] ?? ''),
          minSubscribers:  int.tryParse(params['minSubscribers'] ?? ''),
          maxSubscribers:  int.tryParse(params['maxSubscribers'] ?? ''),
          skipDuplicates:  params['skipDuplicates'] != 'false',
        );
        setState(() => _activeJobId = jobId);
        await JobIdService.save(jobId);
        return ExecutionStatus.succeeded;

      case 'I2':
        await PubSubService.triggerOntology(
          jobId:          (params['jobId'] ?? '').isEmpty ? _newId() : params['jobId'],
          date:           params['date'] ?? '',
          metaUri:        (params['metaUri'] ?? '').isEmpty ? null : params['metaUri'],
          commentsUri:    (params['commentsUri'] ?? '').isEmpty ? null : params['commentsUri'],
          transcriptsUri: (params['transcriptsUri'] ?? '').isEmpty ? null : params['transcriptsUri'],
        );
        return ExecutionStatus.succeeded;

      case 'IT':
        final ids = (params['videoIds'] ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList();
        if (ids.isEmpty) return ExecutionStatus.succeeded;
        await _cloudRun!.callServiceEndpoint(
          kGcpProject, kRegion, kTokenService,
          '/tokenize/batch',
          {'video_ids': ids},
        );
        return ExecutionStatus.succeeded;

      case 'IC':
        final script = params['script'] ?? '';
        if (script.isEmpty) return ExecutionStatus.succeeded;
        await _cloudRun!.callServiceEndpoint(
          kGcpProject, kRegion, kCalcService,
          '/script/$script',
          {},
        );
        return ExecutionStatus.succeeded;

      case 'IS':
        final table = params['table'] ?? '';
        if (table.isNotEmpty) {
          final rows = await _bigQuery!.fetchTablePreview(
              kGcpProject, kBqDataset, table);
          setState(() => _stepPreview['IS'] = rows);
        }
        return ExecutionStatus.succeeded;

      case 'IW':
        final videoId = params['videoId'] ?? '';
        await PubSubService.triggerWhisper(videoId);
        return ExecutionStatus.succeeded;

      default:
        throw Exception('Unknown step: ${step.id}');
    }
  }

  // ── Run logic ──────────────────────────────────────────────────────────

  Future<void> _runSingleWithParams(
      PipelineStep step, Map<String, String> params) {
    _stepParams[step.id] = params;
    return _runSequence([step]);
  }

  Future<void> _runAll() => _runSequence(kPipelineSteps.toList());

  Future<void> _runFromStep(String stepId) {
    final idx = kPipelineSteps.indexWhere((s) => s.id == stepId);
    return _runSequence(kPipelineSteps.skip(idx < 0 ? 0 : idx).toList());
  }

  Future<void> _runSequence(List<PipelineStep> steps) async {
    if (_running) return;
    setState(() => _running = true);

    final runId      = _newId();
    final runStarted = DateTime.now();
    final results    = <StepResult>[];

    for (final step in steps) {
      setState(() => _liveStatus[step.id] = ExecutionStatus.running);
      final stepStarted = DateTime.now();
      try {
        final params = _stepParams[step.id] ?? {};
        final status = await _dispatchStep(step, params);
        setState(() => _liveStatus[step.id] = status);
        results.add(StepResult(
          stepId:      step.id,
          executionId: _newId(),
          startedAt:   stepStarted,
          completedAt: DateTime.now(),
          status:      status,
          jobId:       step.id == 'II' ? _activeJobId : null,
        ));
        if (status != ExecutionStatus.succeeded) {
          for (final rem
              in steps.skipWhile((s) => s.id != step.id).skip(1)) {
            setState(() => _liveStatus[rem.id] = ExecutionStatus.blocked);
          }
          break;
        }
      } catch (e) {
        setState(() => _liveStatus[step.id] = ExecutionStatus.failed);
        results.add(StepResult(
          stepId:       step.id,
          executionId:  _newId(),
          startedAt:    stepStarted,
          completedAt:  DateTime.now(),
          status:       ExecutionStatus.failed,
          errorMessage: e.toString(),
        ));
        break;
      }
    }

    setState(() => _running = false);

    if (results.isNotEmpty) {
      // Update history column immediately in memory.
      setState(() {
        for (final r in results) {
          _stepRuns[r.stepId] = [r, ...(_stepRuns[r.stepId] ?? [])];
        }
      });

      final mode = steps.length == kPipelineSteps.length
          ? RunMode.runAll
          : steps.length == 1
              ? RunMode.runSingle
              : RunMode.runFromStep;
      try {
        await _history?.recordRun(PipelineRun(
          runId:       runId,
          startedAt:   runStarted,
          completedAt: DateTime.now(),
          mode:        mode,
          startStepId: steps.first.id,
          steps:       results,
        ));
      } catch (_) {}

      if (steps.length == 1) {
        setState(() {
          _selectedRun = results.first;
          _detailTab   = 0;
          _logs        = [];
        });
      }
    }

    await _loadHistory();
  }

  // ── Detail panel ───────────────────────────────────────────────────────

  void _selectRun(StepResult run) {
    setState(() {
      _selectedRun = run;
      _detailTab   = 0;
      _logs        = [];
    });
    _fetchLogs(run.executionId);
    if (run.stepId == 'II' && run.jobId != null) {
      _fetchQuota(run.jobId!);
    }
  }

  Future<void> _fetchQuota(String jobId) async {
    final bq = _bigQuery;
    if (bq == null) return;
    try {
      final rows = await bq.fetchTablePreview(
        kGcpProject, kBqDataset, 'quota_log', maxRows: 200,
      );
      final matching = rows
          .where((r) => r['job_id']?.toString() == jobId)
          .toList();
      if (!mounted) return;
      if (matching.isNotEmpty) {
        setState(() => _stepPreview['II'] = matching
            .map((r) => r.map((k, v) => MapEntry(k, v ?? '')))
            .toList());
      } else {
        // Show today's full daily summary if job row not yet written.
        final today = DateTime.now().toLocal();
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
        final todayRows = rows
            .where((r) => r['date']?.toString() == todayStr)
            .toList();
        if (mounted && todayRows.isNotEmpty) {
          setState(() => _stepPreview['II'] = todayRows
              .map((r) => r.map((k, v) => MapEntry(k, v ?? '')))
              .toList());
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchLogs(String executionId) async {
    if (_logging == null) return;
    setState(() => _logsLoading = true);
    try {
      final entries = await _logging!.fetchLogs(executionId);
      if (mounted) setState(() => _logs = entries);
    } finally {
      if (mounted) setState(() => _logsLoading = false);
    }
  }

  void _closeDetail() => setState(() => _selectedRun = null);

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAdminBg,
      body: Column(
        children: [
          _Toolbar(
            running: _running,
            servicesReady: _servicesReady,
            runFromStepId: _runFromStepId,
            activeJobId: _activeJobId,
            steps: kPipelineSteps.toList(),
            onRunAll: _runAll,
            onRunFrom: _runFromStep,
            onRunFromStepChanged: (id) =>
                setState(() => _runFromStepId = id),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Columns 1+2 — service cards paired with run history
                Expanded(
                  child: _ServiceCardColumn(
                    steps: kPipelineSteps.toList(),
                    liveStatus: _liveStatus,
                    bqTables: _bqTables,
                    bqTablesLoading: _bqTablesLoading,
                    icScripts: _icScripts,
                    activeJobId: _activeJobId,
                    itVideoIds: _itVideoIds,
                    itVideoIdsLoading: _itVideoIdsLoading,
                    stepRuns: _stepRuns,
                    selectedRun: _selectedRun,
                    onRun: _runSingleWithParams,
                    onParamsChanged: _updateStepParams,
                    onSelectRun: _selectRun,
                  ),
                ),
                // Column 3 — detail panel (fills remaining space)
                if (_selectedRun != null)
                  Expanded(
                    child: _DetailPanel(
                      run: _selectedRun!,
                      activeTab: _detailTab,
                      logs: _logs,
                      logsLoading: _logsLoading,
                      previewRows: _stepPreview[_selectedRun!.stepId],
                      onTabChanged: (i) => setState(() => _detailTab = i),
                      onClose: _closeDetail,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Toolbar ────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final bool running;
  final bool servicesReady;
  final String? runFromStepId;
  final String? activeJobId;
  final List<PipelineStep> steps;
  final VoidCallback onRunAll;
  final void Function(String stepId) onRunFrom;
  final void Function(String? id) onRunFromStepChanged;

  const _Toolbar({
    required this.running,
    required this.servicesReady,
    required this.runFromStepId,
    required this.activeJobId,
    required this.steps,
    required this.onRunAll,
    required this.onRunFrom,
    required this.onRunFromStepChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = servicesReady && !running;
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: kAdminSurfaceLow,
        border: Border(bottom: BorderSide(color: kAdminAccent, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            'Insight Circle — admin',
            style: spaceGrotesk(
                fontSize: 13, color: kAdminText, letterSpacing: 1),
          ),
          const SizedBox(width: 24),
          _ToolbarButton(
            label: 'Run All',
            icon: Icons.play_arrow,
            enabled: enabled,
            onTap: onRunAll,
          ),
          const SizedBox(width: 12),
          _ToolbarButton(
            label: 'Run from Step',
            icon: Icons.skip_next,
            enabled: enabled && runFromStepId != null,
            onTap:
                runFromStepId != null ? () => onRunFrom(runFromStepId!) : null,
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: runFromStepId,
              hint: Text('pick step…',
                  style: inter(fontSize: 11, color: kAdminTextDim)),
              dropdownColor: kAdminSurface,
              iconEnabledColor: kAdminTextDim,
              style: inter(fontSize: 11, color: kAdminText),
              items: steps
                  .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.name),
                      ))
                  .toList(),
              onChanged: enabled ? onRunFromStepChanged : null,
            ),
          ),
          const Spacer(),
          Text('JOB',
              style: spaceGrotesk(
                  fontSize: 10, color: kAdminTextDim, letterSpacing: 1)),
          const SizedBox(width: 6),
          Text(activeJobId ?? '—',
              style: inter(fontSize: 11, color: kAdminTextMuted)),
          const SizedBox(width: 20),
          if (running) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: kAdminAccent),
            ),
            const SizedBox(width: 8),
            Text('running…',
                style: inter(fontSize: 11, color: kAdminTextMuted)),
          ],
          if (!servicesReady)
            Text('services unavailable',
                style: inter(fontSize: 11, color: kAdminAccent)),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.enabled
        ? (_hovered ? kAdminText : kAdminTextMuted)
        : kAdminTextDim;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration:
              BoxDecoration(border: Border.all(color: fg.withValues(alpha: 0.4))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: fg),
              const SizedBox(width: 4),
              Text(widget.label, style: inter(fontSize: 11, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Column 1 — service-specific cards ─────────────────────────────────────

class _ServiceCardColumn extends StatelessWidget {
  final List<PipelineStep> steps;
  final Map<String, ExecutionStatus> liveStatus;
  final List<String> bqTables;
  final bool bqTablesLoading;
  final List<Map<String, String>> icScripts;
  final String? activeJobId;
  final List<String> itVideoIds;
  final bool itVideoIdsLoading;
  final Map<String, List<StepResult>> stepRuns;
  final StepResult? selectedRun;
  final void Function(PipelineStep, Map<String, String>) onRun;
  final void Function(String, Map<String, String>) onParamsChanged;
  final void Function(StepResult) onSelectRun;

  const _ServiceCardColumn({
    required this.steps,
    required this.liveStatus,
    required this.bqTables,
    required this.bqTablesLoading,
    required this.icScripts,
    required this.onRun,
    required this.onParamsChanged,
    required this.onSelectRun,
    required this.stepRuns,
    this.activeJobId,
    this.itVideoIds        = const [],
    this.itVideoIdsLoading = false,
    this.selectedRun,
  });

  Widget _cardForStep(PipelineStep step) {
    final running = liveStatus[step.id] == ExecutionStatus.running;
    switch (step.id) {
      case 'II':
        return IICard(
          running: running,
          onRun: (p) => onRun(step, p),
          onParamsChanged: (p) => onParamsChanged(step.id, p),
        );
      case 'I2':
        return I2Card(
          running: running,
          externalJobId: activeJobId,
          onRun: (p) => onRun(step, p),
          onParamsChanged: (p) => onParamsChanged(step.id, p),
        );
      case 'IT':
        return ITCard(
          running: running,
          videoIds: itVideoIds,
          videoIdsLoading: itVideoIdsLoading,
          onRun: (p) => onRun(step, p),
          onParamsChanged: (p) => onParamsChanged(step.id, p),
        );
      case 'IC':
        return ICCard(
          running: running,
          scripts: icScripts,
          onRun: (p) => onRun(step, p),
          onParamsChanged: (p) => onParamsChanged(step.id, p),
        );
      case 'IS':
        return ISCard(
          running: running,
          tables: bqTables,
          tablesLoading: bqTablesLoading,
          onRun: (p) => onRun(step, p),
          onParamsChanged: (p) => onParamsChanged(step.id, p),
        );
      case 'IW':
        return IWCard(
          running: running,
          onRun: (p) => onRun(step, p),
          onParamsChanged: (p) => onParamsChanged(step.id, p),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kAdminSurfaceLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: _kColLeft, child: _cardForStep(steps[i])),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RunRow(
                        runs: stepRuns[steps[i].id] ?? [],
                        selectedRun: selectedRun,
                        onSelectRun: onSelectRun,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: _kColLeft / 2),
                  child: Container(
                    width: 1,
                    height: _kGap,
                    color: kAdminBorderMid,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  final List<StepResult> runs;
  final StepResult? selectedRun;
  final void Function(StepResult) onSelectRun;

  const _RunRow({
    required this.runs,
    required this.selectedRun,
    required this.onSelectRun,
  });

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('no runs yet',
            style: inter(fontSize: 11, color: kAdminTextDim)),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < runs.length; i++) ...[
            _RunCard(
              run: runs[i],
              selected: selectedRun?.executionId == runs[i].executionId,
              onTap: () => onSelectRun(runs[i]),
            ),
            if (i < runs.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RunCard extends StatefulWidget {
  final StepResult run;
  final bool selected;
  final VoidCallback onTap;
  const _RunCard(
      {required this.run, required this.selected, required this.onTap});

  @override
  State<_RunCard> createState() => _RunCardState();
}

class _RunCardState extends State<_RunCard> {
  bool _hovered = false;

  String _summary() {
    final r = widget.run;
    if (r.status == ExecutionStatus.failed) return r.errorMessage ?? 'error';
    if (r.rowCount != null) return '${r.rowCount} rows';
    if (r.byteCount != null) {
      return '${(r.byteCount! / 1024).toStringAsFixed(1)} KB';
    }
    return r.status.name;
  }

  String _duration() {
    final d = widget.run.duration;
    if (d == null) return '—';
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final success    = widget.run.status == ExecutionStatus.succeeded;
    final accentBorder = success ? kAdminGreen : kAdminAccent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 130,
          decoration: BoxDecoration(
            color: widget.selected
                ? kAdminBorderMid
                : (_hovered ? kAdminSurfaceLow : kAdminSurface),
            border: Border(
              left:   BorderSide(color: accentBorder, width: 3),
              top:    BorderSide(color: kAdminBorder),
              right:  BorderSide(color: kAdminBorder),
              bottom: BorderSide(color: kAdminBorder),
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_ts(widget.run.startedAt),
                  style: inter(fontSize: 9, color: kAdminTextMuted)),
              const SizedBox(height: 3),
              Text(_duration(),
                  style: spaceGrotesk(fontSize: 13, color: kAdminText)),
              const Spacer(),
              Text(_summary(),
                  style: inter(fontSize: 10, color: kAdminTextMuted),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  String _ts(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $h:$m';
  }
}

// ── Column 3 — Detail panel ────────────────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  final StepResult run;
  final int activeTab;
  final List<LogEntry> logs;
  final bool logsLoading;
  final List<Map<String, dynamic>>? previewRows;
  final void Function(int) onTabChanged;
  final VoidCallback onClose;

  const _DetailPanel({
    required this.run,
    required this.activeTab,
    required this.logs,
    required this.logsLoading,
    required this.onTabChanged,
    required this.onClose,
    this.previewRows,
  });

  static const _tabs = ['Results', 'Logs', 'Info'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kAdminSurface,
        border: Border(left: BorderSide(color: kAdminBorder)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: kAdminSurfaceLow,
              border: Border(bottom: BorderSide(color: kAdminBorder)),
            ),
            child: Row(
              children: [
                for (int i = 0; i < _tabs.length; i++) ...[
                  _DetailTab(
                    label: _tabs[i],
                    active: activeTab == i,
                    onTap: () => onTabChanged(i),
                  ),
                  if (i < _tabs.length - 1) const SizedBox(width: 4),
                ],
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: const Icon(Icons.close,
                        size: 14, color: kAdminTextDim),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (activeTab) {
              0 => _ResultsTab(run: run, previewRows: previewRows),
              1 => _LogsTab(logs: logs, loading: logsLoading),
              _ => _InfoTab(run: run),
            },
          ),
        ],
      ),
    );
  }
}

class _DetailTab extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _DetailTab(
      {required this.label, required this.active, required this.onTap});

  @override
  State<_DetailTab> createState() => _DetailTabState();
}

class _DetailTabState extends State<_DetailTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? kAdminText
        : (_hovered ? kAdminTextMuted : kAdminTextDim);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: widget.active
              ? const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: kAdminText, width: 2)))
              : null,
          child: Text(
            widget.label,
            style: inter(
              fontSize: 10,
              fontWeight:
                  widget.active ? FontWeight.w700 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Detail tab bodies ──────────────────────────────────────────────────────

class _ResultsTab extends StatelessWidget {
  final StepResult run;
  final List<Map<String, dynamic>>? previewRows;
  const _ResultsTab({required this.run, this.previewRows});

  @override
  Widget build(BuildContext context) {
    final rows = previewRows;
    if (rows != null && rows.isNotEmpty) {
      return _PreviewGrid(rows: rows);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (run.rowCount != null) _KV('Rows', '${run.rowCount}'),
          if (run.byteCount != null) _KV('Bytes', '${run.byteCount}'),
          if (run.errorMessage != null)
            _KV('Error', run.errorMessage!, valueColor: kAdminAccent),
          if (run.rowCount == null &&
              run.byteCount == null &&
              run.errorMessage == null)
            Text('No result data recorded.',
                style: inter(fontSize: 11, color: kAdminTextDim)),
        ],
      ),
    );
  }
}

class _PreviewGrid extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const _PreviewGrid({required this.rows});

  @override
  State<_PreviewGrid> createState() => _PreviewGridState();
}

class _PreviewGridState extends State<_PreviewGrid> {
  late final ScrollController _headerScroll;
  late final ScrollController _bodyScroll;
  late List<double> _colWidths;

  static const _initColW = 90.0;
  static const _minColW  = 30.0;
  static const _maxColW  = 600.0;

  @override
  void initState() {
    super.initState();
    _colWidths    = List.filled(widget.rows.first.keys.length, _initColW);
    _headerScroll = ScrollController();
    _bodyScroll   = ScrollController();
    _bodyScroll.addListener(_syncHeader);
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_syncHeader);
    _headerScroll.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  void _syncHeader() {
    if (_headerScroll.hasClients &&
        _headerScroll.offset != _bodyScroll.offset) {
      _headerScroll.jumpTo(_bodyScroll.offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cols   = widget.rows.first.keys.toList();
    final totalW = _colWidths.fold(0.0, (s, w) => s + w);

    Widget headerCell(int i) => SizedBox(
      width: _colWidths[i],
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(cols[i],
              style: inter(fontSize: 11, fontWeight: FontWeight.w700,
                  color: kAdminTextDim, letterSpacing: 0.4),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Column resize handle on right edge
          Positioned(
            right: 0, top: 0, bottom: 0, width: 6,
            child: GestureDetector(
              onHorizontalDragUpdate: (d) => setState(() {
                _colWidths[i] =
                    (_colWidths[i] + d.delta.dx).clamp(_minColW, _maxColW);
              }),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                        right: BorderSide(color: kAdminBorder, width: 1)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Widget dataCell(int i, dynamic value) => SizedBox(
      width: _colWidths[i],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text('${value ?? ''}',
          style: inter(fontSize: 9, color: kAdminText),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Frozen header ──────────────────────────────────────────────────
        Container(
          color: kAdminSurfaceLow,
          child: SingleChildScrollView(
            controller: _headerScroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: totalW,
              child: Row(children: [
                for (int i = 0; i < cols.length; i++) headerCell(i),
              ]),
            ),
          ),
        ),
        Container(height: 1, color: kAdminBorder),
        // ── Scrollable + selectable data rows ─────────────────────────────
        Expanded(
          child: Scrollbar(
            controller: _bodyScroll,
            child: SingleChildScrollView(
              controller: _bodyScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalW,
                child: SelectionArea(
                  child: ListView.builder(
                    itemCount: widget.rows.length,
                    itemBuilder: (_, i) {
                      final row = widget.rows[i];
                      return Container(
                        decoration: BoxDecoration(
                          border: Border(bottom:
                              BorderSide(color: kAdminBorder, width: 0.5)),
                          color: i.isOdd
                              ? Colors.white.withValues(alpha: 0.02)
                              : null,
                        ),
                        child: Row(children: [
                          for (int j = 0; j < cols.length; j++)
                            dataCell(j, row[cols[j]]),
                        ]),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LogsTab extends StatelessWidget {
  final List<LogEntry> logs;
  final bool loading;
  const _LogsTab({required this.logs, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 1.5)));
    }
    if (logs.isEmpty) {
      return Center(
          child:
              Text('No logs.', style: inter(fontSize: 11, color: kAdminTextDim)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (_, i) {
        final e  = logs[i];
        final ts = '${e.timestamp.toLocal().hour.toString().padLeft(2, '0')}'
            ':${e.timestamp.toLocal().minute.toString().padLeft(2, '0')}'
            ':${e.timestamp.toLocal().second.toString().padLeft(2, '0')}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              children: [
                TextSpan(
                    text: '$ts ',
                    style: const TextStyle(color: kAdminTextDim)),
                TextSpan(
                  text: e.message,
                  style: TextStyle(
                    color:
                        e.severity == 'ERROR' ? kAdminAccent : kAdminText,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoTab extends StatelessWidget {
  final StepResult run;
  const _InfoTab({required this.run});

  @override
  Widget build(BuildContext context) {
    final dur = run.duration;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KV('Execution ID', run.executionId),
          _KV('Step', run.stepId),
          _KV('Status', run.status.name),
          _KV('Started', run.startedAt.toLocal().toString()),
          if (run.completedAt != null)
            _KV('Completed', run.completedAt!.toLocal().toString()),
          if (dur != null) _KV('Duration', '${dur.inSeconds}s'),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _KV(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kAdminTextDim,
                  letterSpacing: 0.8)),
          const SizedBox(height: 2),
          Text(value,
              style: inter(fontSize: 11, color: valueColor ?? kAdminText)),
        ],
      ),
    );
  }
}
