package d4m.bridge;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import org.apache.accumulo.core.client.admin.TableOperations;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class AccumuloAccessTest {

	private static final Logger log = LoggerFactory.getLogger(AccumuloAccessTest.class);

	@BeforeAll
	static void setUpBeforeClass() throws Exception {
		log.info("setUpBeforeClass");
	}

	@Test
	void testPost() {
		log.info("testLoad==>");
        final String tableName = "rcvs";
		InputStream reader = BundleToRCVsConverterTest.class.getClassLoader().getResourceAsStream("Alicia.json");
		assertNotNull(reader);
		BundleToRCVsConverter sut = new BundleToRCVsConverter();
        BaseService acc = new BaseService();
		try {
			String jsonString = new String(reader.readAllBytes(), StandardCharsets.UTF_8);
			reader.close();
			RCVs rcvs;
			rcvs = sut.fromJson(jsonString);
			assertNotNull(rcvs);
            acc.createTablePair(tableName);
		} catch (IOException e) {
			log.error("", e);
		}
    }

    @Test
    void v() {
        final String tableName = "rcvs";
        BaseService acc = new BaseService();
        acc.createTablePair(tableName);
        TableOperations ops = acc.client.tableOperations();
        assertTrue(ops.exists(tableName));
        acc.dropTablePair(tableName);
        assertFalse(ops.exists(tableName));
   }
}