import 'dart:convert';

import 'package:flutter/material.dart';

import '../../theme.dart';

typedef RunCallback          = void Function(Map<String, String> params);
typedef ParamsChangedCallback = void Function(Map<String, String> params);

// ── Shared card chrome ─────────────────────────────────────────────────────

class ServiceCard extends StatelessWidget {
  final String serviceId;
  final String title;
  final Widget body;
  final VoidCallback onRun;
  final bool running;
  final bool expandable;
  final bool isExpanded;
  final VoidCallback? onExpandToggle;

  const ServiceCard({
    super.key,
    required this.serviceId,
    required this.title,
    required this.body,
    required this.onRun,
    this.running     = false,
    this.expandable  = false,
    this.isExpanded  = false,
    this.onExpandToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (isExpanded) return _buildPlaceholder();
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
          _buildHeader(),
          const SizedBox(height: 8),
          body,
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              _RunBtn(onTap: onRun, running: running),
              if (expandable) ...[
                const SizedBox(width: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onExpandToggle,
                    child: const Icon(Icons.open_in_full,
                        size: 11, color: kAdminTextDim),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: kAdminSurface.withValues(alpha: 0.4),
        border: Border.all(color: kAdminBorder.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _ServiceBadge(serviceId: serviceId),
          const SizedBox(width: 6),
          Text(title,
              style: spaceGrotesk(fontSize: 11, color: kAdminTextDim)),
          const Spacer(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onExpandToggle,
              child: const Icon(Icons.close_fullscreen,
                  size: 11, color: kAdminTextDim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _ServiceBadge(serviceId: serviceId),
        const SizedBox(width: 6),
        Text(title, style: spaceGrotesk(fontSize: 11, color: kAdminText)),
        const Spacer(),
        if (running)
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: kAdminAccent),
          ),
      ],
    );
  }
}

// ── Shared badge ───────────────────────────────────────────────────────────

class _ServiceBadge extends StatelessWidget {
  final String serviceId;
  const _ServiceBadge({required this.serviceId});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            letterSpacing: 0.5),
      ),
    );
  }
}

// ── Floating panel ─────────────────────────────────────────────────────────

class _FloatingPanel extends StatefulWidget {
  final String serviceId;
  final String title;
  final bool running;
  final Offset initialPos;
  final Widget body;
  final VoidCallback onRun;
  final VoidCallback onCollapse;

  const _FloatingPanel({
    required this.serviceId,
    required this.title,
    required this.running,
    required this.initialPos,
    required this.body,
    required this.onRun,
    required this.onCollapse,
  });

  @override
  State<_FloatingPanel> createState() => _FloatingPanelState();
}

class _FloatingPanelState extends State<_FloatingPanel> {
  late Offset _pos;

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPos;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: kAdminSurface,
            border:
                Border.all(color: kAdminAccent.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 20,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Draggable title bar ──
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) =>
                    setState(() => _pos += d.delta),
                child: Row(
                  children: [
                    _ServiceBadge(serviceId: widget.serviceId),
                    const SizedBox(width: 6),
                    Text(widget.title,
                        style: spaceGrotesk(
                            fontSize: 11, color: kAdminText)),
                    const SizedBox(width: 4),
                    const Icon(Icons.drag_indicator,
                        size: 12, color: kAdminTextDim),
                    const Spacer(),
                    if (widget.running)
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: kAdminAccent),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              widget.body,
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  _RunBtn(onTap: widget.onRun, running: widget.running),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onCollapse,
                      child: const Icon(Icons.close_fullscreen,
                          size: 11, color: kAdminTextDim),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Run button ─────────────────────────────────────────────────────────────

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
                      color: enabled ? kAdminText : kAdminTextDim)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Form helpers ───────────────────────────────────────────────────────────

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
            width: 70,
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

class _RangeRow extends StatelessWidget {
  final String label;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;
  final VoidCallback? onChanged;

