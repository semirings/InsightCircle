package d4m.bridge;

import com.fasterxml.jackson.databind.JsonNode;

public class D4MRequest {
    
    private JsonNode payload;
    private String tableName;

    public JsonNode getPayload() {
        return payload;
    }

    public String getTableName() {
        return tableName;
    }

    public void setTableName(String tableName) {
        this.tableName = tableName;
    } 

    public String toString() {
        return String.format("Payload==%s Tab==%s", payload, tableName);
    }
}
