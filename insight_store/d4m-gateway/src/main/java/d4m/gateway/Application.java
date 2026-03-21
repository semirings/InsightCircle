package d4m.gateway;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = {"d4m.gateway", "d4m.bridge"})
public class Application {

	private static final Logger log = LoggerFactory.getLogger(Application.class);

	public static void main(String[] args) {
		log.debug("Start==>");
		SpringApplication.run(Application.class, args);
		log.debug("<==Stop");
	}	
}
