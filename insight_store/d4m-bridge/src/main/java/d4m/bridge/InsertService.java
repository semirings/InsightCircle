package d4m.bridge;

import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

import org.apache.accumulo.core.client.AccumuloClient;
import org.apache.accumulo.core.client.BatchWriter;
import org.apache.accumulo.core.client.MutationsRejectedException;
import org.apache.accumulo.core.client.TableNotFoundException;
import org.apache.accumulo.core.data.Mutation;
import org.apache.accumulo.core.data.Value;
import org.apache.hadoop.io.Text;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class InsertService extends BaseService {

	private static final Logger log = LoggerFactory.getLogger(InsertService.class);
    
	InsertService(AccumuloClient client) {
        super(client);
	}

 // 	public void insert(RCVs rcvs, String tableName) {

// 		if (!client.tableOperations().exists(tableName)) {
// 			createTable(tableName);
// 		}
// 		try {
// 			AccumuloInsert accIns = new AccumuloInsert(client.properties().getProperty("instance.name"), client.properties().getProperty("instance.zookeepers"), tableName, client.properties().getProperty("auth.principal"), client.properties().getProperty("auth.token"));
// //			accIns.doProcessing(rcvs.getRows(), rcvs.getCols(), rcvs.getVals(),rcvs.getFamily(), "PUBLIC");
// 		} catch (Exception e) {
// 			log.error("", e);
// 		}
// 	}

	public void insertPair(RCVs rcvs, String tableName) {

		log.trace("insertPair=={}", tableName);

		try {
			// if (!client.tableOperations().exists(tableName)) {
			// 	createTablePair(tableName);
			// }
			
			insertIntoTable(rcvs.getRows(), rcvs.getCols(), rcvs.getVals(), tableName, rcvs.getFamily());
			insertIntoTable(rcvs.getCols(), rcvs.getRows(), rcvs.getVals(), tableName + PAIR_DECOR, rcvs.getFamily());
			
        	bumpDegrees(rcvs.getRows(), rcvs.getCols(), tableName + DEGREE_DECOR);
		} catch (Exception e) {
			log.error("Failed to insert into table pair", e);
		}
	}

	private void insertIntoTable(String[] rows, String[] cols, String[] vals, String table, String family)
			throws TableNotFoundException, MutationsRejectedException {

		log.trace("insertIntoTable=={}", table);
				
		try (BatchWriter writer = client.createBatchWriter(table)) {
			for (int i = 0; i < rows.length; i++) {
				Mutation mutation = new Mutation(rows[i]);
				mutation.put(new Text(family), new Text(cols[i]), new Value(vals[i].getBytes(StandardCharsets.UTF_8)));
				writer.addMutation(mutation);
			}
		}
	}

	private void bumpDegrees(String[] rows, String[] cols, String degreeTable) throws Exception {
		// Aggregate per vertex so we write a single mutation per vertex
		Map<String, Integer> delta = new HashMap<>(rows.length * 2);
		for (int i = 0; i < rows.length; i++) {
			delta.merge(rows[i], 1, Integer::sum);
			delta.merge(cols[i], 1, Integer::sum);
		}

		try (BatchWriter bw = client.createBatchWriter(degreeTable)) {
			for (Map.Entry<String, Integer> e : delta.entrySet()) {
				Mutation mutation = new Mutation(e.getKey());
				// STRING SummingCombiner → write integer as string
				String inc = Integer.toString(e.getValue());
				mutation.put(new Text("deg"), new Text("count"), new Value(inc.getBytes(StandardCharsets.UTF_8)));
				bw.addMutation(mutation);
			}
		}
	}
}	
