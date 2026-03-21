package d4m.gateway;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.StringRedisSerializer;

@Configuration
public class RedisConfig {

  @Bean
  public RedisTemplate<String, QueryController.ChunkStateRedisView> chunkStateRedisTemplate(
      LettuceConnectionFactory connectionFactory
  ) {
    var tpl = new RedisTemplate<String, QueryController.ChunkStateRedisView>();
    tpl.setConnectionFactory(connectionFactory);

    var keySer   = new StringRedisSerializer();
    var valueSer =
        new org.springframework.data.redis.serializer.Jackson2JsonRedisSerializer<>(
            QueryController.ChunkStateRedisView.class);

    tpl.setKeySerializer(keySer);
    tpl.setHashKeySerializer(keySer);
    tpl.setValueSerializer(valueSer);
    tpl.setHashValueSerializer(valueSer);
    tpl.afterPropertiesSet();
    return tpl;
  }
}
