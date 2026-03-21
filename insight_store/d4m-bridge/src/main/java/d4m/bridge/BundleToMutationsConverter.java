package d4m.bridge;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.accumulo.core.data.Mutation;

import java.io.File;
import java.io.IOException;
import java.util.*;

public class BundleToMutationsConverter {

    public List<Mutation> fromJson(File jsonFile) throws IOException {
        ObjectMapper mapper = new ObjectMapper();
        JsonNode root = mapper.readTree(jsonFile);

        Map<String, Mutation> mutationMap = new LinkedHashMap<>();

        if (root.has("resourceType") && "Bundle".equals(root.get("resourceType").asText())) {
            JsonNode entries = root.get("entry");
            if (entries != null && entries.isArray()) {
                for (JsonNode entry : entries) {
                    JsonNode resource = entry.get("resource");
                    if (resource != null) {
                        String resourceType = resource.get("resourceType").asText();
                        String id = resource.get("id").asText();
                        String rowKey = id;
                        flatten("", resource, rowKey, resourceType, mutationMap);
                    }
                }
            }
        } else {
            String resourceType = root.get("resourceType").asText();
            String id = root.get("id").asText();
            String rowKey = id;
            flatten("", root, rowKey, resourceType, mutationMap);
        }

        return new ArrayList<>(mutationMap.values());
    }

    private void flatten(String path, JsonNode node, String rowKey, String resourceType,
                         Map<String, Mutation> mutationMap) {
        if (node.isObject()) {
            Iterator<Map.Entry<String, JsonNode>> fields = node.fields();
            while (fields.hasNext()) {
                Map.Entry<String, JsonNode> field = fields.next();
                String newPath = path.isEmpty() ? field.getKey() : path + "." + field.getKey();
                flatten(newPath, field.getValue(), rowKey, resourceType, mutationMap);
            }
        } else if (node.isArray()) {
            int index = 0;
            for (JsonNode item : node) {
                String newPath = path + "[" + index + "]";
                flatten(newPath, item, rowKey, resourceType, mutationMap);
                index++;
            }
        } else if (node.isValueNode()) {
            String colQualifier = resourceType + "." + path;
            Mutation mut = mutationMap.computeIfAbsent(rowKey, Mutation::new);
            mut.put("fhir", colQualifier, node.asText());
        }
    }
} 
