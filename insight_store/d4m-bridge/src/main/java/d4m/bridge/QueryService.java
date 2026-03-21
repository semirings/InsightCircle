package d4m.bridge;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import org.eclipse.emf.common.util.TreeIterator;
import org.eclipse.emf.common.util.URI;
import org.eclipse.emf.ecore.EObject;
import org.eclipse.emf.ecore.resource.Resource;
import org.eclipse.xtext.nodemodel.INode;
import org.eclipse.xtext.parser.IParseResult;
import org.eclipse.xtext.resource.IResourceServiceProvider;
import org.eclipse.xtext.resource.XtextResource;
import org.eclipse.xtext.resource.XtextResourceSet;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.google.cloud.bigquery.BigQuery;
import com.google.cloud.bigquery.FieldValueList;
import com.google.cloud.bigquery.QueryJobConfiguration;
import com.google.cloud.bigquery.TableResult;
import com.google.inject.Injector;

import d4m.acc.query.D4MQueryStandaloneSetup;
import d4m.acc.query.d4MQuery.AxisExpr;
import d4m.acc.query.d4MQuery.D4MQuery;
import d4m.acc.query.d4MQuery.ListExpr;
import d4m.acc.query.d4MQuery.LiteralExpr;
import d4m.acc.query.d4MQuery.RangeExpr;
import d4m.acc.query.d4MQuery.RegexExpr;
import d4m.acc.query.d4MQuery.RowColWildcard;
import d4m.acc.query.d4MQuery.StartsWithExpr;

@Service
public class QueryService extends BaseService {

    private static final Logger log = LoggerFactory.getLogger(QueryService.class);

    public static final int DEFAULT_CHUNK_SIZE = 100;

    QueryService(BigQuery bigQuery, String projectId, String datasetId) {
        super(bigQuery, projectId, datasetId);
    }

    // ---------- Public query entry points ----------

    public ObjectNode query(D4MRequest qry) {
        log.trace("query=={}", qry.getPayload().toString());
        D4MQuery model = parseQuery(qry.getPayload().asText());
        log.debug("model=={}", model);
        return executeParsedQuery(model, qry.getTableName());
    }

    public ObjectNode scanTable(AxisExpr query, String tableName) {
        log.trace("scanTable=={}", query.toString());
        String where = new ScanCriteriaBuilder().applyTo(query, "row");
        log.trace("where=={}", where);
        return runQuery(tableName, where, -1, 0);
    }

    public ObjectNode executeParsedQuery(D4MQuery model, String tableName) {
        return new QueryExecutor(tableName, this).doSwitch(model);
    }

    // ---------- Chunked query ----------

    public ChunkState buildChunkState(D4MRequest request) {
        D4MQuery model = parseQuery(request.getPayload().asText());

        AxisExpr rowExpr = model.getQuery().getRow();
        AxisExpr colExpr = model.getQuery().getCol();

        boolean rowIsWildcard = rowExpr instanceof RowColWildcard;

        // T table already transposes, so we always filter on "row"
        AxisExpr filterExpr = rowIsWildcard ? colExpr : rowExpr;
        String whereClause = new ScanCriteriaBuilder().applyTo(filterExpr, "row");

        ChunkState state = new ChunkState();
        state.setTableName(request.getTableName());
        state.setPayload(request.getPayload().asText());
        state.setLastSeenRow(null);
        state.setWhereClause(whereClause);
        state.setCurrentOffset(0);
        state.setPageSize(DEFAULT_CHUNK_SIZE);
        return state;
    }

    public ObjectNode getNextChunk(ChunkState state) {
        int offset = state.getCurrentOffset();
        int pageSize = state.getPageSize();

        ObjectNode result = runQuery(state.getTableName(), state.getWhereClause(), pageSize, offset);

        int returned = result.withArray("rows").size();
        if (returned == 0) {
            result.put("message", "No more chunks available");
        } else {
            state.setCurrentOffset(offset + returned);
        }

        return result;
    }

    // ---------- BigQuery execution ----------

