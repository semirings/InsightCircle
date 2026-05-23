import 'package:flutter/material.dart';

import '../../theme.dart';

// Each card calls onRun with its current params, and calls onParamsChanged
// whenever the user edits a field so the admin screen can track state for
// "run all" / "run from step" modes.

typedef RunCallback         = void Function(Map<String, String> params);
typedef ParamsChangedCallback = void Function(Map<String, String> params);

// ── Shared card chrome ─────────────────────────────────────────────────────

class ServiceCard extends StatelessWidget {
  final String serviceId;
  final String title;
  final Widget body;
  final VoidCallback onRun;
  final bool running;

  const ServiceCard({
    super.key,
    required this.serviceId,
    required this.title,
    required this.body,
    required this.onRun,
    this.running = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: kAdminSurface,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: kAdminAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  serviceId,
                  style: inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: kAdminAccent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(title,
                  style: spaceGrotesk(fontSize: 11, color: kAdminText)),
              const Spacer(),
              if (running)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: kAdminAccent),
                ),
            ],
          ),
          const SizedBox(height: 8),
          body,
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _RunBtn(onTap: onRun, running: running),
          ),
        ],
      ),
    );
  }
}

class _RunBtn extends StatefulWidget {
  final VoidCallback onTap;
  final bool running;
  const _RunBtn({required this.onTap, required this.running});

  @override
  State<_RunBtn> createState() => _RunBtnState();
}

class _RunBtnState extends State<_RunBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.running;
    final bg = enabled
        ? (_hovered ? kAdminAccent : kAdminBorderMid)
        : kAdminBorderMid;
    return MouseRegion(
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: kAdminBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow,
                  size: 11,
                  color: enabled ? kAdminText : kAdminTextDim),
              const SizedBox(width: 3),
              Text('Run',
                  style: inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: enabled ? kAdminText : kAdminTextDim,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Compact form helpers ───────────────────────────────────────────────────

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget field;
  const _FieldRow({required this.label, required this.field});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: kAdminTextDim,
                  letterSpacing: 0.5),
            ),
          ),
          Expanded(child: field),
        ],
      ),
    );
  }
}

Widget _dropdownField<T>({
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) =>
    Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: kAdminSurfaceLow,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: kAdminSurface,
          iconEnabledColor: kAdminTextDim,
          iconSize: 14,
          style: inter(fontSize: 10, color: kAdminText),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );

// ── II — InsightIngest ─────────────────────────────────────────────────────

class IICard extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  const IICard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
  });

  @override
  State<IICard> createState() => _IICardState();
}

class _IICardState extends State<IICard> {
  String _phase = 'all';
  final _keywords = TextEditingController();
  final _count    = TextEditingController();

  Map<String, String> get _params => {
        'phase':    _phase,
        'keywords': _keywords.text,
        'count':    _count.text,
      };

  void _notify() => widget.onParamsChanged?.call(_params);

  @override
  void dispose() {
    _keywords.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'II',
      title: 'Ingest',
      running: widget.running,
      onRun: () => widget.onRun(_params),
      body: Column(
        children: [
          _FieldRow(
            label: 'Phase',
            field: _dropdownField<String>(
              value: _phase,
              items: ['all', '1', '2', '3']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) {
                setState(() => _phase = v ?? 'all');
                _notify();
              },
            ),
          ),
          _FieldRow(
            label: 'Keywords',
            field: _inputField(_keywords,
                hint: '["foo","bar"]', onChanged: _notify),
          ),
          _FieldRow(
            label: 'Count',
            field: _inputField(_count,
                hint: '10',
                keyboardType: TextInputType.number,
                onChanged: _notify),
          ),
        ],
      ),
    );
  }
}

// ── I2 — InsightOntology ───────────────────────────────────────────────────

class I2Card extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  const I2Card({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
  });

  @override
  State<I2Card> createState() => _I2CardState();
}

class _I2CardState extends State<I2Card> {
  final _jobId          = TextEditingController();
  final _date           = TextEditingController();
  final _commentsUri    = TextEditingController();
  final _transcriptsUri = TextEditingController();

  Map<String, String> get _params => {
        'jobId':          _jobId.text,
        'date':           _date.text,
        'commentsUri':    _commentsUri.text,
        'transcriptsUri': _transcriptsUri.text,
      };

  void _notify() => widget.onParamsChanged?.call(_params);

