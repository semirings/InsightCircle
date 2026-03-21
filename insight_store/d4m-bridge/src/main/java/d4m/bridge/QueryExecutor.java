package d4m.bridge;

import org.eclipse.emf.ecore.EObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.databind.node.ObjectNode;

import d4m.acc.query.d4MQuery.AxisExpr;
import d4m.acc.query.d4MQuery.D4MQuery;
import d4m.acc.query.d4MQuery.QueryExpr;
import d4m.acc.query.d4MQuery.RowColWildcard;
import d4m.acc.query.d4MQuery.util.D4MQuerySwitch;

public class QueryExecutor extends D4MQuerySwitch<ObjectNode> {

	private static final Logger log = LoggerFactory.getLogger(QueryExecutor.class);

    private final String tableName;
    private QueryService svc;

    public QueryExecutor(String tableName, QueryService svc) {
        this.tableName = tableName;
        this.svc = svc;
    }

    @Override
    public ObjectNode caseD4MQuery(D4MQuery query) {

        log.trace("caseD4MQuery=={}", query.getQuery().toString());
     
        return doSwitch(query.getQuery()); // delegate to QueryExpr
    }

    @Override
    public ObjectNode caseQueryExpr(QueryExpr expr) {

        log.trace("caseQueryExpr=={}", expr.toString());

        AxisExpr rowExpr = expr.getRow();

        log.trace("rowExpr=={}", rowExpr);

        AxisExpr colExpr = expr.getCol();

        log.trace("colExpr=={}", colExpr);

        boolean isRowWildcard = rowExpr instanceof RowColWildcard;

        log.trace("isRowWildcard=={}", isRowWildcard);

        boolean isColWildcard = colExpr instanceof RowColWildcard;

        log.trace("isColWildcard=={}", isColWildcard);

        if (isRowWildcard && isColWildcard) {
            throw new IllegalArgumentException("Both row and col cannot be ':' — ambiguous scan.");
        }

        String table = null;
        if (isRowWildcard) {
            table = tableName + "T";
            return svc.scanTable(colExpr, table);
        } else {
            table = tableName;
            return svc.scanTable(rowExpr, table);
        }
    }

    @Override
    public ObjectNode defaultCase(EObject object) {
        throw new UnsupportedOperationException("Unknown query component: " + object);
    }
}
