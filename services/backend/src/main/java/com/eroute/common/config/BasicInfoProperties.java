package com.eroute.common.config;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
@ConfigurationProperties("eroute.basic-info")
public record BasicInfoProperties(Duration refreshInterval,boolean schedulerEnabled){
 public BasicInfoProperties {if(refreshInterval==null)refreshInterval=Duration.ofDays(7);if(refreshInterval.compareTo(Duration.ofDays(1))<0)throw new IllegalArgumentException("Basic refresh must be at least one day");}
}
