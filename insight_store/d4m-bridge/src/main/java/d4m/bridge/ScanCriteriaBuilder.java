package d4m.bridge;

import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import d4m.acc.query.d4MQuery.ListExpr;
import d4m.acc.query.d4MQuery.LiteralExpr;
import d4m.acc.query.d4MQuery.RangeExpr;
import d4m.acc.query.d4MQuery.RegexExpr;
import d4m.acc.query.d4MQuery.RowColWildcard;
import d4m.acc.query.d4MQuery.StartsWithExpr;
import d4m.acc.query.d4MQuery.util.D4MQuerySwitch;

/**
 * Translates a D4M AxisExpr into a BigQuery SQL WHERE predicate.
 * The predicate uses the literal placeholder {axis} for the column name
 * (either "row" or "col") so the caller can substitute at use time.
 *
 * Use {@link #applyTo(d4m.acc.query.d4MQuery.AxisExpr, String)} for a
 * fully resolved predicate, or call doSwitch() and replace {axis} manually.
 */
public class ScanCriteriaBuilder extends D4MQuerySwitch<String> {

    private static final Logger log = LoggerFactory.getLogger(ScanCriteriaBuilder.class);

    /** Returns a SQL WHERE predicate with the given column name substituted for {axis}. */
    public String applyTo(d4m.acc.query.d4MQuery.AxisExpr expr, String column) {
        return doSwitch(expr).replace("{axis}", column);
    }

    @Override
    public String caseLiteralExpr(LiteralExpr expr) {
        String value = expr.getValue();
        log.trace("LiteralExpr.value = {}", value);
        return "{axis} = '" + escape(value) + "'";
    }

    @Override
    public String caseRangeExpr(RangeExpr expr) {
        log.trace("caseRangeExpr=={}..{}", expr.getFrom(), expr.getTo());
        return "{axis} >= '" + escape(expr.getFrom()) + "' AND {axis} <= '" + escape(expr.getTo()) + "'";
    }

    @Override
    public String caseListExpr(ListExpr expr) {
        log.trace("caseListExpr=={}", expr.getValues());
        String inList = expr.getValues().stream()
                .map(v -> "'" + escape(v) + "'")
                .collect(Collectors.joining(", "));
        return "{axis} IN (" + inList + ")";
    }

    @Override
    public String caseRowColWildcard(RowColWildcard expr) {
        log.trace("caseRowColWildcard — full scan");
        return "TRUE";
    }

    @Override
    public String caseStartsWithExpr(StartsWithExpr expr) {
        String prefix = expr.getPrefix();
        String end = nextLexicographicString(prefix);
        log.trace("caseStartsWithExpr prefix={} end={}", prefix, end);
        return "{axis} >= '" + escape(prefix) + "' AND {axis} < '" + escape(end) + "'";
    }

    @Override
    public String caseRegexExpr(RegexExpr expr) {
        String pattern = expr.getPattern();
        log.trace("RegexExpr.pattern = {}", pattern);
        return "REGEXP_CONTAINS({axis}, '" + escape(pattern) + "')";
    }

    private static String escape(String s) {
        return s == null ? "" : s.replace("\\", "\\\\").replace("'", "\\'");
    }

    public static String nextLexicographicString(String prefix) {
        if (prefix == null || prefix.isEmpty()) return prefix;
        char[] chars = prefix.toCharArray();
        for (int i = chars.length - 1; i >= 0; i--) {
            if (chars[i] != Character.MAX_VALUE) {
                chars[i]++;
                return new String(chars, 0, i + 1);
            }
        }
        return prefix;
    }
}
