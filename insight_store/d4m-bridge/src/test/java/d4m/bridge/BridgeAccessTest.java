package d4m.bridge;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class BridgeAccessTest {

    private static final Logger log = LoggerFactory.getLogger(BridgeAccessTest.class);

    @BeforeAll
    static void setUpBeforeClass() {
        log.info("setUpBeforeClass");
    }

    @Test
    void testBundleToRCVs() throws IOException {
        log.info("testBundleToRCVs==>");
        InputStream reader = BundleToRCVsConverterTest.class.getClassLoader()
                .getResourceAsStream("Alicia.json");
        assertNotNull(reader);
        BundleToRCVsConverter sut = new BundleToRCVsConverter();
        String jsonString = new String(reader.readAllBytes(), StandardCharsets.UTF_8);
        reader.close();
        RCVs rcvs = sut.fromJson(jsonString);
        assertNotNull(rcvs);
    }
}
