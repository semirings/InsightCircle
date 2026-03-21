package d4m.bridge;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

import org.eclipse.emf.common.util.TreeIterator;
import org.eclipse.emf.ecore.EObject;
import org.eclipse.emf.ecore.resource.Resource;
import org.eclipse.xtext.nodemodel.INode;
import org.eclipse.xtext.parser.IParseResult;
import org.eclipse.xtext.resource.XtextResource;
import org.eclipse.xtext.resource.XtextResourceSet;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.inject.Injector;

import d4m.acc.query.D4MQueryStandaloneSetup;

public class XtextTraceUtil {

    private static final Logger log = LoggerFactory.getLogger(XtextTraceUtil.class);

    public static void parseAndTrace(String queryString) {
        Injector injector = new D4MQueryStandaloneSetup().createInjectorAndDoEMFRegistration();
        XtextResourceSet resourceSet = injector.getInstance(XtextResourceSet.class);

        Resource resource = resourceSet.createResource(org.eclipse.emf.common.util.URI.createURI("dummy:/query.d4mq"));
        ByteArrayInputStream input = new ByteArrayInputStream(queryString.getBytes(StandardCharsets.UTF_8));

        try {
            resource.load(input, resourceSet.getLoadOptions());

            // Log parse errors if any
            if (!resource.getErrors().isEmpty()) {
                log.error("=== Parse Errors ===");
                for (Resource.Diagnostic diag : resource.getErrors()) {
                    log.error("Line {}, Col {}: {}", diag.getLine(), diag.getColumn(), diag.getMessage());
                }
                return;
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

        } catch (Exception e) {
            log.error("Parsing failed", e);
        }
    }
}
