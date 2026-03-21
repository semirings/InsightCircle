package d4m.bridge;

import java.nio.file.Files;
import java.nio.file.Paths;

@Repository
public class BigQueryD4MBridge {
    private final BigQuery bigQuery;
    
    public BigQueryD4MBridge(BigQuery bigQuery) {
        this.bigQuery = bigQuery;
    }

    /**
     * Point Lookup: Intersection of a specific Row and Column.
     */
    public TableResult queryPoint(String row, String col) throws Exception {
        String sql = loadSql("/sql/t_point.sql"); // SELECT * FROM table WHERE row_key = @row AND col_key = @col
        QueryJobConfiguration queryConfig = QueryJobConfiguration.newBuilder(sql)
            .addNamedParameter("row", QueryParameterValue.string(row))
            .addNamedParameter("col", QueryParameterValue.string(col))
            .build();
        return bigQuery.query(queryConfig);
    }

    public TableResult queryRows(String tableName, String rowKey) throws Exception {
        // Load the SQL template from resources
        String sql = new String(Files.readAllBytes(
            Paths.get(getClass().getResource("/sql/t_row.sql").toURI())));

        // Parametrize for BigQuery (Protects against SQL injection)
        QueryJobConfiguration queryConfig = QueryJobConfiguration.newBuilder(sql)
            .addNamedParameter("row_key", QueryParameterValue.string(rowKey))
            .addNamedParameter("table_id", QueryParameterValue.string(tableName))
            .build();

        return bigQuery.query(queryConfig);
    }

    /**
     * Column Lookup: All rows for a specific attribute.
     */
    public TableResult queryCols(String col) throws Exception {
        String sql = loadSql("/sql/t_col.sql"); // SELECT * FROM table WHERE col_key = @col
        QueryJobConfiguration queryConfig = QueryJobConfiguration.newBuilder(sql)
            .addNamedParameter("col", QueryParameterValue.string(col))
            .build();
        return bigQuery.query(queryConfig);
    }
}