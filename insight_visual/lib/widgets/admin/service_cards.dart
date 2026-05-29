import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/execution_status.dart';
import '../../models/step_result.dart';
import '../../theme.dart';

typedef RunCallback            = void Function(Map<String, String> params);
typedef ParamsChangedCallback  = void Function(Map<String, String> params);
typedef FetchKeywordsCallback  = Future<List<String>> Function(List<String> urls);

// ── Per-card status indicator (elapsed timer + result badge) ──────────

class _CardStatus extends StatefulWidget {
  final bool       running;
  final StepResult? lastResult;
  const _CardStatus({required this.running, this.lastResult});
  @override
  State<_CardStatus> createState() => _CardStatusState();
}

class _CardStatusState extends State<_CardStatus> {
  Timer? _timer;
  int    _elapsed = 0;

  @override
  void didUpdateWidget(_CardStatus old) {
    super.didUpdateWidget(old);
    if (widget.running && !old.running) {
      _elapsed = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed++);
      });
    } else if (!widget.running) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.running) {
      return Text(_fmt(_elapsed),
          style: inter(fontSize: 9, color: kAdminTextMuted));
    }
    final r = widget.lastResult;
    if (r == null) return const SizedBox.shrink();
    final ok    = r.status == ExecutionStatus.succeeded;
    final color = ok ? kAdminGreen : kAdminAccent;
    final dur   = r.duration;
    final label = (!ok && r.errorMessage != null)
        ? r.errorMessage!.substring(0, r.errorMessage!.length.clamp(0, 28))
        : (dur != null ? _fmt(dur.inSeconds) : (ok ? 'ok' : 'failed'));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 10, color: color),
      const SizedBox(width: 3),
      Text(label, style: inter(fontSize: 9, color: color)),
    ]);
  }
}

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
  final StepResult? lastResult;

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
    this.lastResult,
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
        if (running) ...[
          const SizedBox(
            width: 10, height: 10,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: kAdminAccent),
          ),
          const SizedBox(width: 6),
        ],
        _CardStatus(running: running, lastResult: lastResult),
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
    const kRunGreen      = Color(0xFF1B5E20);
    const kRunGreenHover = Color(0xFF2E7D32);
    final bg = enabled
        ? (_hovered ? kRunGreenHover : kRunGreen)
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
                  fontSize: 11,
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
                    fontSize: 11,
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
  final FetchKeywordsCallback? onFetchKeywords;
  final StepResult? lastResult;

  const IICard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.onFetchKeywords,
    this.running = false,
    this.lastResult,
  });

  @override
  State<IICard> createState() => _IICardState();
}

class _IICardState extends State<IICard> {
  String        _phase          = 'all';
  final List<String>  _keywords  = [];
  final _count       = TextEditingController();
  final _minViews    = TextEditingController();
  final _maxViews    = TextEditingController();
  final _minSubs     = TextEditingController();
  final _maxSubs     = TextEditingController();
  final _seedUrlCtrl   = TextEditingController();
  final _directUrlCtrl = TextEditingController();
  bool  _skipDuplicates   = true;
  bool  _fetchingKeywords = false;

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
        'directUrls':      _directUrlCtrl.text,
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

  Future<void> _fetchSeedKeywords() async {
    final fn = widget.onFetchKeywords;
    if (fn == null) return;
    final urls = _seedUrlCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;
    _update(() => _fetchingKeywords = true);
    try {
      final keywords = await fn(urls);
      _update(() {
        for (final kw in keywords) {
          if (!_keywords.contains(kw)) _keywords.add(kw);
        }
        _seedUrlCtrl.clear();
      });
      _notify();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) _update(() => _fetchingKeywords = false);
    }
  }

  @override
  void dispose() {
    _overlay?.remove();
    _count.dispose();
    _minViews.dispose();
    _maxViews.dispose();
    _minSubs.dispose();
    _maxSubs.dispose();
    _seedUrlCtrl.dispose();
    _directUrlCtrl.dispose();
    super.dispose();
  }

  // ── Collapsed body (inline) ──────────────────────────────────────────

  Widget _buildCollapsedBody() {
    final isDirect = _directUrlCtrl.text.trim().isNotEmpty;
    return Column(
      children: [
        _FieldRow(
          label: 'Direct URLs',
          field: _inputField(_directUrlCtrl,
              hint: 'youtu.be/… one per line',
              onChanged: () { _update(() {}); _notify(); }),
        ),
        if (!isDirect) ...[
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
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SEED URLS',
                  style: inter(fontSize: 11, fontWeight: FontWeight.w700,
                      color: kAdminTextDim, letterSpacing: 0.5)),
              const SizedBox(height: 3),
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: kAdminSurfaceLow,
                  border: Border.all(color: kAdminBorder),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: TextField(
                  controller: _seedUrlCtrl,
                  maxLines: null,
                  style: inter(fontSize: 9, color: kAdminText),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'paste YouTube URLs, one per line…',
                    hintStyle: inter(fontSize: 9, color: kAdminTextDim),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              MouseRegion(
                cursor: (_fetchingKeywords || widget.onFetchKeywords == null)
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: (_fetchingKeywords || widget.onFetchKeywords == null)
                      ? null
                      : _fetchSeedKeywords,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kAdminSurfaceLow,
                      border: Border.all(color: kAdminBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: _fetchingKeywords
                        ? const SizedBox(
                            width: 10, height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: kAdminAccent),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.label_outline,
                                  size: 10, color: kAdminTextDim),
                              const SizedBox(width: 4),
                              Text('Fetch Keywords',
                                  style: inter(fontSize: 9, color: kAdminTextMuted)),
                            ],
                          ),
                  ),
                ),
              ),
            ],
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
      lastResult:      widget.lastResult,
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
  final StepResult? lastResult;

  const I2Card({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
    this.externalJobId,
    this.lastResult,
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
      final id = widget.externalJobId!;
      final now = DateTime.now().toUtc();
      final date = '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      _jobId.text = id;
      if (_date.text.isEmpty) _date.text = date;
      final d = _date.text;
      _metaUri.text        = 'gs://insightcircle_bucket/ingest/$d/${id}_meta.jsonl';
      _commentsUri.text    = 'gs://insightcircle_bucket/ingest/$d/${id}_comments.jsonl';
      _transcriptsUri.text = 'gs://insightcircle_bucket/ingest/$d/${id}_transcripts.jsonl';
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
      serviceId:  'I2',
      title:      'Ontology',
      running:    widget.running,
      lastResult: widget.lastResult,
      onRun:      () => widget.onRun(_params),
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
  final List<String> videoIds;
  final bool videoIdsLoading;
  final StepResult? lastResult;

  const ITCard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
    this.videoIds = const [],
    this.videoIdsLoading = false,
    this.lastResult,
  });

  @override
  State<ITCard> createState() => _ITCardState();
}

