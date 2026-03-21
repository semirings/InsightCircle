package d4m.bridge;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class BundleToRCVsConverterTest {

	private static final Logger log = LoggerFactory.getLogger(BundleToRCVsConverterTest.class);

	@BeforeAll
	static void setUpBeforeClass() throws Exception {
		log.info("setUpBeforeClass");
	}

	@Test
	void testPost() {
		log.info("testLoad==>");
		InputStream reader = BundleToRCVsConverterTest.class.getClassLoader().getResourceAsStream("Alicia.json");
		assertNotNull(reader);
		BundleToRCVsConverter sut = new BundleToRCVsConverter();
		try {
			String jsonString = new String(reader.readAllBytes(), StandardCharsets.UTF_8);
			reader.close();
			RCVs rcvs;
			rcvs = sut.fromJson(jsonString);
			assertNotNull(rcvs);
			log.info("Rows=={}", rcvs.getRows());
			log.info("Cols=={}", rcvs.getCols());
			log.info("Vals=={}", rcvs.getVals());
		} catch (IOException e) {
			log.error("", e);
		}
    }
}