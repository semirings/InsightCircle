import 'dart:math';

import 'package:flutter/material.dart';

import '../../config/pipeline_config.dart';
import '../../models/execution_status.dart';
import '../../models/log_entry.dart';
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
const _kColRight = 220.0;
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
  List<String> _bqTables   = [];
  String?      _activeJobId;
  String?      _activeVideoId;

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
      final cr     = await CloudRunService.create();
      final hs     = await HistoryService.create();
      final ls     = await LoggingService.create();
      final bq     = await BigQueryService.create();
      final tables = await bq.listTables(kGcpProject, kBqDataset);
      if (!mounted) return;
      setState(() {
        _cloudRun      = cr;
        _history       = hs;
        _logging       = ls;
        _bigQuery      = bq;
        _bqTables      = tables;
        _servicesReady = true;
      });
      await _loadHistory();
    } catch (e) {
      if (mounted) setState(() => _servicesReady = false);
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
          phase:    params['phase'] ?? 'all',
          keywords: (params['keywords'] ?? '').isEmpty ? null : params['keywords'],
          count:    int.tryParse(params['count'] ?? ''),
        );
        setState(() => _activeJobId = jobId);
        await JobIdService.save(jobId);
        return ExecutionStatus.succeeded;

      case 'I2':
        await PubSubService.triggerOntology(
          jobId:          (params['jobId'] ?? '').isEmpty ? _newId() : params['jobId'],
          date:           params['date'] ?? '',
          commentsUri:    (params['commentsUri'] ?? '').isEmpty ? null : params['commentsUri'],
          transcriptsUri: (params['transcriptsUri'] ?? '').isEmpty ? null : params['transcriptsUri'],
        );
        return ExecutionStatus.succeeded;

      case 'IT':
        await PubSubService.triggerToken(params['videoId'] ?? '');
        return ExecutionStatus.succeeded;

      case 'IC':
        await _cloudRun!.callServiceEndpoint(
          kGcpProject, kRegion, kCalcService,
          '/query/yt_metadata',
          {'query': (params['query'] ?? '').isEmpty ? ':' : params['query']!},
        );
        return ExecutionStatus.succeeded;

      case 'IS':
        final table = params['table'] ?? '';
        if (table.isNotEmpty) {
          await _bigQuery!.fetchTablePreview(kGcpProject, kBqDataset, table);
        }
        return ExecutionStatus.succeeded;

      case 'IW':
        final videoId = params['videoId'] ?? '';
        await PubSubService.triggerWhisper(videoId);
        if (videoId.isNotEmpty) setState(() => _activeVideoId = videoId);
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

    for (final step in steps) {
      setState(() => _liveStatus[step.id] = ExecutionStatus.running);
      try {
        final params = _stepParams[step.id] ?? {};
        final status = await _dispatchStep(step, params);
        setState(() => _liveStatus[step.id] = status);
        if (status != ExecutionStatus.succeeded) {
          for (final rem
              in steps.skipWhile((s) => s.id != step.id).skip(1)) {
            setState(() => _liveStatus[rem.id] = ExecutionStatus.blocked);
          }
          break;
        }
      } catch (e) {
        setState(() => _liveStatus[step.id] = ExecutionStatus.failed);
        break;
      }
    }

    setState(() => _running = false);
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
                // Column 1 — service-specific cards
                SizedBox(
                  width: _kColLeft,
                  child: _ServiceCardColumn(
                    steps: kPipelineSteps.toList(),
                    liveStatus: _liveStatus,
                    bqTables: _bqTables,
                    activeJobId: _activeJobId,
                    activeVideoId: _activeVideoId,
                    onRun: _runSingleWithParams,
                    onParamsChanged: _updateStepParams,
                  ),
                ),
                // Column 2 — run history
                Expanded(
                  child: _HistoryColumn(
                    steps: kPipelineSteps.toList(),
                    stepRuns: _stepRuns,
                    selectedRun: _selectedRun,
                    onSelectRun: _selectRun,
                  ),
                ),
                // Column 3 — detail panel (conditional)
                if (_selectedRun != null)
                  SizedBox(
                    width: _kColRight,
                    child: _DetailPanel(
                      run: _selectedRun!,
                      activeTab: _detailTab,
                      logs: _logs,
                      logsLoading: _logsLoading,
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
  final String? activeJobId;
  final String? activeVideoId;
  final void Function(PipelineStep, Map<String, String>) onRun;
  final void Function(String, Map<String, String>) onParamsChanged;

  const _ServiceCardColumn({
    required this.steps,
    required this.liveStatus,
    required this.bqTables,
    required this.onRun,
    required this.onParamsChanged,
    this.activeJobId,
    this.activeVideoId,
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
          externalVideoId: activeVideoId,
          onRun: (p) => onRun(step, p),
          onParamsChanged: (p) => onParamsChanged(step.id, p),
        );
      case 'IC':
        return ICCard(
          running: running,
          onRun: (p) => onRun(step, p),
          onParamsChanged: (p) => onParamsChanged(step.id, p),
        );
      case 'IS':
        return ISCard(
          running: running,
          tables: bqTables,
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
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              _cardForStep(steps[i]),
              if (i < steps.length - 1)
                Center(
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

// ── Column 2 — Run history ─────────────────────────────────────────────────

class _HistoryColumn extends StatelessWidget {
  final List<PipelineStep> steps;
  final Map<String, List<StepResult>> stepRuns;
  final StepResult? selectedRun;
  final void Function(StepResult) onSelectRun;

  const _HistoryColumn({
    required this.steps,
    required this.stepRuns,
    required this.selectedRun,
    required this.onSelectRun,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in steps) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                step.id,
                style: inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: kAdminTextDim,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SizedBox(
              height: 80,
              child: _RunRow(
                runs: stepRuns[step.id] ?? [],
                selectedRun: selectedRun,
                onSelectRun: onSelectRun,
              ),
            ),
            const SizedBox(height: _kGap + 6),
          ],
        ],
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
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: runs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final run      = runs[i];
        final selected = selectedRun?.executionId == run.executionId;
        return _RunCard(
          run: run,
          selected: selected,
          onTap: () => onSelectRun(run),
        );
      },
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
  final void Function(int) onTabChanged;
  final VoidCallback onClose;

  const _DetailPanel({
    required this.run,
    required this.activeTab,
    required this.logs,
    required this.logsLoading,
    required this.onTabChanged,
    required this.onClose,
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
              0 => _ResultsTab(run: run),
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
  const _ResultsTab({required this.run});

  @override
  Widget build(BuildContext context) {
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
                  fontSize: 9,
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
