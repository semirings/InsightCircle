package d4m.bridge;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.google.cloud.bigquery.BigQuery;
import com.google.cloud.bigquery.InsertAllRequest;
import com.google.cloud.bigquery.InsertAllResponse;
import com.google.cloud.bigquery.TableId;

@Service
public class InsertService extends BaseService {

    private static final Logger log = LoggerFactory.getLogger(InsertService.class);

    InsertService(BigQuery bigQuery, String projectId, String datasetId) {
        super(bigQuery, projectId, datasetId);
    }

    public void insertPair(RCVs rcvs, String tableName) {
        log.trace("insertPair=={}", tableName);
        try {
            insertIntoTable(rcvs.getRows(), rcvs.getCols(), rcvs.getVals(), tableName);
            insertIntoTable(rcvs.getCols(), rcvs.getRows(), rcvs.getVals(), tableName + PAIR_DECOR);
            bumpDegrees(rcvs.getRows(), rcvs.getCols(), tableName + DEGREE_DECOR);
        } catch (Exception e) {
            log.error("Failed to insert into table pair", e);
        }
    }

    private void insertIntoTable(String[] rows, String[] cols, String[] vals, String table) {
        log.trace("insertIntoTable=={}", table);
        TableId tableId = TableId.of(projectId, datasetId, table);
        List<InsertAllRequest.RowToInsert> bqRows = new ArrayList<>(rows.length);
        for (int i = 0; i < rows.length; i++) {
            Map<String, Object> row = new HashMap<>();
            row.put("row", rows[i]);
            row.put("col", cols[i]);
            row.put("val", vals[i]);
            bqRows.add(InsertAllRequest.RowToInsert.of(row));
        }
        InsertAllResponse response = bigQuery.insertAll(InsertAllRequest.of(tableId, bqRows));
        if (response.hasErrors()) {
            throw new RuntimeException("BigQuery insert errors: " + response.getInsertErrors());
        }
    }

    private void bumpDegrees(String[] rows, String[] cols, String degreeTable) {
        Map<String, Integer> delta = new HashMap<>(rows.length * 2);
        for (int i = 0; i < rows.length; i++) {
            delta.merge(rows[i], 1, Integer::sum);
            delta.merge(cols[i], 1, Integer::sum);
        }
        TableId tableId = TableId.of(projectId, datasetId, degreeTable);
        List<InsertAllRequest.RowToInsert> bqRows = new ArrayList<>(delta.size());
        for (Map.Entry<String, Integer> e : delta.entrySet()) {
            Map<String, Object> row = new HashMap<>();
            row.put("row", e.getKey());
            row.put("col", "deg.count");
            row.put("val", Integer.toString(e.getValue()));
            bqRows.add(InsertAllRequest.RowToInsert.of(row));
        }
        InsertAllResponse response = bigQuery.insertAll(InsertAllRequest.of(tableId, bqRows));
        if (response.hasErrors()) {
            throw new RuntimeException("BigQuery degree insert errors: " + response.getInsertErrors());
        }
    }
}
