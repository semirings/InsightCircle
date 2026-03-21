package d4m.gateway;

import java.util.SortedSet;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import d4m.bridge.AdminService;

@RestController
@RequestMapping("/admin")
public class AdminController {

	private static final Logger log = LoggerFactory.getLogger(AdminController.class);

    private final AdminService svc;

    @Autowired
    public AdminController(AdminService svc) {
        this.svc = svc;
    }

    @GetMapping("/list-tables")
    public ResponseEntity<SortedSet<String>> listTables() {
        log.trace("/list-tables==>");
        return ResponseEntity.ok(svc.listTables());
    }

    @GetMapping("/current-user")
    public ResponseEntity<String> currentUser() {
        log.trace("/current-user==>");
        return ResponseEntity.ok(svc.currentUser());
    }

    @PostMapping("/create-table")
    public ResponseEntity<?> createTable(@RequestParam String tableName) {
        log.debug("/create-table==>");
        svc.createTable(tableName);
        return ResponseEntity.ok().build();
    }

	@PostMapping(path = "/create-pair", produces = "application/json")
	@ResponseBody
	public ResponseEntity<String> createTablePair(@RequestBody String tableName) {
        log.debug("/create-pair==>");
		svc.createTablePair(tableName);
		return ResponseEntity.accepted().body(tableName);
	}

	@PostMapping(path = "/rename", produces = "application/json")
	@ResponseBody
	public ResponseEntity<String> rename(@RequestBody RenameRequest req) {
        log.debug("/rename==>");
		svc.rename(req.oldName, req.newName);
		return ResponseEntity.accepted().body(req.newName);
	}
    // @DeleteMapping("/delete-table")
    // public ResponseEntity<?> deleteTable(@RequestParam String tableName) {
    //     acc.deleteTable(tableName);
    //     return ResponseEntity.ok().build();
    // }

    @GetMapping("/is-online")
    public ResponseEntity<Boolean> isOnline(@RequestParam String tableName) {
        log.trace("/is-online==>");
        return ResponseEntity.ok(svc.isOnline(tableName));
    }

    @GetMapping("/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.ok("Ok");
    }

	@GetMapping("/")
	public String hello() {
		return "Ave Mundus!!";
	}
}
