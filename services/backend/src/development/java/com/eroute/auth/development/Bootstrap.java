package com.eroute.auth.development;

import com.eroute.auth.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.time.*;
import java.util.*;
import org.springframework.core.env.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.TransactionTemplate;
import org.flywaydb.core.Flyway;

/** Explicit non-web command only. No Spring application, scheduler, PASS, SMS or NMC. */
public final class Bootstrap {
 public static void main(String[] args)throws Exception{
  String environment=System.getenv("EROUTE_AUTH_ENVIRONMENT");if(!Set.of("local","test").contains(environment==null?"":environment))throw new IllegalStateException("BOOTSTRAP_LOCAL_TEST_ONLY");
  var ds=new DriverManagerDataSource(System.getenv("DB_URL"),System.getenv("DB_USERNAME"),System.getenv("DB_PASSWORD"));var db=new JdbcTemplate(ds);
  if(Arrays.asList(args).contains("--initialize-local-database")){
   String name=db.queryForObject("SELECT current_database()",String.class);if(!name.endsWith("_local")&&!name.endsWith("_test"))throw new IllegalStateException("EXPLICIT_DEVELOPMENT_DATABASE_REQUIRED");
   Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();
   db.update("INSERT INTO auth_environment VALUES(true,?) ON CONFLICT DO NOTHING",environment);
  }
  if(!db.queryForList("SELECT environment FROM auth_environment",String.class).equals(List.of(environment)))throw new IllegalStateException("BOOTSTRAP_ENVIRONMENT_MISMATCH");
  var env=new StandardEnvironment();env.getPropertySources().addFirst(new MapPropertySource("bootstrap",Map.of("eroute.auth.environment",environment,"eroute.auth.provider","development","eroute.auth.allow-development",true,"eroute.auth.key-file",System.getenv("EROUTE_AUTH_KEY_FILE"))));var settings=new AuthSettings(env);var tm=new DataSourceTransactionManager(ds);var box=new SecretBox(settings,db,tm);var tx=new TransactionTemplate(tm);
  db.execute("CREATE TABLE IF NOT EXISTS dev_identity_fixture (phone text PRIMARY KEY,subject text NOT NULL,credential_hash text NOT NULL,birth_date date NOT NULL)");
  box.validateRegistry();
  Path output=Path.of(System.getenv("EROUTE_DEV_CREDENTIALS_FILE"));boolean rotate=Arrays.asList(args).contains("--rotate-credentials");
  if(Files.exists(output)&&!rotate){
   var saved=new ObjectMapper().readTree(Files.readString(output));
   if(!environment.equals(saved.path("environment").asText())||saved.path("accounts").size()!=3)throw new IllegalStateException("CREDENTIAL_FILE_DATABASE_MISMATCH");
   Set<String> aliases=new HashSet<>();
   for(var fixture:saved.path("accounts")){
    String alias=fixture.path("alias").asText(),phone=fixture.path("phone").asText();
    if(!Set.of("operator","member-a","member-b").contains(alias)||!aliases.add(alias)||!phone.equals("dev:"+alias)||!"DEVELOPMENT".equals(fixture.path("source").asText())||db.queryForObject("SELECT count(*) FROM dev_identity_fixture WHERE phone=? AND credential_hash=?",Long.class,phone,SecretBox.sha256(fixture.path("credential").asText()))!=1)throw new IllegalStateException("CREDENTIAL_FILE_DATABASE_MISMATCH");
   }
   System.out.println("Development accounts already provisioned; credential file retained.");return;
  }
  var fixtures=new ArrayList<Map<String,String>>();
  tx.executeWithoutResult(s->{
   for(String alias:List.of("operator","member-a","member-b")){
    String phone="dev:"+alias;var existing=db.queryForList("SELECT subject FROM dev_identity_fixture WHERE phone=?",String.class,phone);
    if(!existing.isEmpty()&&!rotate)throw new IllegalStateException("CREDENTIAL_FILE_MISSING_USE_EXPLICIT_ROTATION");
    String subject=existing.isEmpty()?UUID.randomUUID().toString():existing.getFirst(),credential=box.token();Instant now=Instant.now();
    db.update("INSERT INTO dev_identity_fixture VALUES(?,?,?,?) ON CONFLICT(phone) DO UPDATE SET credential_hash=excluded.credential_hash",phone,subject,SecretBox.sha256(credential),java.sql.Date.valueOf("2000-01-01"));
    String scope="development:"+environment;String digest=box.mac("identity",scope+"|"+subject);
    if(existing.isEmpty()){
     UUID user=UUID.randomUUID();db.update("INSERT INTO app_user(id,environment,source,role,phone_cipher,created_at) VALUES(?,?,?,?,?,?)",user,environment,"DEVELOPMENT",alias.equals("operator")?"OPERATOR":"MEMBER",box.encrypt("account","phone:"+user,phone),AuthData.ts(now));
     db.update("INSERT INTO verified_identity VALUES(?,?,?,?,?)",user,scope,box.active("identity"),digest,AuthData.ts(now));
     db.update("INSERT INTO health_consent(user_id,updated_at) VALUES(?,?)",user,AuthData.ts(now));
     db.update("INSERT INTO consent_record VALUES(?,?,?,?,?,?,?)",UUID.randomUUID(),user,"SIGNUP",AuthService.TERMS,"GRANTED","DEVELOPMENT_BOOTSTRAP",AuthData.ts(now));
    }else{for(String old:box.macs("identity",scope+"|"+subject))db.update("UPDATE auth_session SET revoked_at=? WHERE user_id IN(SELECT user_id FROM verified_identity WHERE digest=?)",AuthData.ts(now),old);}
    fixtures.add(Map.of("alias",alias,"phone",phone,"credential",credential,"source","DEVELOPMENT"));
   }
  });
  Files.createDirectories(output.toAbsolutePath().getParent());Path temporary=Files.createTempFile(output.getParent(),"credentials-",".tmp",PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
  Files.writeString(temporary,new ObjectMapper().writerWithDefaultPrettyPrinter().writeValueAsString(Map.of("environment",environment,"accounts",fixtures)));Files.move(temporary,output,StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);System.out.println("Development credentials written to private local file. No session issued.");
 }
}
