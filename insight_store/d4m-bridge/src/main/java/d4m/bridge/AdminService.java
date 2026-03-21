package d4m.bridge;

import java.util.SortedSet;
import java.util.TreeSet;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.google.cloud.bigquery.BigQuery;
import com.google.cloud.bigquery.CopyJobConfiguration;
import com.google.cloud.bigquery.Field;
import com.google.cloud.bigquery.Job;
import com.google.cloud.bigquery.JobInfo;
import com.google.cloud.bigquery.Schema;
import com.google.cloud.bigquery.StandardSQLTypeName;
import com.google.cloud.bigquery.StandardTableDefinition;
import com.google.cloud.bigquery.TableDefinition;
import com.google.cloud.bigquery.TableId;
import com.google.cloud.bigquery.TableInfo;

@Service
public class AdminService extends BaseService {

    private static final Logger log = LoggerFactory.getLogger(AdminService.class);

    /** D4M triple schema: every table (main, T, Deg) uses the same three columns. */
    private static final Schema D4M_SCHEMA = Schema.of(
        Field.of("row", StandardSQLTypeName.STRING),
        Field.of("col", StandardSQLTypeName.STRING),
        Field.of("val", StandardSQLTypeName.STRING)
    );

    AdminService(BigQuery bigQuery, String projectId, String datasetId) {
        super(bigQuery, projectId, datasetId);
    }

    public SortedSet<String> listTables() {
        log.info("listTables==>");
        SortedSet<String> names = new TreeSet<>();
        bigQuery.listTables(datasetId).iterateAll()
                .forEach(t -> names.add(t.getTableId().getTable()));
        return names;
    }

    public String currentUser() {
        log.info("user==whoami");
        return projectId;
    }

    public String createTable(String tableName) {
        log.debug("tableName=={}", tableName);
        TableId tableId = TableId.of(projectId, datasetId, tableName);
        TableDefinition def = StandardTableDefinition.of(D4M_SCHEMA);
        bigQuery.create(TableInfo.of(tableId, def));
        return tableName;
    }

    public String createTablePair(String tableName) {
        log.info("tableName=={} {}", 1, tableName);
        log.debug("create pair==> -1");
        if (!tableExists(tableName)) {
            log.debug("create pair==> 0");
            createTable(tableName);
            log.debug("create pair==> 1");
            createTable(tableName.concat(PAIR_DECOR));
            createTable(tableName.concat(DEGREE_DECOR));
            log.debug("tableName=={} {}", 2, tableName);
        } else {
            log.debug("Table {} exists", tableName);
        }
        return tableName;
    }

    public boolean isOnline(String tableName) {
        log.info("isOnline=={}", tableName);
        return tableExists(tableName);
    }

    public String rename(String oldName, String newName) {
        log.info("rename=={} {} == . {}", 1, oldName, newName);
        log.debug("rename==> -1");
        if (tableExists(oldName)) {
            log.debug("rename==> 0");
            TableId src = TableId.of(projectId, datasetId, oldName);
            TableId dst = TableId.of(projectId, datasetId, newName);
            CopyJobConfiguration cfg = CopyJobConfiguration.of(dst, src);
            try {
                Job job = bigQuery.create(JobInfo.of(cfg));
                job.waitFor();
                bigQuery.delete(src);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("Rename interrupted", e);
            }
            log.info("tableName=={} {} ==> {}", 2, oldName, newName);
        } else {
            log.debug("Table {} !exists", oldName);
        }
        return newName;
    }

    public String dropTablePair(String tableName) {
        log.trace("tableName=={} {}", 1, tableName);
        if (tableExists(tableName)) {
            bigQuery.delete(TableId.of(projectId, datasetId, tableName));
            bigQuery.delete(TableId.of(projectId, datasetId, tableName + PAIR_DECOR));
            bigQuery.delete(TableId.of(projectId, datasetId, tableName + DEGREE_DECOR));
            log.trace("tableName=={} {}", 2, tableName);
        } else {
            log.info("Table {} does not exist", tableName);
        }
        return tableName;
    }

    private boolean tableExists(String tableName) {
        return bigQuery.getTable(TableId.of(projectId, datasetId, tableName)) != null;
    }
}
