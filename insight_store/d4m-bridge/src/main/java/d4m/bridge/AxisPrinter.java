package d4m.bridge;

import d4m.acc.query.d4MQuery.ListExpr;
import d4m.acc.query.d4MQuery.LiteralExpr;
import d4m.acc.query.d4MQuery.RowColWildcard;
import d4m.acc.query.d4MQuery.util.D4MQuerySwitch;

public class AxisPrinter extends D4MQuerySwitch<String> {

    @Override
    public String caseLiteralExpr(LiteralExpr expr) {
        return expr.getValue();
    }

    @Override
    public String caseRowColWildcard(RowColWildcard wildcard) {
        return ":";
    }

    // Optional: handle other AxisExpr types if needed
    @Override
    public String caseListExpr(ListExpr list) {
        return list.getValues().toString();
    }
}