class _ITCardState extends State<ITCard> {
  final Set<String> _selected = {};

  Map<String, String> get _params => {'videoIds': _selected.join(',')};
  void _notify() => widget.onParamsChanged?.call(_params);

  void _selectAll() {
    setState(() => _selected..clear()..addAll(widget.videoIds));
    WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
  }

  void _clearAll() {
    setState(() => _selected.clear());
    WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: kAdminTextMuted, fontSize: 11);
    return ServiceCard(
      serviceId:  'IT',
      title:      'Token',
      running:    widget.running,
      lastResult: widget.lastResult,
      onRun:      () => widget.onRun(_params),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _linkBtn('All',  _selectAll),
              const SizedBox(width: 8),
              _linkBtn('None', _clearAll),
              const Spacer(),
              Text('${_selected.length} / ${widget.videoIds.length}',
                  style: muted),
            ],
          ),
          const SizedBox(height: 4),
          if (widget.videoIdsLoading)
            const Text('loading…', style: muted)
          else if (widget.videoIds.isEmpty)
            const Text('no videos found', style: muted)
          else
            SizedBox(
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kAdminSurfaceLow,
                  border: Border.all(color: kAdminBorder),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  itemCount: widget.videoIds.length,
                  itemBuilder: (ctx, i) {
                    final id      = widget.videoIds[i];
                    final checked = _selected.contains(id);
                    return InkWell(
                      onTap: () {
                        setState(() =>
                            checked ? _selected.remove(id) : _selected.add(id));
                        _notify();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14, height: 14,
                              child: Checkbox(
                                value: checked,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                activeColor: kAdminAccent,
                                side: const BorderSide(color: kAdminBorderMid),
                                onChanged: (v) {
                                  setState(() => v!
                                      ? _selected.add(id)
                                      : _selected.remove(id));
                                  _notify();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(id,
                                style: const TextStyle(
                                    color: kAdminText,
                                    fontSize: 11,
                                    fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _linkBtn(String label, VoidCallback onTap) => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(label,
              style: const TextStyle(
                  color: kAdminBlue,
                  fontSize: 11,
                  decoration: TextDecoration.underline)),
        ),
      ),
    );

// ── IC — InsightCalc ───────────────────────────────────────────────────────

class ICCard extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  final List<Map<String, String>> scripts;
  final StepResult? lastResult;

  const ICCard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
    this.scripts = const [],
    this.lastResult,
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
      serviceId:  'IC',
      title:      'Calc',
      running:    widget.running,
      lastResult: widget.lastResult,
      onRun:      () => widget.onRun(_params),
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
  final bool tablesLoading;
  final StepResult? lastResult;

  const ISCard({
    super.key,
    required this.onRun,
    required this.tables,
    this.onParamsChanged,
    this.running = false,
    this.tablesLoading = false,
    this.lastResult,
  });

  @override
  State<ISCard> createState() => _ISCardState();
}

class _ISCardState extends State<ISCard> {
  String? _table;

  Map<String, String> get _params => {'table': _table ?? ''};

  Widget _tableField() {
    if (widget.tablesLoading) {
      return Container(
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
      );
    }
    if (widget.tables.isEmpty) {
      return Container(
        height: 24,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: kAdminSurfaceLow,
          border: Border.all(color: kAdminBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text('no tables found',
            style: inter(fontSize: 10, color: kAdminTextDim)),
      );
    }
    return _dropdownField<String>(
      value: _table,
      items: widget.tables
          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
          .toList(),
      onChanged: (v) {
        setState(() => _table = v);
        widget.onParamsChanged?.call({'table': v ?? ''});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      serviceId:  'IS',
      title:      'Store',
      running:    widget.running,
      lastResult: widget.lastResult,
      onRun:      () => widget.onRun(_params),
      body: _FieldRow(
        label: 'Table',
        field: _tableField(),
      ),
    );
  }
}

// ── IW — InsightWhisper ────────────────────────────────────────────────────

class IWCard extends StatefulWidget {
  final bool running;
  final RunCallback onRun;
  final ParamsChangedCallback? onParamsChanged;
  final StepResult? lastResult;

  const IWCard({
    super.key,
    required this.onRun,
    this.onParamsChanged,
    this.running = false,
    this.lastResult,
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
      serviceId:  'IW',
      title:      'Whisper',
      running:    widget.running,
      lastResult: widget.lastResult,
      onRun:      () => widget.onRun(_params),
      body: _FieldRow(
        label: 'Video ID',
        field: _inputField(_videoId,
            hint: 'yt video_id', onChanged: _notify),
      ),
    );
  }
}
