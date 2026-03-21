package d4m.gateway;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;

import d4m.bridge.ChunkState;
import d4m.bridge.D4MRequest;
import d4m.bridge.QueryService;

@RestController
@RequestMapping("/qry")
public class QueryController {

  private final QueryService svc;

  public QueryController(QueryService svc) {
    this.svc = svc;
  }

  // ---------- Endpoints ----------

  /**
   * Initialise a chunked query. Returns a ChunkState the client must
   * include in every subsequent /next call.
   */
  @PostMapping("/init")
  public ResponseEntity<ChunkState> init(@RequestBody D4MRequest request) {
    ChunkState state = svc.buildChunkState(request);
    return ResponseEntity.ok(state);
  }

  /**
   * Fetch the next page. Client POSTs the ChunkState returned by /init
   * (or the updated state from the previous /next call).
   * Response contains the rows and the updated state for the next call.
   */
  @PostMapping("/next")
  public ResponseEntity<ObjectNode> next(@RequestBody ChunkState state) {
    ObjectNode results = svc.getNextChunk(state);
    results.putPOJO("state", state);
    return ResponseEntity.ok(results);
  }
}
