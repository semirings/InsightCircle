package d4m.bridge;

import java.util.SortedSet;

import org.apache.accumulo.core.client.AccumuloClient;
import org.apache.accumulo.core.client.AccumuloException;
import org.apache.accumulo.core.client.AccumuloSecurityException;
import org.apache.accumulo.core.client.TableExistsException;
import org.apache.accumulo.core.client.TableNotFoundException;
import org.apache.accumulo.core.client.admin.TableOperations;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class AdminService extends BaseService {

	private static final Logger log = LoggerFactory.getLogger(AdminService.class);
	TableOperations ops;
    
	AdminService(AccumuloClient client) {
        super(client);
		this.ops = client.tableOperations();
	}
    	
    public SortedSet<String> listTables() {
		log.info("listTables==>");
		return ops.list();
	}

	public String currentUser() {
		log.info("user==whoami");
		return client.whoami();
	}

	public String createTable(String tableName) {
		log.debug("tableName=={}", tableName);
		try {
			ops.create(tableName);
		} catch (AccumuloException | AccumuloSecurityException | TableExistsException e) {
			e.printStackTrace();
		}
		return tableName;
	}

	public String createTablePair(String tableName) {
		log.info("tableName=={} {}", 1, tableName);
//		log.debug("auth.principal=={}", client.properties().getProperty("auth.principal"));
		log.debug("ops.create(tableName)==> -1");
		if (!ops.exists(tableName)) {
			try {
				log.debug("ops.create(tableName)==> 0");
				ops.create(tableName);
				log.debug("ops.create(tableName)==> 1");
				ops.create(tableName.concat(PAIR_DECOR));
				ops.create(tableName.concat(DEGREE_DECOR));
			} catch (AccumuloException | AccumuloSecurityException | TableExistsException e) {
				e.printStackTrace();
			}
			log.debug("tableName=={} {}", 2, tableName);
		} else {
			log.debug("Table {} exists", tableName);
		}
		return tableName;
	}

	public boolean isOnline(String tableName) {
		log.info("isOnline=={}", tableName);
		try {
			return ops.exists(tableName) && ops.isOnline(tableName);
		} catch (AccumuloException | TableNotFoundException e) {
			log.error("isOnline=={}", tableName, e);
			return false;
		}
	}

	public String rename(String oldName, String newName) {
		log.info("rename=={} {} == . {}", 1, oldName, newName);
//		log.debug("auth.principal=={}", client.properties().getProperty("auth.principal"));
		log.debug("ops.create(tableName)==> -1");
		if (ops.exists(oldName)) {
			try {
				log.debug("ops.rename==> 0");
				ops.rename(oldName, newName);
			} catch (AccumuloException | AccumuloSecurityException | TableExistsException | TableNotFoundException e) {
				e.printStackTrace();
			}
			log.info("tableName=={} {} ==> {}", 2, oldName, newName);
		} else {
			log.debug("Table {} !exists", oldName);
		}
		return newName;
	}

	public String dropTablePair(String tableName) {
		log.trace("tableName=={} {}", 1, tableName);
		log.trace("auth.principal=={}", client.properties().getProperty("auth.principal"));
		log.trace("auth.token=={}", client.properties().getProperty("auth.token"));
		if (ops.exists(tableName)) {
				try {
					ops.delete(tableName);
					ops.delete(tableName.concat(PAIR_DECOR));
					ops.delete(tableName.concat(DEGREE_DECOR));
				} catch (AccumuloException | AccumuloSecurityException | TableNotFoundException e) {
					log.error("", e);
				}

			log.trace("tableName=={} {}", 2, tableName);
		} else {
			log.info("Table {} does not exist", tableName);
		}
		return tableName;
	}
}
