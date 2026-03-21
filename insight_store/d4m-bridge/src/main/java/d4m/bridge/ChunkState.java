package d4m.bridge;

import java.util.List;

import org.apache.accumulo.core.data.Range;

public class ChunkState {
    
    private String tableName;
    private String payload;
    private String lastSeenRow;
    private List<Range> ranges;
    private int currentIndex = 0;

    public ChunkState() {}

    public ChunkState(String tableName, String payload, String lastSeenRow, List<Range> ranges) {
        this.tableName = tableName;
        this.payload = payload;
        this.lastSeenRow = lastSeenRow;
        this.ranges = ranges;
    }

     public String getTableName() {
        return tableName;
    }

    public void setTableName(String tableName) {
        this.tableName = tableName;
    }

    public String getPayload() {
        return payload;
    }

    public void setPayload(String payload) {
        this.payload = payload;
    }

    public String getLastSeenRow() {
        return lastSeenRow;
    }

    public void setLastSeenRow(String lastSeenRow) {
        this.lastSeenRow = lastSeenRow;
    }

    public void setRanges(List<Range> ranges) {
        this.ranges = ranges;
    }

    public List<Range> getRanges() {
        return ranges;
    }

    public int getCurrentIndex() {
        return currentIndex;
    }

    public void setCurrentIndex(int currentIndex) {
        this.currentIndex = currentIndex;
    }
}