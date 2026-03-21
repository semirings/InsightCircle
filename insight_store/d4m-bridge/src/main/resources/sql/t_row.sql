-- File: src/main/resources/sql/t_row.sql
SELECT 
    row_id,
    -- Returns the sparse array as a list of key-value structs
    ARRAY(SELECT AS STRUCT key, value FROM UNNEST(metadata)) AS associative_row
FROM 
    `${projectId}.${datasetId}.${tableName}`
WHERE 
    row_id = @rowId