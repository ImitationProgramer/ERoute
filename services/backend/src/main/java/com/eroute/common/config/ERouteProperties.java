package com.eroute.common.config;
import java.time.Duration;
import java.net.URI;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;
@ConfigurationProperties("eroute")
public record ERouteProperties(List<Integer> radiusSteps, Duration realtimeTtl, Duration masterTtl,
 Duration refreshDeadline, URI nmcBaseUrl, String nmcKey, String keyEncoding, String keyAlias, int callBudget,
 int dailyLimit, int maxConcurrency, int requestsPerSecond, Duration requestTimeout,
 int maxResponseBytes, int rawRetentionDays) {
 public ERouteProperties {
  if(!List.of("decoded","encoded").contains(keyEncoding)) throw new IllegalArgumentException("Invalid key encoding");
  if(keyEncoding.equals("encoded")) nmcKey=java.net.URLDecoder.decode(nmcKey,java.nio.charset.StandardCharsets.UTF_8);
  if(radiusSteps==null || radiusSteps.isEmpty() || radiusSteps.stream().anyMatch(n->n<=0 || n>200000)) throw new IllegalArgumentException("Invalid radius steps");
  if(!radiusSteps.equals(radiusSteps.stream().distinct().sorted().toList())) throw new IllegalArgumentException("Radius steps must be ascending and unique");
  radiusSteps=List.copyOf(radiusSteps);
  if(callBudget<=0 || callBudget>dailyLimit || maxConcurrency<1 || requestsPerSecond<1) throw new IllegalArgumentException("Invalid NMC budget");
  if(realtimeTtl.isNegative() || realtimeTtl.isZero() || requestTimeout.isNegative() || requestTimeout.isZero()) throw new IllegalArgumentException("Invalid TTL");
 }
 @Override public String toString() { return "ERouteProperties[secrets redacted]"; }
}