  const _RangeRow({
    required this.label,
    required this.minCtrl,
    required this.maxCtrl,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      label: label,
      field: Row(
        children: [
          Expanded(
              child: _inputField(minCtrl,
                  hint: 'min',
                  keyboardType: TextInputType.number,
                  onChanged: onChanged)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text('–',
                style: inter(fontSize: 10, color: kAdminTextDim)),
          ),
          Expanded(
              child: _inputField(maxCtrl,
                  hint: 'max',
                  keyboardType: TextInputType.number,
                  onChanged: onChanged)),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: kAdminTextDim,
                    letterSpacing: 0.5)),
          ),
          Transform.scale(
            scale: 0.7,
            alignment: Alignment.centerLeft,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: kAdminAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Text(value ? 'on' : 'off',
              style: inter(fontSize: 9, color: kAdminTextMuted)),
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

// ── Keyword chip input ─────────────────────────────────────────────────────

class _ChipInput extends StatefulWidget {
  final List<String> chips;
  final void Function(String kw) onAdd;
  final void Function(int idx) onRemove;

  const _ChipInput({
    required this.chips,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  State<_ChipInput> createState() => _ChipInputState();
}

class _ChipInputState extends State<_ChipInput> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isNotEmpty) {
      widget.onAdd(t);
      _ctrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minHeight: 28),
      decoration: BoxDecoration(
        color: kAdminSurfaceLow,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (int i = 0; i < widget.chips.length; i++)
            _Chip(
              label: widget.chips[i],
              onDelete: () => widget.onRemove(i),
            ),
          SizedBox(
            width: 72,
            height: 18,
            child: TextField(
              controller: _ctrl,
              style: inter(fontSize: 10, color: kAdminText),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'add…',
                hintStyle: inter(fontSize: 10, color: kAdminTextDim),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onDelete;
  const _Chip({required this.label, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 3, 2),
      decoration: BoxDecoration(
        color: kAdminAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: inter(fontSize: 9, color: kAdminText)),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onDelete,
            child:
                const Icon(Icons.close, size: 9, color: kAdminTextDim),
          ),
        ],
      ),
    );
  }
}

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
  String        _phase          = 'all';
  final List<String>  _keywords  = [];
  final _count  = TextEditingController();
  final _minViews = TextEditingController();
  final _maxViews = TextEditingController();
  final _minSubs  = TextEditingController();
  final _maxSubs  = TextEditingController();
  bool  _skipDuplicates = true;

  bool           _floating = false;
  OverlayEntry?  _overlay;

  Map<String, String> get _params => {
        'phase':           _phase,
        'keywords':        jsonEncode(_keywords),
        'count':           _count.text,
        'minViews':        _minViews.text,
        'maxViews':        _maxViews.text,
        'minSubscribers':  _minSubs.text,
        'maxSubscribers':  _maxSubs.text,
        'skipDuplicates':  _skipDuplicates.toString(),
      };

  // setState + refresh overlay
  void _update(VoidCallback fn) {
    setState(fn);
    _overlay?.markNeedsBuild();
  }

  void _notify() {
    widget.onParamsChanged?.call(_params);
    _overlay?.markNeedsBuild();
  }

  void _expand(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final pos  = Offset(size.width * 0.28, size.height * 0.12);
    _overlay = OverlayEntry(
      builder: (_) => _FloatingPanel(
        serviceId:  'II',
        title:      'Ingest',
        running:    widget.running,
        initialPos: pos,
        body:       _buildExpandedBody(),
        onRun:      () => widget.onRun(_params),
        onCollapse: _collapse,
      ),
    );
    Overlay.of(context).insert(_overlay!);
    setState(() => _floating = true);
  }

  void _collapse() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() => _floating = false);
  }

  @override
  void dispose() {
    _overlay?.remove();
    _count.dispose();
    _minViews.dispose();
    _maxViews.dispose();
    _minSubs.dispose();
    _maxSubs.dispose();
    super.dispose();
  }

  // ── Collapsed body (inline) ──────────────────────────────────────────

  Widget _buildCollapsedBody() {
    return Column(
      children: [
        _FieldRow(
          label: 'Phase',
          field: _dropdownField<String>(
            value: _phase,
            items: ['all', '1', '2', '3']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) {
              _update(() => _phase = v ?? 'all');
              _notify();
            },
          ),
        ),
        _FieldRow(
          label: 'Keywords',
          field: _ChipInput(
            chips:    _keywords,
            onAdd:    (kw) { _update(() => _keywords.add(kw)); _notify(); },
            onRemove: (i)  { _update(() => _keywords.removeAt(i)); _notify(); },
          ),
        ),
        _FieldRow(
          label: 'Count',
          field: _inputField(_count,
              hint: '100',
              keyboardType: TextInputType.number,
              onChanged: _notify),
        ),
      ],
    );
  }

  // ── Expanded body (floating panel) ──────────────────────────────────

  Widget _buildExpandedBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldRow(
          label: 'Phase',
          field: _dropdownField<String>(
            value: _phase,
            items: ['all', '1', '2', '3']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) {
              _update(() => _phase = v ?? 'all');
              _notify();
            },
          ),
        ),
        _FieldRow(
          label: 'Keywords',
          field: _ChipInput(
            chips:    _keywords,
            onAdd:    (kw) { _update(() => _keywords.add(kw)); _notify(); },
            onRemove: (i)  { _update(() => _keywords.removeAt(i)); _notify(); },
          ),
        ),
        _FieldRow(
          label: 'Count',
          field: _inputField(_count,
              hint: '100',
              keyboardType: TextInputType.number,
              onChanged: _notify),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(color: kAdminBorder, height: 1),
        ),
        _RangeRow(
          label: 'Views',
          minCtrl: _minViews,
          maxCtrl: _maxViews,
          onChanged: _notify,
        ),
        _RangeRow(
          label: 'Subs',
          minCtrl: _minSubs,
          maxCtrl: _maxSubs,
          onChanged: _notify,
        ),
        _ToggleRow(
          label: 'Skip dups',
          value: _skipDuplicates,
          onChanged: (v) { _update(() => _skipDuplicates = v); _notify(); },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId:       'II',
      title:           'Ingest',
      running:         widget.running,
      expandable:      true,
      isExpanded:      _floating,
      onExpandToggle:  _floating ? _collapse : () => _expand(context),
      onRun:           () => widget.onRun(_params),
      body:            _buildCollapsedBody(),
    );
  }
}

