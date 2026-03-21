package d4m.gateway;

import java.io.IOException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.SessionAttributes;

import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;

import d4m.bridge.BundleToRCVsConverter;
import d4m.bridge.D4MRequest;
import d4m.bridge.InsertService;
import d4m.bridge.RCVs;

@ComponentScan
@RestController
@SessionAttributes("chunkState")
public class InsertController {

	private static final Logger log = LoggerFactory.getLogger(InsertController.class);

	private final InsertService svc;
	
	private final BundleToRCVsConverter conv;

	@Autowired
	public InsertController(InsertService svc, BundleToRCVsConverter conv) {
		this.svc = svc;
		this.conv = conv;
	}

	@PostMapping(path = "/ins", consumes = MediaType.APPLICATION_JSON_VALUE, produces = "application/json")
	@ResponseBody
	public ResponseEntity<ObjectNode> insResource(@RequestBody D4MRequest qry) {
		RCVs rcvs = null;
		try {
			log.debug("tableName=={}", qry.getTableName());
			
			try {
				rcvs = conv.fromJson(qry.getPayload().toString());
				log.trace("rcvs populated=={}", rcvs.toString().length());
			} catch (IOException e) {
				log.error("", e);
			}
			svc.insertPair(rcvs, qry.getTableName());

			return ResponseEntity.status(HttpStatus.CREATED).build();
		
		} catch (Exception e) {
			log.error("Error processing insert: {}", e.getMessage(), e);
			ObjectNode error = JsonNodeFactory.instance.objectNode();
			error.put("error", "Insert failed");
			error.put("details", e.getMessage());
			return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
		}
	}
}