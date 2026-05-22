import 'package:googleapis/bigquery/v2.dart' as bq;
import 'package:googleapis_auth/auth_io.dart';

const _pollInterval = Duration(seconds: 3);

class BigQueryService {
  BigQueryService._();

  static Future<BigQueryService> create() async {
    final svc = BigQueryService._();
    await svc._init();
    return svc;
  }

  late final bq.BigqueryApi _api;

  Future<void> _init() async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: [bq.BigqueryApi.cloudPlatformScope],
    );
    _api = bq.BigqueryApi(client);
  }

  Future<List<Map<String, dynamic>>> runQuery(
    String projectId,
    String query,
  ) async {
    final job = await _api.jobs.insert(
      bq.Job(
        configuration: bq.JobConfiguration(
          query: bq.JobConfigurationQuery(
            query: query,
            useLegacySql: false,
          ),
        ),
      ),
      projectId,
    );

    final jobId = job.jobReference!.jobId!;
    bq.Job status;
    do {
      await Future<void>.delayed(_pollInterval);
      status = await _api.jobs.get(projectId, jobId);
    } while (status.status?.state != 'DONE');

    if (status.status?.errorResult != null) {
      throw Exception(status.status!.errorResult!.message);
    }

    final result = await _api.jobs.getQueryResults(projectId, jobId);
    return _rowsToMaps(result.schema, result.rows ?? []);
  }

  Future<List<String>> listTables(String projectId, String datasetId) async {
    final resp = await _api.tables.list(projectId, datasetId);
    return (resp.tables ?? [])
        .map((t) => t.tableReference?.tableId ?? '')
        .where((id) => id.isNotEmpty)
        .toList()
      ..sort();
  }

  Future<List<Map<String, dynamic>>> fetchTablePreview(
    String projectId,
    String datasetId,
    String tableId, {
    int maxRows = 100,
  }) async {
    final schema = await _api.tables.get(projectId, datasetId, tableId);
    final data = await _api.tabledata.list(
      projectId,
      datasetId,
      tableId,
      maxResults: maxRows,
    );
    return _rowsToMaps(schema.schema, data.rows ?? []);
  }

  List<Map<String, dynamic>> _rowsToMaps(
    bq.TableSchema? schema,
    List<bq.TableRow> rows,
  ) {
    final fields = schema?.fields ?? [];
    return rows.map((row) {
      final cells = row.f ?? [];
      return {
        for (var i = 0; i < fields.length && i < cells.length; i++)
          fields[i].name!: cells[i].v,
      };
    }).toList();
  }
}