  @override
  void dispose() {
    _jobId.dispose();
    _date.dispose();
    _commentsUri.dispose();
    _transcriptsUri.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'I2',
      title: 'Ontology',
      running: widget.running,
      onRun: () => widget.onRun(_params),
      body: Column(
        children: [
          _FieldRow(
            label: 'Job ID',
            field: _inputField(_jobId, hint: 'uuid', onChanged: _notify),
          ),
          _FieldRow(
            label: 'Date',
            field: _inputField(_date, hint: 'YYYY-MM-DD', onChanged: _notify),
          ),
          _FieldRow(
            label: 'Comments',
            field: _inputField(_commentsUri,
                hint: 'gs://…/comments.jsonl', onChanged: _notify),
          ),
          _FieldRow(
            label: 'Transcripts',
            field: _inputField(_transcriptsUri,
                hint: 'gs://…/transcripts.jsonl', onChanged: _notify),
          ),
        ],
      ),
    );
  }
}

// ── IT — InsightToken ──────────────────────────────────────────────────────

class ITCard extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  const ITCard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
  });

  @override
  State<ITCard> createState() => _ITCardState();
}

class _ITCardState extends State<ITCard> {
  final _videoId = TextEditingController();

  Map<String, String> get _params => {'videoId': _videoId.text};

  void _notify() => widget.onParamsChanged?.call(_params);

  @override
  void dispose() {
    _videoId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'IT',
      title: 'Token',
      running: widget.running,
      onRun: () => widget.onRun(_params),
      body: _FieldRow(
        label: 'Video ID',
        field: _inputField(_videoId,
            hint: 'yt video_id', onChanged: _notify),
      ),
    );
  }
}

// ── IC — InsightCalc ───────────────────────────────────────────────────────

class ICCard extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  const ICCard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
  });

  @override
  State<ICCard> createState() => _ICCardState();
}

class _ICCardState extends State<ICCard> {
  final _query = TextEditingController(
      text: 'SELECT * FROM tokens LIMIT 10');

  Map<String, String> get _params => {'query': _query.text};

  void _notify() => widget.onParamsChanged?.call(_params);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'IC',
      title: 'Calc',
      running: widget.running,
      onRun: () => widget.onRun(_params),
      body: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: kAdminSurfaceLow,
          border: Border.all(color: kAdminBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: TextField(
          controller: _query,
          maxLines: null,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 10, color: kAdminText),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'SELECT …',
            hintStyle: const TextStyle(
                fontFamily: 'monospace', fontSize: 10, color: kAdminTextDim),
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (_) => _notify(),
        ),
      ),
    );
  }
}

// ── IS — InsightStore (BQ table query) ────────────────────────────────────

class ISCard extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  // Injected from admin screen after BigQueryService fetches the list
  final List<String> tables;
  const ISCard({
    super.key,
    required this.onRun,
    required this.tables,
    this.onParamsChanged,
    this.running = false,
  });

  @override
  State<ISCard> createState() => _ISCardState();
}

class _ISCardState extends State<ISCard> {
  String? _table;

  Map<String, String> get _params => {'table': _table ?? ''};

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'IS',
      title: 'Store',
      running: widget.running,
      onRun: () => widget.onRun(_params),
      body: _FieldRow(
        label: 'Table',
        field: widget.tables.isEmpty
            ? Container(
                height: 24,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: kAdminSurfaceLow,
                  border: Border.all(color: kAdminBorder),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('loading…',
                    style: inter(fontSize: 10, color: kAdminTextDim)),
              )
            : _dropdownField<String>(
                value: _table,
                items: widget.tables
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _table = v);
                  widget.onParamsChanged?.call({'table': v ?? ''});
                },
              ),
      ),
    );
  }
}

// ── IW — InsightWhisper ────────────────────────────────────────────────────

class IWCard extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  const IWCard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
  });

  @override
  State<IWCard> createState() => _IWCardState();
}

class _IWCardState extends State<IWCard> {
  final _videoId = TextEditingController();

  Map<String, String> get _params => {'videoId': _videoId.text};

  void _notify() => widget.onParamsChanged?.call(_params);

  @override
  void dispose() {
    _videoId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'IW',
      title: 'Whisper',
      running: widget.running,
      onRun: () => widget.onRun(_params),
      body: _FieldRow(
        label: 'Video ID',
        field: _inputField(_videoId,
            hint: 'yt video_id', onChanged: _notify),
      ),
    );
  }
}

// ── _inputField helper with onChanged ─────────────────────────────────────

Widget _inputField(
  TextEditingController ctrl, {
  String hint = '',
  TextInputType keyboardType = TextInputType.text,
  VoidCallback? onChanged,
}) =>
    Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: kAdminSurfaceLow,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: inter(fontSize: 10, color: kAdminText),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: inter(fontSize: 10, color: kAdminTextDim),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
        onChanged: (_) => onChanged?.call(),
      ),
    );
