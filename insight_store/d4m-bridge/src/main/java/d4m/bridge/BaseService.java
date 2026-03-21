package d4m.bridge;

import java.nio.file.Paths;
import java.util.Objects;

import org.apache.accumulo.core.client.Accumulo;
import org.apache.accumulo.core.client.AccumuloClient;
import org.apache.accumulo.core.client.security.tokens.PasswordToken;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.apache.hadoop.io.Text;

/**
 * BaseService: Provides authenticated Accumulo client and common constants.
 * Subclasses can use the protected 'client' field for table operations.
 */
public abstract class BaseService {

	private static final Logger log = LoggerFactory.getLogger(BaseService.class);
    // --- Constants accessible to subclasses ---
    protected static final String PAIR_DECOR = "T";
    protected static final String DEGREE_DECOR = "Deg";
    protected static final Text FAMILY = new Text(""); // reserved, may never be used

    // --- Protected client ---
    protected final AccumuloClient client;

    /**
     * Constructor: use prebuilt client (for dependency injection)
     *
     * @param client a fully authenticated AccumuloClient
     */
    protected BaseService(AccumuloClient client) {
		log.info("BaseService==>");
        this.client = Objects.requireNonNull(client, "AccumuloClient must not be null");
		log.debug("auth.principal=={}", client.properties().getProperty("auth.principal"));
    }
}