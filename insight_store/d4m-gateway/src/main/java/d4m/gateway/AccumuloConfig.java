package d4m.gateway;

import org.apache.accumulo.core.client.Accumulo;
import org.apache.accumulo.core.client.AccumuloClient;
import org.apache.accumulo.core.client.security.tokens.PasswordToken;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;

import java.io.InputStream;
import java.util.Properties;

/**
 * Spring configuration for AccumuloClient.
 * 
 * - Uses accumulo-client.properties for connection info (instance + zookeepers)
 * - Injects username and password from environment variables to avoid committing secrets
 */
@Configuration
public class AccumuloConfig {

    @Bean(destroyMethod = "close")
    public AccumuloClient accumuloClient(
            @Value("${accumulo.client.props:classpath:accumulo-client.properties}")
            Resource propsResource
    ) {
        Properties p = new Properties();

        // Load connection properties
        try (InputStream in = propsResource.getInputStream()) {
            p.load(in);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to load Accumulo client properties from " + propsResource, e);
        }

        // Override zookeeper host from env (e.g. ACCUMULO_HOST=hostname:2181)
        String accumuloHost = System.getenv("ACCUMULO_HOST");
        if (accumuloHost != null && !accumuloHost.isBlank()) {
            p.setProperty("instance.zookeepers", accumuloHost);
        }

        // Override tablet server port from env
        String tabletPort = System.getenv("ACCUMULO_TABLET_PORT");
        if (tabletPort != null && !tabletPort.isBlank()) {
            p.setProperty("tserver.port.client", tabletPort);
        }

        // Get username from properties (or default)
        String user = p.getProperty("auth.principal");
        if (user == null || user.isBlank()) {
            throw new IllegalStateException("Accumulo username not set in properties");
        }

        // Get password from environment
        String pass = System.getenv("ACCUMULO_PASSWORD");
        if (pass == null || pass.isBlank()) {
            throw new IllegalStateException("ACCUMULO_PASSWORD environment variable not set");
        }

        // Build client: connection info from properties + credentials from env
        return Accumulo.newClient()
                .from(p)
                .as(user, new PasswordToken(pass))
                .build();
    }
}