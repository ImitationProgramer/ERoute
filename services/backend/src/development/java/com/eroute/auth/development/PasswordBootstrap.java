package com.eroute.auth.development;
import com.eroute.auth.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.*;
import java.time.Clock;
import java.util.*;
import org.springframework.core.env.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.beans.factory.support.DefaultListableBeanFactory;

/** Explicit userId mappings, in a private file. No web server or external providers. */
public final class PasswordBootstrap {
 public static void main(String[] args)throws Exception{
  if(args.length!=1)throw new IllegalArgumentException("PRIVATE_MANIFEST_PATH_REQUIRED");
  var manifest=new ObjectMapper().readTree(Files.readString(Path.of(args[0])));
  String environment=System.getenv("EROUTE_AUTH_ENVIRONMENT");
  if(!Set.of("local","test").contains(environment==null?"":environment)||!environment.equals(manifest.path("environment").asText()))throw new IllegalStateException("BOOTSTRAP_LOCAL_TEST_ONLY");
  var ds=new DriverManagerDataSource(System.getenv("DB_URL"),System.getenv("DB_USERNAME"),System.getenv("DB_PASSWORD"));var db=new JdbcTemplate(ds);
  if(!db.queryForList("SELECT environment FROM auth_environment",String.class).equals(List.of(environment)))throw new IllegalStateException("BOOTSTRAP_ENVIRONMENT_MISMATCH");
  var env=new StandardEnvironment();env.getPropertySources().addFirst(new MapPropertySource("bootstrap",Map.of("eroute.auth.environment",environment,"eroute.auth.provider","password","eroute.auth.key-file",System.getenv("EROUTE_AUTH_KEY_FILE"))));
  var settings=new AuthSettings(env);var tm=new DataSourceTransactionManager(ds);var box=new SecretBox(settings,db,tm);box.validateRegistry();
  var auth=new AuthService(db,box,settings,Clock.systemUTC(),tm,new DefaultListableBeanFactory().getBeanProvider(PhoneIdentityVerificationProvider.class));
  var passwords=new PasswordAuthService(db,box,settings,auth,Clock.systemUTC(),tm);
  var ids=new HashSet<String>();for(var account:manifest.path("accounts")){if(!ids.add(account.path("userId").asText()))throw new IllegalStateException("DUPLICATE_BOOTSTRAP_USER_ID");}
  for(var account:manifest.path("accounts"))passwords.provision(UUID.fromString(account.path("userId").asText()),account.path("phone").asText(),account.path("password").asText());
  System.out.println("Explicit development password mappings validated/provisioned; existing credentials and health retained.");
 }
}
