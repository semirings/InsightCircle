import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme.dart';

const _kIngestFilesUrl = 'http://localhost:5203/ingest_files';

// ── Palette ────────────────────────────────────────────────────────────────

const _kCardBg    = kGray500;           // mid grey  #6B7280
const _kDarkGreen = Color(0xFF1B5E20);  // dark green

// ── Public widget ──────────────────────────────────────────────────────────

/// Action card – Ingest
///
/// Displays a pick-list of files from the GCS `ingest/` bucket, an option to
/// add a new file name, and a "Go" button (enabled only when a file is
/// selected).  Sized to fit inside the 300 px sidebar.
class IngestActionCard extends StatefulWidget {
  /// Called when the Go button is tapped.  Receives the selected file name.
  final void Function(String fileName)? onGo;

  /// Files already present in `gs://<bucket>/ingest/`.
  /// Wire this up to a real GCS listing in production.
  final List<String> bucketFiles;

  const IngestActionCard({
    super.key,
    this.onGo,
    this.bucketFiles = const [],
  });

  @override
  State<IngestActionCard> createState() => _IngestActionCardState();
}

class _IngestActionCardState extends State<IngestActionCard> {
  String? _selected;
  bool _addingNew = false;
  bool _loading = false;
  final _newFileCtrl = TextEditingController();
  late List<String> _files;

  @override
  void initState() {
    super.initState();
    _files = List<String>.from(widget.bucketFiles);
    _fetchFiles();
  }

  Future<void> _fetchFiles() async {
    setState(() => _loading = true);
    try {
      final response = await http.get(Uri.parse(_kIngestFilesUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _files = data.cast<String>();
        });
      }
    } catch (_) {
      // keep whatever was seeded via widget.bucketFiles
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _newFileCtrl.dispose();
    super.dispose();
  }

  void _confirmNewFile() {
    final name = _newFileCtrl.text.trim();
    setState(() {
      if (name.isNotEmpty && !_files.contains(name)) {
        _files.add(name);
        _selected = name;
      }
      _addingNew = false;
      _newFileCtrl.clear();
    });
  }

  void _cancelNewFile() {
    setState(() {
      _addingNew = false;
      _newFileCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _kCardBg,
        border: Border.all(color: kBlack, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Title ────────────────────────────────────────────────────────
          Text(
            'Ingest',
            textAlign: TextAlign.center,
            style: spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // ── Bucket pick-list ─────────────────────────────────────────────
          _loading
              ? const Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                )
              : _BucketDropdown(
                  files: _files,
                  selected: _selected,
                  onChanged: (v) => setState(() => _selected = v),
                ),
          const SizedBox(height: 8),

          // ── Add-new-file row ─────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: _addingNew
                ? _NewFileRow(
                    key: const ValueKey('new'),
                    controller: _newFileCtrl,
                    onConfirm: _confirmNewFile,
                    onCancel: _cancelNewFile,
                  )
                : _AddFileChip(
                    key: const ValueKey('chip'),
                    onTap: () => setState(() => _addingNew = true),
                  ),
          ),
          const SizedBox(height: 16),

          // ── Go button ────────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: _GoButton(
              enabled: _selected != null,
              onPressed:
                  _selected != null ? () => widget.onGo?.call(_selected!) : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bucket drop-down ───────────────────────────────────────────────────────

class _BucketDropdown extends StatelessWidget {
  final List<String> files;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _BucketDropdown({
    required this.files,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          hint: Text(
            'ingest/ — select a file',
            style: inter(fontSize: 12, color: Colors.white70),
          ),
          isExpanded: true,
          dropdownColor: kGray600,
          iconEnabledColor: Colors.white70,
          items: files
              .map(
                (f) => DropdownMenuItem(
                  value: f,
                  child: Text(
                    f,
                    overflow: TextOverflow.ellipsis,
                    style: inter(fontSize: 12, color: Colors.white),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Add-file chip ──────────────────────────────────────────────────────────

class _AddFileChip extends StatefulWidget {
  final VoidCallback onTap;
  const _AddFileChip({super.key, required this.onTap});

  @override
  State<_AddFileChip> createState() => _AddFileChipState();
}

class _AddFileChipState extends State<_AddFileChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline,
                size: 14,
                color: _hovered ? Colors.white : Colors.white60),
            const SizedBox(width: 4),
            Text(
              'Add new file',
              style: inter(
                fontSize: 11,
                color: _hovered ? Colors.white : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── New-file input row ─────────────────────────────────────────────────────

class _NewFileRow extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _NewFileRow({
    super.key,
    required this.controller,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller: controller,
              autofocus: true,
              style: inter(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'file name…',
                hintStyle: inter(fontSize: 12, color: Colors.white38),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
              ),
              onSubmitted: (_) => onConfirm(),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _IconBtn(icon: Icons.check, color: _kDarkGreen, onTap: onConfirm),
        const SizedBox(width: 2),
        _IconBtn(icon: Icons.close, color: kGray400, onTap: onCancel),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

// ── Go button ──────────────────────────────────────────────────────────────

class _GoButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onPressed;
  const _GoButton({required this.enabled, this.onPressed});

  @override
  State<_GoButton> createState() => _GoButtonState();
}

class _GoButtonState extends State<_GoButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.enabled
        ? (_hovered ? const Color(0xFF2E7D32) : _kDarkGreen)
        : kGray600;

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: kBlack),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Go',
            style: inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: widget.enabled ? Colors.white : Colors.white38,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
