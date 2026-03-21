package d4m.acc.query.validation

import d4m.acc.query.d4MQuery.D4MQueryPackage
import d4m.acc.query.d4MQuery.ListExpr
import d4m.acc.query.d4MQuery.LiteralExpr
import d4m.acc.query.d4MQuery.QueryExpr
import d4m.acc.query.d4MQuery.RangeExpr
import d4m.acc.query.d4MQuery.RegexExpr
import d4m.acc.query.d4MQuery.RowColWildcard
import d4m.acc.query.d4MQuery.StartsWithExpr
import java.util.regex.Pattern
import java.util.regex.PatternSyntaxException
import org.eclipse.xtext.validation.Check

class D4MQueryValidator extends AbstractD4MQueryValidator {

    @Check
    def void validate(QueryExpr expr) {
    	
        if (expr.row instanceof RowColWildcard && expr.col instanceof RowColWildcard) {
            error(
                "Cannot use wildcard for both row and column — ambiguous scan.",
                D4MQueryPackage.Literals.QUERY_EXPR__ROW
            )
        }
    }
    
    @Check
	def void validate(LiteralExpr expr) {
	    val value = expr.value
	
	    if (value === null || value.trim.empty) {
	        error("Literal value must not be empty",
	              D4MQueryPackage.Literals.LITERAL_EXPR__VALUE)
	        return
	    }
	
	    // Disallow characters that are reserved or confusing
	    if (value.contains(",") || value.contains("[") || value.contains("]")) {
	        warning("Literal contains characters that may conflict with other query constructs: ',', '[', or ']'",
	                D4MQueryPackage.Literals.LITERAL_EXPR__VALUE)
	    }
	
	    // Optional: domain-specific checks
	    if (!value.startsWith("Patient.") && !value.startsWith("Observation.")) {
	        info("Literal does not use a known prefix like 'Patient.' or 'Observation.'",
	             D4MQueryPackage.Literals.LITERAL_EXPR__VALUE)
	    }
	
	    // Optional: Length warning
	    if (value.length > 100) {
	        warning("Literal value is unusually long. This may impact query performance.",
	                D4MQueryPackage.Literals.LITERAL_EXPR__VALUE)
	    }
	}
    
    
    
    @Check
    def void validate(RangeExpr expr) {
    	
        val fromVal = expr.from
        val toVal = expr.to

        // Basic: Make sure neither is null or empty
        if (fromVal === null || fromVal.trim.isEmpty ||
            toVal === null || toVal.trim.isEmpty) {
            error("Range bounds must not be empty", 
                D4MQueryPackage.Literals.RANGE_EXPR__FROM)
        }

        // Optional: Enforce lexicographic order
        if (fromVal > toVal) {
            warning("Range 'from' is greater than 'to'. This may yield no results.",
                D4MQueryPackage.Literals.RANGE_EXPR__FROM)
        }
	}

	@Check
	def void validate(ListExpr expr) {
	
	    if (expr.values.empty) {
	        error("List must contain at least one value", D4MQueryPackage.Literals.LIST_EXPR__VALUES)
	        return
	    }
	
	    val seen = newHashSet
	    val dupes = newHashSet
	
	    if (expr.values.exists[it.nullOrEmpty]) {
	        error("List must not contain empty values", D4MQueryPackage.Literals.LIST_EXPR__VALUES)
	        return
	    }
	
	    // Detect duplicates
	    for (value : expr.values) {
	        if (!seen.add(value)) {
	            dupes.add(value)
	        }
	    }
		
	    if (!dupes.empty) {
	        error("List contains duplicate values: " + dupes.join(", "), D4MQueryPackage.Literals.LIST_EXPR__VALUES)
	    }
	
	    if (expr.values.size > 1000) {
	        warning("Large list may cause performance issues", D4MQueryPackage.Literals.LIST_EXPR__VALUES)
	    }
	}

	
	@Check
	def void validate(StartsWithExpr expr) {
		
	    val prefix = expr.prefix
	
	    if (prefix === null || prefix.trim.empty) {
	        error("StartsWith must contain a non-empty prefix", 
	              D4MQueryPackage.Literals.STARTS_WITH_EXPR__PREFIX)
	    }
	
	    if (prefix.contains("*") || prefix.contains("?")) {
	        warning("Prefix contains wildcard characters which may be unsupported", 
	                D4MQueryPackage.Literals.STARTS_WITH_EXPR__PREFIX)
	    }
	
	    if (!prefix.matches("[a-zA-Z0-9._-]+")) {
	        warning("Prefix contains unusual characters", 
	                D4MQueryPackage.Literals.STARTS_WITH_EXPR__PREFIX)
	    }
	}
	
	
	@Check
	def void validate(RegexExpr expr) {
	    val pattern = expr.pattern
	
	    if (pattern === null || pattern.trim.empty) {
	        error("Regex must not be empty",
	              D4MQueryPackage.Literals.REGEX_EXPR__PATTERN)
	        return
	    }
	
	    try {
	        Pattern.compile(pattern)
	    } catch (PatternSyntaxException e) {
	        error("Invalid regex: " + e.message,
	              D4MQueryPackage.Literals.REGEX_EXPR__PATTERN)
	    }
	
	    if (pattern == ".*") {
	        warning("Regex pattern '.*' matches everything — are you sure?",
	                D4MQueryPackage.Literals.REGEX_EXPR__PATTERN)
	    }
	}
	
}