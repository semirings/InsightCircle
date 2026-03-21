package d4m.bridge;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import org.apache.accumulo.core.data.Range;
import org.apache.hadoop.io.Text;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import d4m.acc.query.d4MQuery.ListExpr;
import d4m.acc.query.d4MQuery.LiteralExpr;
import d4m.acc.query.d4MQuery.RangeExpr;
import d4m.acc.query.d4MQuery.RegexExpr;
import d4m.acc.query.d4MQuery.RowColWildcard;
import d4m.acc.query.d4MQuery.StartsWithExpr;
import d4m.acc.query.d4MQuery.util.D4MQuerySwitch;

public class ScanCriteriaBuilder extends D4MQuerySwitch<List<Range>> { 
    
	private static final Logger log = LoggerFactory.getLogger(ScanCriteriaBuilder.class);

    @Override
    public List<Range> caseLiteralExpr(LiteralExpr expr) {
        String value = expr.getValue();
        log.trace("LiteralExpr.value = {}", value);

        Text key = new Text(value);
        Range range = new Range(key, true, key, true);
        return Collections.singletonList(range);
    }

    @Override
    public List<Range> caseRangeExpr(RangeExpr expr) {
        log.trace("caseRangeExpr=={}..{}", expr.getFrom(), expr.getTo());
        return List.of(new Range(expr.getFrom(), expr.getTo()));
    }

    @Override
    public List<Range> caseListExpr(ListExpr expr) {
        List<Range> ranges = new ArrayList<>();
        for (String val : expr.getValues()) {
            ranges.add(new Range(val));
        }
        log.trace("caseListExpr=={}", expr.getValues());
        return ranges;
    }

    @Override
    public List<Range> caseRowColWildcard(RowColWildcard expr) {
        // Return null or empty list to signify full scan — up to you
        log.trace("caseRowColWildcard=={}", expr.toString());
        return Collections.emptyList(); // interpreted as a wildcard/full-scan by caller
    }

    // Add StartsWithExpr or RegexExpr if needed — for now you can throw if unsupported
    @Override
    public List<Range> caseStartsWithExpr(StartsWithExpr expr) {
        List<Range> ranges = new ArrayList<>();
        String prefix = expr.getPrefix();
        String end = nextLexicographicString(prefix); // e.g., Pat → Pau
        Range range = new Range(prefix, true, end, false);
        ranges.add(range);
        return ranges;
    }

    @Override
    public List<Range> caseRegexExpr(RegexExpr expr) {
        String pattern = expr.getPattern();
        log.trace("RegexExpr.pattern = {}", pattern);

        // For regex, use full scan range
        Range range = new Range(); // entire table

        return Collections.singletonList(range);    
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
    	return prefix; // fallback (should not happen)
	}
}
