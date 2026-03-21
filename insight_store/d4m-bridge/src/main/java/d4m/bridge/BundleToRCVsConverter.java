package d4m.bridge;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Component
public class BundleToRCVsConverter {

	private static final Logger log = LoggerFactory.getLogger(BundleToRCVsConverter.class);

    public RCVs fromJson(String jsonString) throws IOException {

        log.trace("fromJson==>{}", 0);

        ObjectMapper mapper = new ObjectMapper();
        JsonNode root = mapper.readTree(jsonString);

        List<String> rr = new ArrayList<>();
        List<String> cc = new ArrayList<>();
        List<String> vv = new ArrayList<>();

        if (root.has("resourceType") && "Bundle".equals(root.get("resourceType").asText())) {

        log.trace("fromJson==>{}", 1);

            JsonNode entries = root.get("entry");
            if (entries != null && entries.isArray()) {
                for (JsonNode entry : entries) {
                    JsonNode resource = entry.get("resource");
                    if (resource != null) {
                        String resourceType = resource.get("resourceType").asText();
                        String id = resource.get("id").asText();
                        String rowKey = id;
                        flatten("", resource, rowKey, resourceType, rr, cc, vv);
                    }
                }
            }
        } else {
            String resourceType = root.get("resourceType").asText();
            String id = root.get("id").asText();
            String rowKey = id;
            flatten("", root, rowKey, resourceType, rr, cc, vv);
        }

        log.trace("fromJson==>{}", 2);

        return new RCVs(rr.toArray(new String[0]), cc.toArray(new String[0]), vv.toArray(new String[0]), "FHIR");
    }

    private void flatten(String path, JsonNode node, String rowKey, String resourceType,
                         List<String> rr, List<String> cc, List<String> vv) {
        if (node.isObject()) {
            Iterator<Map.Entry<String, JsonNode>> fields = node.fields();
            while (fields.hasNext()) {
                Map.Entry<String, JsonNode> field = fields.next();
                String newPath = path.isEmpty() ? field.getKey() : path + "." + field.getKey();
                flatten(newPath, field.getValue(), rowKey, resourceType, rr, cc, vv);
            }
        } else if (node.isArray()) {
            int index = 0;
            for (JsonNode item : node) {
                String newPath = path + "[" + index + "]";
                flatten(newPath, item, rowKey, resourceType, rr, cc, vv);
                index++;
            }
        } else if (node.isValueNode()) {
            rr.add(rowKey);
            cc.add(resourceType + "." + path);
            vv.add(node.asText());
        }
    }
}