    private ObjectNode runQuery(String tableName, String where, int limit, int offset) {
        String fullTable = String.format("`%s.%s.%s`", projectId, datasetId, tableName);
        StringBuilder sql = new StringBuilder("SELECT row, col, val FROM ")
                .append(fullTable)
                .append(" WHERE ").append(where);
        if (limit > 0) {
            sql.append(" LIMIT ").append(limit).append(" OFFSET ").append(offset);
        }

        log.trace("BQ sql=={}", sql);

        ObjectNode result = JsonNodeFactory.instance.objectNode();
        ArrayNode rows = result.putArray("rows");

        try {
            QueryJobConfiguration cfg = QueryJobConfiguration.newBuilder(sql.toString()).build();
            TableResult tableResult = bigQuery.query(cfg);
            for (FieldValueList row : tableResult.iterateAll()) {
                ObjectNode rowNode = JsonNodeFactory.instance.objectNode();
                rowNode.put("row", row.get("row").getStringValue());
                rowNode.put("col", row.get("col").getStringValue());
                rowNode.put("val", row.get("val").getStringValue());
                rows.add(rowNode);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("BigQuery query interrupted", e);
        } catch (Exception e) {
            throw new RuntimeException("BigQuery query failed", e);
        }

        return result;
    }

    // ---------- D4M query parser (Xtext) ----------

    public D4MQuery parseQuery(String queryString) {
        Injector injector = new D4MQueryStandaloneSetup().createInjectorAndDoEMFRegistration();
        XtextResourceSet resourceSet = injector.getInstance(XtextResourceSet.class);
        resourceSet.addLoadOption(XtextResource.OPTION_RESOLVE_ALL, Boolean.TRUE);

        IResourceServiceProvider provider = injector.getInstance(IResourceServiceProvider.class);
        Resource.Factory factory = provider.get(Resource.Factory.class);
        resourceSet.getResourceFactoryRegistry().getExtensionToFactoryMap().put("d4mq", factory);

        Resource resource = resourceSet.createResource(URI.createURI("dummy:/query.qry"));
        ByteArrayInputStream input = new ByteArrayInputStream(queryString.getBytes(StandardCharsets.UTF_8));

        try {
            resource.load(input, resourceSet.getLoadOptions());
            if (!resource.getErrors().isEmpty()) {
                log.error("=== Parse Errors ===");
                for (Resource.Diagnostic diag : resource.getErrors()) {
                    log.error("Line {}, Col {}: {}", diag.getLine(), diag.getColumn(), diag.getMessage());
                }
                return null;
            }

            EObject model = resource.getContents().get(0);
            log.debug("Parsed model: {}", model.getClass().getSimpleName());

            TreeIterator<EObject> it = model.eAllContents();
            while (it.hasNext()) {
                EObject obj = it.next();
                log.debug("EObject: {} → {}", obj.eClass().getName(), obj.toString());
            }

            if (resource instanceof XtextResource) {
                IParseResult parseResult = ((XtextResource) resource).getParseResult();
                INode rootNode = parseResult.getRootNode();
                log.debug("=== Grammar Trace ===");
                for (INode node : rootNode.getAsTreeIterable()) {
                    String element = node.getGrammarElement() != null
                            ? node.getGrammarElement().toString() : "null";
                    log.debug("Node: {}  [Text: '{}']", element, node.getText().replace("\n", "\\n"));
                }
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to parse query", e);
        }

        EObject eObject = resource.getContents().get(0);
        log.debug("Parsed model type: {}", eObject.getClass().getName());
        TreeIterator<EObject> it = eObject.eAllContents();
        while (it.hasNext()) {
            EObject child = it.next();
            log.debug("Child: {} — {}", child.eClass().getName(), child.toString());
        }
        if (eObject instanceof D4MQuery) {
            return (D4MQuery) eObject;
        }
        throw new RuntimeException("Parsed root is not a D4MQuery");
    }

    // ---------- Axis extraction (used by QueryExecutor) ----------

    public static String extractAxisFromQuery(AxisExpr axis) {
        if (axis == null) return "";
        if (axis instanceof RowColWildcard) return ":";
        if (axis instanceof LiteralExpr)   return ((LiteralExpr) axis).getValue();
        if (axis instanceof RangeExpr r)   return String.format("[%s..%s]", r.getFrom(), r.getTo());
        if (axis instanceof ListExpr l) {
            List<String> values = new ArrayList<>();
            for (Object v : l.getValues()) values.add(v.toString());
            return "[" + String.join(", ", values) + "]";
        }
        if (axis instanceof StartsWithExpr s) return "StartsWith(" + s.getPrefix() + ")";
        if (axis instanceof RegexExpr r)      return "Regex(" + r.getPattern() + ")";
        throw new UnsupportedOperationException("Unknown AxisExpr subtype: " + axis.getClass().getName());
    }
}
