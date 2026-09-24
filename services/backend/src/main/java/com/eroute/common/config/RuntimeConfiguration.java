package com.eroute.common.config;
import java.time.Clock;
import java.util.concurrent.*;
import org.springframework.context.annotation.*;
@Configuration
public class RuntimeConfiguration {
 @Bean Clock clock(){return Clock.systemUTC();}
 @Bean(destroyMethod="close") ExecutorService refreshExecutor(){return Executors.newVirtualThreadPerTaskExecutor();}
}
