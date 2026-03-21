-- File: src/main/resources/sql/t_point.sql
SELECT 
    row_id,
    m.value AS val
FROM 
    `${projectId}.${datasetId}.${tableName}`,
    UNNEST(metadata) AS m
WHERE 
    row_id = @rowId 
    AND m.key = @colKey