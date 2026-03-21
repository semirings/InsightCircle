package d4m.bridge;

import java.util.Objects;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.cloud.bigquery.BigQuery;

/**
 * BaseService: Provides a BigQuery client and common D4M table decoration constants.
 * Subclasses use the protected fields for table operations and queries.
 */
public abstract class BaseService {

	private static final Logger log = LoggerFactory.getLogger(BaseService.class);

    // --- Constants accessible to subclasses ---
    protected static final String PAIR_DECOR   = "T";
    protected static final String DEGREE_DECOR = "Deg";

    // --- Protected client ---
    protected final BigQuery bigQuery;
    protected final String   projectId;
    protected final String   datasetId;

    protected BaseService(BigQuery bigQuery, String projectId, String datasetId) {
        log.info("BaseService==>");
        this.bigQuery   = Objects.requireNonNull(bigQuery,   "BigQuery must not be null");
        this.projectId  = Objects.requireNonNull(projectId,  "projectId must not be null");
        this.datasetId  = Objects.requireNonNull(datasetId,  "datasetId must not be null");
        log.debug("projectId=={} datasetId=={}", projectId, datasetId);
    }
}
