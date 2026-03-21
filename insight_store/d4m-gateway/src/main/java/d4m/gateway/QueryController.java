package d4m.gateway;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import d4m.bridge.ChunkState;
import d4m.bridge.D4MRequest;
import d4m.bridge.QueryService;
import jakarta.servlet.http.HttpSession;

@RestController
@RequestMapping("/qry")
public class QueryController {

  private final RedisTemplate<String, ChunkStateRedisView> redisTemplate;
  private final QueryService svc;

  
  public QueryController(@Qualifier("chunkStateRedisTemplate") RedisTemplate<String, ChunkStateRedisView> redisTemplate, QueryService svc) {
    this.redisTemplate = redisTemplate;
    this.svc = svc;
  }

  // ---------- DTOs (Redis-facing) ----------
  public static record RangeSpec(
      String startRow, boolean startInclusive,
      String stopRow,  boolean stopInclusive,
      boolean infiniteStart, boolean infiniteStop) {}

  public static record ChunkStateRedisView(
      String tableName,
      String payload,
      String lastSeenRow,
      java.util.List<RangeSpec> ranges) {}

  // ---------- Mappers ----------
  private static RangeSpec toRangeSpec(org.apache.accumulo.core.data.Range r) {
    String sr = r.isInfiniteStartKey() ? null : r.getStartKey().getRow().toString();
    String er = r.isInfiniteStopKey()  ? null : r.getEndKey().getRow().toString();
    return new RangeSpec(sr, r.isStartKeyInclusive(), er, r.isEndKeyInclusive(),
                         r.isInfiniteStartKey(), r.isInfiniteStopKey());
  }

  private static org.apache.accumulo.core.data.Range fromRangeSpec(RangeSpec s) {
    var sk = s.infiniteStart() ? null : new org.apache.accumulo.core.data.Key(s.startRow());
    var ek = s.infiniteStop()  ? null : new org.apache.accumulo.core.data.Key(s.stopRow());
    return new org.apache.accumulo.core.data.Range(sk, s.startInclusive(), ek, s.stopInclusive());
  }

  private static ChunkStateRedisView toView(ChunkState state) {
    var specs = state.getRanges().stream()
        .map(QueryController::toRangeSpec)
        .toList();
    return new ChunkStateRedisView(state.getTableName(), state.getPayload(),
                                   state.getLastSeenRow(), specs);
  }

  private static ChunkState fromView(ChunkStateRedisView view) {
    var ranges = view.ranges().stream()
        .map(QueryController::fromRangeSpec)
        .toList();
    // adapt to your ChunkState constructor/builder
    return new ChunkState(view.tableName(), view.payload(), view.lastSeenRow(), ranges);
  }

  // ---------- Endpoints ----------
  @PostMapping("/init")
  public ResponseEntity<com.fasterxml.jackson.databind.node.ObjectNode>
  init(@RequestBody D4MRequest request, HttpSession session) {

    String sessionId = session.getId();
    ChunkState state = svc.buildChunkState(request);

    // ✅ store the VIEW, not a RangeSpec
    ChunkStateRedisView view = toView(state);
    redisTemplate.opsForValue().set(sessionId, view);

    var ok = com.fasterxml.jackson.databind.node.JsonNodeFactory.instance.objectNode()
        .put("message", "Session initialized");
    return ResponseEntity.ok(ok);
  }

  @GetMapping("/next")
  public ResponseEntity<com.fasterxml.jackson.databind.node.ObjectNode>
  next(HttpSession session) {

    String sessionId = session.getId();
    ChunkStateRedisView view = redisTemplate.opsForValue().get(sessionId);
    if (view == null) {
      var err = com.fasterxml.jackson.databind.node.JsonNodeFactory.instance.objectNode()
          .put("error", "No session initialized");
      return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(err);
    }

    ChunkState state = fromView(view);
    var results = svc.getNextChunk(state);

    // optional: if state advanced, write back
    // redisTemplate.opsForValue().set(sessionId, toView(state));

    return ResponseEntity.ok(results);
  }
}
