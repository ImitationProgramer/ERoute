package com.eroute.auth;

import java.time.Duration;
import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

@Component
public class AuthSettings {
 public final String environment, provider, keyFile;
 public final boolean enabled;
 public final Duration access, memberIdle, memberAbsolute, operatorIdle, operatorAbsolute;
 public AuthSettings(Environment env) {
  environment=env.getProperty("eroute.auth.environment","disabled");
  provider=env.getProperty("eroute.auth.provider","disabled");
  keyFile=env.getProperty("eroute.auth.key-file","");
  enabled=!provider.equals("disabled");
  if(!Set.of("disabled","local","test","production").contains(environment) || !Set.of("disabled","development","password","pass").contains(provider)) throw new IllegalStateException("INVALID_AUTH_CONFIGURATION");
  if(provider.equals("development") && (!Set.of("local","test").contains(environment) || !env.getProperty("eroute.auth.allow-development",Boolean.class,false))) throw new IllegalStateException("DEVELOPMENT_AUTH_FORBIDDEN");
  if(environment.equals("production") && env.getProperty("eroute.auth.allow-development",Boolean.class,false)) throw new IllegalStateException("PRODUCTION_AUTH_CONFLICT");
  if(provider.equals("password")&&!Set.of("local","test","production").contains(environment))throw new IllegalStateException("PASSWORD_ENVIRONMENT_REQUIRED");
  if(provider.equals("pass")) throw new IllegalStateException("PASS_ADAPTER_NOT_APPROVED");
  if(enabled && keyFile.isBlank()) throw new IllegalStateException("AUTH_KEYS_REQUIRED");
  access=duration(env,"access-ttl","PT5M"); memberIdle=duration(env,"member-idle","P7D"); memberAbsolute=duration(env,"member-absolute","P30D");
  operatorIdle=duration(env,"operator-idle","PT15M"); operatorAbsolute=duration(env,"operator-absolute","PT8H");
 }
 private Duration duration(Environment env,String key,String fallback){var d=Duration.parse(env.getProperty("eroute.auth."+key,fallback));if(d.isNegative()||d.isZero())throw new IllegalStateException("INVALID_AUTH_DURATION");return d;}
 public Duration idle(String role){return role.equals("OPERATOR")?operatorIdle:memberIdle;}
 public Duration absolute(String role){return role.equals("OPERATOR")?operatorAbsolute:memberAbsolute;}
 @Override public String toString(){return "AuthSettings[redacted]";}
}
