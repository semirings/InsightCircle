import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const InsightApp());
}

class InsightApp extends StatelessWidget {
  const InsightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InsightCircle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const IngestPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Ingest page
// ---------------------------------------------------------------------------

class IngestPage extends StatefulWidget {
  const IngestPage({super.key});

  @override
  State<IngestPage> createState() => _IngestPageState();
}

class _IngestPageState extends State<IngestPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _tableController = TextEditingController();

  bool _loading = false;
  IngestResult? _result;

  static const _ingestUrl = 'http://localhost:5201/ingest';

  @override
  void dispose() {
    _urlController.dispose();
    _tableController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // HTTP helper – POST to insight_calc /ingest
  // ---------------------------------------------------------------------------

  Future<IngestResult> _postIngest(String url, String tableName) async {
    debugPrint('[IngestPage] POST $_ingestUrl url=$url table=$tableName');
    try {
      final response = await http
          .post(
            Uri.parse(_ingestUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': url, 'table_name': tableName}),
          )
          .timeout(const Duration(seconds: 60));

      debugPrint('[IngestPage] Response ${response.statusCode}: ${response.body}');
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return IngestResult.fromJson(body);
      }
      // Non-200 — surface the error detail from FastAPI
      final detail = body['detail']?.toString() ?? 'HTTP ${response.statusCode}';
      return IngestResult(success: false, detail: detail);
    } on Exception catch (e) {
      debugPrint('[IngestPage] Error: $e');
      return IngestResult(success: false, detail: e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Submit handler
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _result = null;
    });

    final result = await _postIngest(
      _urlController.text.trim(),
      _tableController.text.trim(),
    );

    setState(() {
      _loading = false;
      _result = result;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('InsightCircle – Ingest')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // URL or file-path input
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'YouTube URL or file path',
                      hintText: 'https://www.youtube.com/watch?v=… or /path/to/urls.txt',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Table name input
                  TextFormField(
                    controller: _tableController,
                    decoration: const InputDecoration(
                      labelText: 'Table name',
                      hintText: 'Must already exist in Accumulo',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Ingest'),
                  ),
                  const SizedBox(height: 24),

                  // Result card
                  if (_result != null) _ResultCard(result: _result!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result display
// ---------------------------------------------------------------------------

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final IngestResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.success ? Colors.green.shade700 : Colors.red.shade700;
    final icon = result.success ? Icons.check_circle : Icons.error;
    final label = result.success ? 'Success' : 'Failed';

    return Card(
      color: result.success ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            if (result.videoId != null) ...[
              const SizedBox(height: 8),
              Text('Video ID: ${result.videoId}'),
            ],
            if (result.storeStatus != null) ...[
              const SizedBox(height: 4),
              Text('Store status: ${result.storeStatus}'),
            ],
            if (result.detail != null) ...[
              const SizedBox(height: 4),
              Text(result.detail!,
                  style: TextStyle(color: color, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class IngestResult {
  final bool success;
  final String? videoId;
  final int? storeStatus;
  final String? detail;

  const IngestResult({
    required this.success,
    this.videoId,
    this.storeStatus,
    this.detail,
  });

  factory IngestResult.fromJson(Map<String, dynamic> json) => IngestResult(
        success: json['success'] as bool,
        videoId: json['video_id'] as String?,
        storeStatus: json['store_status'] as int?,
        detail: json['detail'] as String?,
      );
}
