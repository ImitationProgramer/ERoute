package com.eroute;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;
import com.eroute.common.config.ERouteProperties;
@SpringBootApplication
@EnableScheduling
@EnableConfigurationProperties({ERouteProperties.class,com.eroute.common.config.BasicInfoProperties.class})
public class ERouteApplication {
 public static void main(String[] args) {
  boolean job=java.util.Arrays.stream(args).anyMatch(a->a.startsWith("--discover-basic")||a.startsWith("--resume-basic-discovery")||a.startsWith("--sync-basic")||a.startsWith("--resume-basic=")||a.equals("--auth-reencrypt")||a.equals("--auth-retain"));
  var app=new SpringApplication(ERouteApplication.class);
  if(job){app.setWebApplicationType(org.springframework.boot.WebApplicationType.NONE);app.setDefaultProperties(java.util.Map.of("eroute.jobs-enabled","false"));}
  var context=app.run(args);
  if(job) context.close();
 }
}