// ── I2 — InsightOntology ───────────────────────────────────────────────────

class I2Card extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  final String? externalJobId;

  const I2Card({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
    this.externalJobId,
  });

  @override
  State<I2Card> createState() => _I2CardState();
}

class _I2CardState extends State<I2Card> {
  final _jobId          = TextEditingController();
  final _date           = TextEditingController();
  final _metaUri        = TextEditingController();
  final _commentsUri    = TextEditingController();
  final _transcriptsUri = TextEditingController();

  Map<String, String> get _params => {
        'jobId':          _jobId.text,
        'date':           _date.text,
        'metaUri':        _metaUri.text,
        'commentsUri':    _commentsUri.text,
        'transcriptsUri': _transcriptsUri.text,
      };

  void _notify() => widget.onParamsChanged?.call(_params);

  @override
  void didUpdateWidget(I2Card oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalJobId != null &&
        widget.externalJobId != oldWidget.externalJobId) {
      _jobId.text = widget.externalJobId!;
      _notify();
    }
  }

  @override
  void dispose() {
    _jobId.dispose();
    _date.dispose();
    _metaUri.dispose();
    _commentsUri.dispose();
    _transcriptsUri.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'I2',
      title:     'Ontology',
      running:   widget.running,
      onRun:     () => widget.onRun(_params),
      body: Column(
        children: [
          _FieldRow(
              label: 'Job ID',
              field: _inputField(_jobId,
                  hint: 'uuid', onChanged: _notify)),
          _FieldRow(
              label: 'Date',
              field: _inputField(_date,
                  hint: 'YYYY-MM-DD', onChanged: _notify)),
          _FieldRow(
              label: 'Meta',
              field: _inputField(_metaUri,
                  hint: 'gs://…/meta.jsonl', onChanged: _notify)),
          _FieldRow(
              label: 'Comments',
              field: _inputField(_commentsUri,
                  hint: 'gs://…/comments.jsonl', onChanged: _notify)),
          _FieldRow(
              label: 'Transcripts',
              field: _inputField(_transcriptsUri,
                  hint: 'gs://…/transcripts.jsonl', onChanged: _notify)),
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
  final String? externalVideoId;

  const ITCard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
    this.externalVideoId,
  });

  @override
  State<ITCard> createState() => _ITCardState();
}

class _ITCardState extends State<ITCard> {
  final _videoId = TextEditingController();

  Map<String, String> get _params => {'videoId': _videoId.text};
  void _notify() => widget.onParamsChanged?.call(_params);

  @override
  void didUpdateWidget(ITCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalVideoId != null &&
        widget.externalVideoId != oldWidget.externalVideoId) {
      _videoId.text = widget.externalVideoId!;
      _notify();
    }
  }

  @override
  void dispose() {
    _videoId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'IT',
      title:     'Token',
      running:   widget.running,
      onRun:     () => widget.onRun(_params),
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
  final List<Map<String, String>> scripts;

  const ICCard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
    this.scripts = const [],
  });

  @override
  State<ICCard> createState() => _ICCardState();
}

class _ICCardState extends State<ICCard> {
  String? _selected;

  Map<String, String> get _params => {'script': _selected ?? ''};
  void _notify() => widget.onParamsChanged?.call(_params);

  @override
  void didUpdateWidget(ICCard old) {
    super.didUpdateWidget(old);
    if (widget.scripts.isNotEmpty &&
        (_selected == null ||
            !widget.scripts.any((s) => s['name'] == _selected))) {
      _selected = widget.scripts.first['name'];
      _notify();
    }
  }

  String _description() {
    if (_selected == null) return '';
    return widget.scripts
            .firstWhere((s) => s['name'] == _selected,
                orElse: () => {})['description'] ??
        '';
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId: 'IC',
      title:     'Calc',
      running:   widget.running,
      onRun:     () => widget.onRun(_params),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldRow(
            label: 'Script',
            field: widget.scripts.isEmpty
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
                    value: _selected,
                    items: widget.scripts
                        .map((s) => DropdownMenuItem(
                              value: s['name'],
                              child: Text(s['name'] ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selected = v);
                      _notify();
                    },
                  ),
          ),
          if (_description().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 70),
              child: Text(
                _description(),
                style: inter(fontSize: 9, color: kAdminTextDim),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

// ── IS — InsightStore ──────────────────────────────────────────────────────

class ISCard extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
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
      title:     'Store',
      running:   widget.running,
      onRun:     () => widget.onRun(_params),
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
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text(t)))
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
      title:     'Whisper',
      running:   widget.running,
      onRun:     () => widget.onRun(_params),
      body: _FieldRow(
        label: 'Video ID',
        field: _inputField(_videoId,
            hint: 'yt video_id', onChanged: _notify),
      ),
    );
  }
}
