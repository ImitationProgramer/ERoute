package com.eroute.auth;

import static com.eroute.auth.AuthData.*;
import java.time.*;
import java.util.*;
import org.springframework.boot.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class PasswordAuthService implements ApplicationRunner {
 private final JdbcTemplate db;private final SecretBox box;private final AuthSettings settings;
 private final AuthService auth;private final Clock clock;private final TransactionTemplate tx;
 public PasswordAuthService(JdbcTemplate db,SecretBox box,AuthSettings settings,AuthService auth,Clock clock,PlatformTransactionManager tm){this.db=db;this.box=box;this.settings=settings;this.auth=auth;this.clock=clock;tx=new TransactionTemplate(tm);}
 private void enabled(){if(!settings.enabled)throw problem("AUTH_UNAVAILABLE",503);}
 // One cross-version lock also serializes startup index migration and explicit bootstrap.
 private void indexLock(){db.queryForObject("SELECT pg_advisory_xact_lock(70420260915)",Object.class);}
 private String phoneValue(String phone){return "password-phone-v1|"+phone;}
 private UUID find(String phone){
  Set<UUID> users=new HashSet<>();
  for(String digest:box.macs("identity",phoneValue(phone)))users.addAll(db.queryForList("SELECT user_id FROM phone_login_identifier WHERE environment=? AND digest=?",UUID.class,settings.environment,digest));
  if(users.size()>1)throw problem("LOGIN_IDENTIFIER_CONFLICT",409);
  return users.stream().findFirst().orElse(null);
 }
 private void index(UUID user,String phone){
  for(String key:box.versions("identity")){
   String digest=box.mac("identity",key,phoneValue(phone));
   db.update("INSERT INTO phone_login_identifier VALUES(?,?,?,?) ON CONFLICT DO NOTHING",settings.environment,key,digest,user);
   if(!user.equals(db.queryForObject("SELECT user_id FROM phone_login_identifier WHERE environment=? AND key_version=? AND digest=?",UUID.class,settings.environment,key,digest)))throw problem("LOGIN_IDENTIFIER_CONFLICT",409);
  }
 }
 @Override public void run(ApplicationArguments args){
  if(!settings.enabled)return;
  tx.executeWithoutResult(s->{indexLock();
   for(var row:db.queryForList("SELECT id,phone_cipher FROM app_user WHERE environment=?",settings.environment)){
    UUID user=uuid(row,"id");String phone=box.decrypt("account","phone:"+user,string(row,"phone_cipher"));
    if(phone.startsWith("dev:"))continue;
    // Reserve existing numbers without granting a credential or merging accounts.
    index(user,PasswordPolicy.phone(phone));
   }
  });
 }
 private void rate(String identifier){
  // Independent of NMC and charged outside the account transaction, including failures.
  var minute=clock.instant().truncatedTo(java.time.temporal.ChronoUnit.MINUTES);
  int count=db.queryForObject("INSERT INTO auth_rate_window VALUES(?,?,1) ON CONFLICT(bucket,window_at) DO UPDATE SET attempts=auth_rate_window.attempts+1 RETURNING attempts",Integer.class,box.mac("session","password-rate:"+identifier),ts(minute));
  if(count>10)throw problem("AUTH_RATE_LIMIT",429);
 }
 public Tokens signup(String rawPhone,String rawPassword,String terms,boolean accepted,boolean age){
  enabled();String phone=PasswordPolicy.phone(rawPhone);rate(phone);String password=PasswordPolicy.normalize(rawPassword);PasswordPolicy.strong(password);
  if(!accepted||!PasswordPolicy.TERMS.equals(terms))throw problem("SIGNUP_CONSENT_REQUIRED",400);
  if(!age)throw problem("AGE_SELF_DECLARATION_REQUIRED",400);
  String hash=PasswordPolicy.hash(password);
  return tx.execute(s->{indexLock();if(find(phone)!=null)throw problem("SIGNUP_UNAVAILABLE",409);
   String source=settings.environment.equals("production")?"PRODUCTION":"DEVELOPMENT";
   UUID user=auth.createMember(phone,source,PasswordPolicy.TERMS);
   auth.consent(user,"AGE_SELF_DECLARATION","age-14-self-v1","DECLARED_14_OR_OLDER",source);
   index(user,phone);credential(user,hash);return auth.issue(user);
  });
 }
 private void credential(UUID user,String hash){db.update("INSERT INTO password_credential VALUES(?,?,?,?,?)",user,hash,PasswordPolicy.VERSION,ts(clock.instant()),ts(clock.instant()));}
 private void validateAccount(UUID user){
  var row=db.queryForMap("SELECT environment,source,status FROM app_user WHERE id=?",user);
  if(!settings.environment.equals(string(row,"environment"))||!"ACTIVE".equals(string(row,"status"))||settings.environment.equals("production")&&!"PRODUCTION".equals(string(row,"source")))throw problem("INVALID_CREDENTIALS",401);
 }
 private void check(UUID user,String normalized){
  var rows=user==null?List.<Map<String,Object>>of():db.queryForList("SELECT password_hash,policy_version FROM password_credential WHERE user_id=?",user);
  String hash=rows.isEmpty()?null:string(rows.getFirst(),"password_hash");
  boolean valid=PasswordPolicy.matches(normalized,hash);
  if(!valid||hash==null)throw problem("INVALID_CREDENTIALS",401);
  if(!PasswordPolicy.VERSION.equals(string(rows.getFirst(),"policy_version")))throw problem("AUTH_UNAVAILABLE",503);
  validateAccount(user);
 }
 public Tokens login(String rawPhone,String rawPassword){
  enabled();String phone=PasswordPolicy.phone(rawPhone);rate(phone);String password=PasswordPolicy.normalize(rawPassword);
  UUID user=find(phone);check(user,password);
  return tx.execute(s->{validateAccount(user);return auth.issue(user);});
 }
 public Map<String,Object> reauth(Principal p,String rawPassword){
  enabled();rate(p.userId().toString());check(p.userId(),PasswordPolicy.normalize(rawPassword));
  return tx.execute(s->{int updated=db.update("UPDATE auth_session SET reauthenticated_at=? WHERE id=? AND user_id=? AND revoked_at IS NULL AND expires_at>? AND last_activity_at>?",ts(clock.instant()),p.sessionId(),p.userId(),ts(clock.instant()),ts(clock.instant().minus(settings.idle(p.role()))));
   if(updated!=1)throw problem("SESSION_EXPIRED",401);return Map.of("reauthenticated",true);
  });
 }
 /** Explicit non-web local/test bootstrap; never derives ownership from a phone. */
 public void provision(UUID user,String rawPhone,String rawPassword){
  if(!Set.of("local","test").contains(settings.environment))throw problem("DEVELOPMENT_AUTH_FORBIDDEN",403);
  String phone=PasswordPolicy.phone(rawPhone),password=PasswordPolicy.normalize(rawPassword);PasswordPolicy.strong(password);
  tx.executeWithoutResult(s->{indexLock();var account=db.queryForMap("SELECT * FROM app_user WHERE id=? FOR UPDATE",user);
   if(!settings.environment.equals(string(account,"environment"))||!"DEVELOPMENT".equals(string(account,"source")))throw problem("DEVELOPMENT_AUTH_FORBIDDEN",403);
   UUID owner=find(phone);if(owner!=null&&!owner.equals(user))throw problem("LOGIN_IDENTIFIER_CONFLICT",409);
   if(db.queryForObject("SELECT count(*) FROM password_credential WHERE user_id=?",Long.class,user)>0){check(user,password);if(!user.equals(owner))throw problem("LOGIN_IDENTIFIER_CONFLICT",409);return;}
   db.update("UPDATE app_user SET phone_cipher=? WHERE id=?",box.encrypt("account","phone:"+user,phone),user);index(user,phone);credential(user,PasswordPolicy.hash(password));
  });
 }
}
