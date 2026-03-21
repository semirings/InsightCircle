-- File: src/main/resources/sql/t_col.sql
SELECT 
    row_id,
    m.value AS val
FROM 
    `${projectId}.${datasetId}.${tableName}`,
    UNNEST(metadata) AS m
WHERE 
    SEARCH(m.key, @colKey) 
    AND m.key = @colKey