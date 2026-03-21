package d4m.gateway;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.google.cloud.bigquery.BigQuery;
import com.google.cloud.bigquery.BigQueryOptions;

/**
 * Spring configuration for the BigQuery client.
 *
 * Credentials are resolved automatically via Application Default Credentials (ADC):
 *   - Locally: run  gcloud auth application-default login
 *   - Cloud Run / GCE: the attached service account is used automatically
 *
 * Required env vars (or application.properties overrides):
 *   GOOGLE_CLOUD_PROJECT  — GCP project that owns the BigQuery dataset
 *   BIGQUERY_DATASET      — dataset name (defaults to "d4m")
 */
@Configuration
public class BigQueryConfig {

    @Bean
    public BigQuery bigQuery(
            @Value("${bigquery.project-id}") String projectId) {
        return BigQueryOptions.newBuilder()
                .setProjectId(projectId)
                .build()
                .getService();
    }

    @Bean
    public String projectId(@Value("${bigquery.project-id}") String projectId) {
        return projectId;
    }

    @Bean
    public String datasetId(@Value("${bigquery.dataset-id}") String datasetId) {
        return datasetId;
    }
}
