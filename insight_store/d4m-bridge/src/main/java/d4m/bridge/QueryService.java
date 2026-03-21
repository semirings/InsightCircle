package d4m.bridge;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import org.apache.accumulo.core.client.AccumuloClient;
import org.apache.accumulo.core.client.BatchScanner;
import org.apache.accumulo.core.data.Key;
import org.apache.accumulo.core.data.Range;
import org.apache.accumulo.core.data.Value;
import org.apache.accumulo.core.security.Authorizations;
import org.apache.hadoop.io.Text;
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

    public final static int DEFAULT_CHUNK_SIZE = 100;
    public final static int MAX_EXPECTED_SIZE = 100;
    public final static String ZERO_PAD = "%06d";

	QueryService(AccumuloClient client) {
        super(client);
	}

	public ObjectNode query(D4MRequest qry) {

			log.trace("query=={}", qry.getPayload().toString());

			D4MQuery model = (D4MQuery) parseQuery(qry.getPayload().asText());

			log.debug("model=={}", model);
			
			return executeParsedQuery(model, qry.getTableName());
		}

	public ObjectNode scanTable(AxisExpr query, String tableName) {
		log.trace("scanTable=={}", query.toString());

		List<Range> initialRanges = new ScanCriteriaBuilder().doSwitch(query);
        List<Range> ranges;
        if (initialRanges.size() == 1) {
            String rowOrCol = extractAxisFromQuery(query); // You must define this logic
            ranges = buildRanges(rowOrCol);
        } else {
            ranges = initialRanges;
        }
		// for (Range range : ranges) {
		// 	log.trace("range==Start=={} End=={}", range.getStartKey().toString(), range.getEndKey().toString());
		// }
		log.trace("ranges size=={}", ranges.size());
		ObjectNode result = JsonNodeFactory.instance.objectNode();
		ArrayNode rows = result.putArray("rows");

		try {
			String user = client.whoami();
			Authorizations auths = client.securityOperations().getUserAuthorizations(user);
			BatchScanner scanner = client.createBatchScanner(tableName, auths);
			scanner.setRanges(ranges);
			for (Map.Entry<Key, Value> entry : scanner) {
				ObjectNode row = JsonNodeFactory.instance.objectNode();
				row.put("row", entry.getKey().getRow().toString());
				row.put("col", entry.getKey().getColumnFamily().toString());
				row.put("val", entry.getValue().toString());
				rows.add(row);
			}
			scanner.close();
		} catch (Exception e) {
			throw new RuntimeException("Accumulo scan failed", e);
		}

		return result;
	}

	public D4MQuery parseQuery(String queryString) {
		// Set up Xtext
		Injector injector = new D4MQueryStandaloneSetup().createInjectorAndDoEMFRegistration();
		XtextResourceSet resourceSet = injector.getInstance(XtextResourceSet.class);
		resourceSet.addLoadOption(XtextResource.OPTION_RESOLVE_ALL, Boolean.TRUE);

		IResourceServiceProvider provider = injector.getInstance(IResourceServiceProvider.class);
		Resource.Factory factory = provider.get(Resource.Factory.class);
		resourceSet.getResourceFactoryRegistry().getExtensionToFactoryMap()
			.put("d4mq", factory);

		Resource resource = resourceSet.createResource(URI.createURI("dummy:/query.qry"));
		ByteArrayInputStream input = new ByteArrayInputStream(queryString.getBytes(StandardCharsets.UTF_8));

		try {
			resource.load(input, resourceSet.getLoadOptions());
			            // Log parse errors if any
			if (!resource.getErrors().isEmpty()) {
				log.error("=== Parse Errors ===");
				for (Resource.Diagnostic diag : resource.getErrors()) {
					log.error("Line {}, Col {}: {}", diag.getLine(), diag.getColumn(), diag.getMessage());
				}
				return null;
			}

			// Log root EObject
			EObject model = resource.getContents().get(0);
			log.debug("Parsed model: {}", model.getClass().getSimpleName());

			TreeIterator<EObject> it = model.eAllContents();
			while (it.hasNext()) {
				EObject obj = it.next();
				log.debug("EObject: {} → {}", obj.eClass().getName(), obj.toString());
			}

			// Dump grammar nodes if available
			if (resource instanceof XtextResource) {
				IParseResult parseResult = ((XtextResource) resource).getParseResult();
				INode rootNode = parseResult.getRootNode();
				log.debug("=== Grammar Trace ===");
				for (INode node : rootNode.getAsTreeIterable()) {
					String element = node.getGrammarElement() != null ? node.getGrammarElement().toString() : "null";
					log.debug("Node: {}  [Text: '{}']", element, node.getText().replace("\n", "\\n"));
				}
				}
		} catch (IOException e) {
			throw new RuntimeException("Failed to parse query", e);
		}

		// Get the parsed root object
		EObject eObject = resource.getContents().get(0);
log.debug("Parsed model type: {}", eObject.getClass().getName());
TreeIterator<EObject> it = eObject.eAllContents();
while (it.hasNext()) {
    EObject child = it.next();
    log.debug("Child: {} — {}", child.eClass().getName(), child.toString());
}
		if (eObject instanceof D4MQuery) {
			return (D4MQuery) eObject;
		} else {
			throw new RuntimeException("Parsed root is not a D4MQuery");
		}
	}

	public ObjectNode executeParsedQuery(D4MQuery model, String tableName) {
		return new QueryExecutor(tableName, this).doSwitch(model);
	}

    public static List<Range> buildRanges(String rowOrCol) {
    List<Range> ranges = new ArrayList<>();
    int offset = 0;

        while (true) {
            Text start = new Text(rowOrCol + "|" + String.format(ZERO_PAD, offset));
            Text end = new Text(rowOrCol + "|" + String.format(ZERO_PAD, (offset + DEFAULT_CHUNK_SIZE)));
            ranges.add(new Range(start, end));
            offset += DEFAULT_CHUNK_SIZE;
            if (offset > MAX_EXPECTED_SIZE) break; // Optional safeguard
        }

        return ranges;
    }

		public ChunkState buildChunkState(D4MRequest request) {
			D4MQuery model = (D4MQuery) parseQuery(request.getPayload().asText());

			AxisExpr rowExpr = model.getQuery().getRow();
			AxisExpr colExpr = model.getQuery().getCol();

			String row = QueryService.extractAxisFromQuery(rowExpr);
			String col = QueryService.extractAxisFromQuery(colExpr);

			String rowOrCol = !":".equals(row) ? row : col;
			List<Range> ranges = QueryService.buildRanges(rowOrCol); // ✅ Uses Accumulo class here

			ChunkState state = new ChunkState();
			state.setTableName(request.getTableName());
			state.setPayload(request.getPayload().asText());
			state.setLastSeenRow(null); // Optional
			state.setRanges(ranges);
			state.setCurrentIndex(0);
			return state;
		}

	public ObjectNode getNextChunk(ChunkState state) {
		int index = state.getCurrentIndex();
		List<Range> ranges = state.getRanges();
		String table = state.getTableName();

		if (index >= ranges.size()) {
			ObjectNode done = JsonNodeFactory.instance.objectNode();
			done.put("message", "No more chunks available");
			return done;
		}

		Range currentRange = ranges.get(index);
		ObjectNode result = JsonNodeFactory.instance.objectNode();
		ArrayNode rows = result.putArray("rows");

		try {
			String user = client.whoami();
			Authorizations auths = client.securityOperations().getUserAuthorizations(user);
			BatchScanner scanner = client.createBatchScanner(table, auths);
			scanner.setRanges(Collections.singleton(currentRange));

			for (Map.Entry<Key, Value> entry : scanner) {
				ObjectNode row = JsonNodeFactory.instance.objectNode();
				row.put("row", entry.getKey().getRow().toString());
				row.put("col", entry.getKey().getColumnFamily().toString());
				row.put("val", entry.getValue().toString());
				rows.add(row);
			}

			scanner.close();
		} catch (Exception e) {
			throw new RuntimeException("Accumulo chunk scan failed", e);
		}

		// ✅ Advance the cursor
		state.setCurrentIndex(index + 1);

		return result;
	}

    public static String extractAxisFromQuery(AxisExpr axis) {
        if (axis == null) return "";

        if (axis instanceof RowColWildcard) {
            return ":"; // Wildcard case
        }

        if (axis instanceof LiteralExpr) {
            return ((LiteralExpr) axis).getValue();
        }

        if (axis instanceof RangeExpr) {
            RangeExpr range = (RangeExpr) axis;
            return String.format("[%s..%s]", unquote(range.getFrom()), unquote(range.getTo()));
        }

        if (axis instanceof ListExpr) {
            ListExpr list = (ListExpr) axis;
            List<String> values = new ArrayList<>();
            for (Object v : list.getValues()) {
                values.add(unquote(v.toString()));
            }
            return "[" + String.join(", ", values) + "]";
        }

        if (axis instanceof StartsWithExpr) {
            StartsWithExpr s = (StartsWithExpr) axis;
            return "StartsWith(" + unquote(s.getPrefix()) + ")";
        }

        if (axis instanceof RegexExpr) {
            RegexExpr r = (RegexExpr) axis;
            return "Regex(" + unquote(r.getPattern()) + ")";
        }

        throw new UnsupportedOperationException("Unknown AxisExpr subtype: " + axis.getClass().getName());
    }

    private static String unquote(String s) {
        if (s == null) return "";
        if ((s.startsWith("\"") && s.endsWith("\"")) || (s.startsWith("'") && s.endsWith("'"))) {
            return s.substring(1, s.length() - 1);
        }
        return s;
    }

}
