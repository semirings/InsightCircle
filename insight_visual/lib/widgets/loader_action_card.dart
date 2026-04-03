import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme.dart';

// ── Palette ────────────────────────────────────────────────────────────────

const _kCardBg    = kGray500;
const _kDarkGreen = Color(0xFF1B5E20);

const _kIngestFilesUrl = 'http://localhost:5203/ingest_files';
const _kBqTablesUrl = 'http://localhost:5203/metadata/tables';

// ── Public widget ──────────────────────────────────────────────────────────

/// Action card – Loader
///
/// Two pick-lists: source file from the ingest/ bucket, and destination BQ
/// table.  A "Go" button is enabled only when both are selected.
class LoaderActionCard extends StatefulWidget {
  /// Called when Go is tapped. Receives the selected file and table names.
  final void Function(String fileName, String tableName)? onGo;

  const LoaderActionCard({super.key, this.onGo});

  @override
  State<LoaderActionCard> createState() => _LoaderActionCardState();
}

class _LoaderActionCardState extends State<LoaderActionCard> {
  String? _selectedFile;
  String? _selectedTable;
  bool _loadingFiles  = false;
  bool _loadingTables = false;
  List<String> _files  = [];
  List<String> _tables = [];

  @override
  void initState() {
    super.initState();
    _fetchFiles();
    _fetchTables();
  }

  Future<void> _fetchFiles() async {
    setState(() => _loadingFiles = true);
    try {
      final response = await http.get(Uri.parse(_kIngestFilesUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() => _files = data.cast<String>());
      }
    } catch (_) {
      // keep empty list
    } finally {
      if (mounted) setState(() => _loadingFiles = false);
    }
  }

  Future<void> _fetchTables() async {
    setState(() => _loadingTables = true);
    try {
      final response = await http.get(Uri.parse(_kBqTablesUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() => _tables = data.cast<String>());
      }
    } catch (_) {
      // keep empty list
    } finally {
      if (mounted) setState(() => _loadingTables = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGo = _selectedFile != null && _selectedTable != null;

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
          // ── Title ──────────────────────────────────────────────────────────
          Text(
            'Loader',
            textAlign: TextAlign.center,
            style: spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // ── Source file pick-list ──────────────────────────────────────────
          Text(
            'Source file',
            style: inter(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 4),
          _loadingFiles
              ? const _Spinner()
              : _Dropdown(
                  hint: 'ingest/ — select a file',
                  items: _files,
                  selected: _selectedFile,
                  onChanged: (v) => setState(() => _selectedFile = v),
                ),
          const SizedBox(height: 10),

          // ── Destination BQ table pick-list ─────────────────────────────────
          Text(
            'Destination table',
            style: inter(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 4),
          _loadingTables
              ? const _Spinner()
              : _Dropdown(
                  hint: 'BigQuery — select a table',
                  items: _tables,
                  selected: _selectedTable,
                  onChanged: (v) => setState(() => _selectedTable = v),
                ),
          const SizedBox(height: 16),

          // ── Go button ──────────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: _GoButton(
              enabled: canGo,
              onPressed: canGo
                  ? () => widget.onGo?.call(_selectedFile!, _selectedTable!)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared drop-down ───────────────────────────────────────────────────────

class _Dropdown extends StatelessWidget {
  final String hint;
  final List<String> items;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _Dropdown({
    required this.hint,
    required this.items,
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
          hint: Text(hint, style: inter(fontSize: 12, color: Colors.white70)),
          isExpanded: true,
          dropdownColor: kGray600,
          iconEnabledColor: Colors.white70,
          items: items
              .map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(
                      f,
                      overflow: TextOverflow.ellipsis,
                      style: inter(fontSize: 12, color: Colors.white),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Spinner ────────────────────────────────────────────────────────────────

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
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
