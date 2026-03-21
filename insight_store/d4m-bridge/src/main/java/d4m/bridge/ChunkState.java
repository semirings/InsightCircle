package d4m.bridge;

public class ChunkState {

    private String tableName;
    private String payload;
    private String lastSeenRow;
    private String whereClause;   // SQL WHERE predicate built from the D4M query
    private int    currentOffset; // OFFSET for next BigQuery page
    private int    pageSize;      // LIMIT per chunk

    public ChunkState() {}

    public ChunkState(String tableName, String payload, String lastSeenRow,
                      String whereClause, int currentOffset, int pageSize) {
        this.tableName     = tableName;
        this.payload       = payload;
        this.lastSeenRow   = lastSeenRow;
        this.whereClause   = whereClause;
        this.currentOffset = currentOffset;
        this.pageSize      = pageSize;
    }

    public String getTableName()             { return tableName; }
    public void   setTableName(String v)     { this.tableName = v; }

    public String getPayload()               { return payload; }
    public void   setPayload(String v)       { this.payload = v; }

    public String getLastSeenRow()           { return lastSeenRow; }
    public void   setLastSeenRow(String v)   { this.lastSeenRow = v; }

    public String getWhereClause()           { return whereClause; }
    public void   setWhereClause(String v)   { this.whereClause = v; }

    public int    getCurrentOffset()         { return currentOffset; }
    public void   setCurrentOffset(int v)    { this.currentOffset = v; }

    public int    getPageSize()              { return pageSize; }
    public void   setPageSize(int v)         { this.pageSize = v; }
}
