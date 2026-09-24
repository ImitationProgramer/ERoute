package com.eroute.auth;

import static com.eroute.auth.AuthData.*;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class AuthService {
 public static final String TERMS="signup-v1", HEALTH_TERMS="health-v1";
 private final JdbcTemplate db;private final SecretBox box;private final AuthSettings settings;private final Clock clock;
 private final TransactionTemplate tx;private final ObjectProvider<PhoneIdentityVerificationProvider> providers;
 public AuthService(JdbcTemplate db,SecretBox box,AuthSettings settings,Clock clock,PlatformTransactionManager tm,ObjectProvider<PhoneIdentityVerificationProvider> providers){this.db=db;this.box=box;this.settings=settings;this.clock=clock;this.tx=new TransactionTemplate(tm);this.providers=providers;}
 private void enabled(){if(!settings.enabled)throw problem("AUTH_UNAVAILABLE",503);}
 private PhoneIdentityVerificationProvider provider(){enabled();return providers.stream().filter(p->p.name().equals(settings.provider)).findFirst().orElseThrow(()->problem("AUTH_UNAVAILABLE",503));}
 public Map<String,Object> start(String phone,String challenge,String purpose,Principal principal){
  enabled();if(phone==null||phone.length()>40||challenge==null||!challenge.matches("[A-Za-z0-9_-]{43}")||!Set.of("LOGIN","REAUTH","PHONE_CHANGE").contains(purpose))throw problem("INVALID_AUTH_REQUEST",400);
  if(!purpose.equals("LOGIN")&&principal==null)throw problem("AUTH_REQUIRED",401);
  if(settings.provider.equals("development")&&!phone.matches("dev:[a-zA-Z0-9_-]{1,30}"))throw problem("DEVELOPMENT_PHONE_REQUIRED",400);
  UUID id=UUID.randomUUID();Instant now=clock.instant();String source=settings.provider.equals("development")?"DEVELOPMENT":"PRODUCTION";
  return tx.execute(s->{
   db.update("INSERT INTO verification_transaction(id,environment,source,purpose,requester_hash,phone_cipher,bound_user,bound_session,state,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",id,settings.environment,source,purpose,challenge,box.encrypt("temporary","transaction-phone:"+id,phone),principal==null?null:principal.userId(),principal==null?null:principal.sessionId(),"PENDING",ts(now),ts(now.plusSeconds(300)));
   String ref=provider().start(id,phone);db.update("UPDATE verification_transaction SET provider_ref=? WHERE id=?",ref,id);
   return Map.of("transactionId",id,"state","PENDING","source",source,"expiresAt",now.plusSeconds(300));
  });
 }
 private Map<String,Object> transaction(UUID id,String proof){
  var rows=db.queryForList("SELECT * FROM verification_transaction WHERE id=? FOR UPDATE",id);if(rows.isEmpty())throw problem("VERIFICATION_NOT_FOUND",404);var r=rows.getFirst();
  if(proof==null||proof.length()>128||!java.security.MessageDigest.isEqual(SecretBox.sha256(proof).getBytes(java.nio.charset.StandardCharsets.UTF_8),string(r,"requester_hash").getBytes(java.nio.charset.StandardCharsets.UTF_8))||!settings.environment.equals(string(r,"environment")))throw problem("VERIFICATION_NOT_FOUND",404);
  return r;
 }
 public Map<String,Object> status(UUID id,String proof){enabled();return tx.execute(s->{var r=transaction(id,proof);String state=string(r,"state");if(!state.equals("CONSUMED")&&!instant(r,"expires_at").isAfter(clock.instant()))state="EXPIRED";return Map.of("transactionId",id,"state",state,"source",string(r,"source"),"expiresAt",instant(r,"expires_at"));});}
 public void cancel(UUID id,String proof){tx.executeWithoutResult(s->{var r=transaction(id,proof);if(!string(r,"state").equals("CONSUMED"))db.update("UPDATE verification_transaction SET state='CANCELLED',verified_cipher=NULL WHERE id=?",id);});}
 /** Development evidence enters only through the external-provider adapter. */
 public Map<String,Object> verify(UUID id,String proof,String evidence){
  return tx.execute(s->{var r=transaction(id,proof);requirePending(r);String phone=box.decrypt("temporary","transaction-phone:"+id,string(r,"phone_cipher"));
   Verified v=provider().verifyResult(id,string(r,"provider_ref"),phone,evidence);
   if(!v.transactionId().equals(id)||!v.providerReference().equals(string(r,"provider_ref"))||!v.phone().equals(phone)||!v.source().equals(string(r,"source"))||!v.environment().equals(settings.environment)||v.subject()==null||v.subject().isBlank()||v.scope()==null||v.scope().isBlank())throw problem("VERIFICATION_MISMATCH",400);
   if(v.birthDate()==null)throw problem("AGE_UNVERIFIED",403);
   if(v.birthDate().plusYears(14).isAfter(LocalDate.ofInstant(clock.instant(),ZoneId.of("Asia/Seoul"))))throw problem("AGE_RESTRICTED",403);
   db.update("UPDATE verification_transaction SET state='VERIFIED',verified_cipher=?,verified_at=?,expires_at=? WHERE id=?",box.encrypt("temporary","verification:"+id,box.json(v)),ts(clock.instant()),ts(clock.instant().plusSeconds(300)),id);
   UUID user=findIdentity(v,false);boolean phoneChange=user!=null&&!phone.equals(readPhone(user));
   return Map.of("state","VERIFIED","newMember",user==null,"phoneChangeRequired",phoneChange,"termsVersion",TERMS);
  });
 }
 private void requirePending(Map<String,Object> r){if(!string(r,"state").equals("PENDING")||!instant(r,"expires_at").isAfter(clock.instant()))throw problem("VERIFICATION_EXPIRED_OR_USED",409);}
 public Tokens changePhone(UUID id,String proof,String requestKey,Principal principal){
  return tx.execute(s->{var r=transaction(id,proof);
   if(!"PHONE_CHANGE".equals(string(r,"purpose"))||uuid(r,"bound_user")==null)throw problem("PHONE_CHANGE_TRANSACTION_REQUIRED",400);
   return complete(id,proof,requestKey,null,true,principal);
  });
 }
 public Tokens complete(UUID id,String proof,String requestKey,String termsVersion,boolean confirmPhoneChange,Principal principal){
  requestKey(requestKey);
  return tx.execute(s->{var r=transaction(id,proof);Instant now=clock.instant();
   if(string(r,"state").equals("CONSUMED")){
    if(requestKey.equals(string(r,"completion_key"))&&instant(r,"completion_until")!=null&&instant(r,"completion_until").isAfter(now))return box.parse(box.decrypt("temporary","completion:"+id,string(r,"completion_cipher")),Tokens.class);
    throw problem("VERIFICATION_ALREADY_USED",409);
   }
   if(!string(r,"state").equals("VERIFIED")||!instant(r,"expires_at").isAfter(now))throw problem("VERIFICATION_EXPIRED_OR_USED",409);
   Verified v=box.parse(box.decrypt("temporary","verification:"+id,string(r,"verified_cipher")),Verified.class);
   if(v.birthDate().plusYears(14).isAfter(LocalDate.ofInstant(now,ZoneId.of("Asia/Seoul"))))throw problem("AGE_RESTRICTED",403);
   // The active-key advisory lock serializes registrations across all accepted HMAC versions.
   String activeDigest=box.mac("identity",v.scope()+"|"+v.subject());db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",Object.class,activeDigest);
   UUID user=findIdentity(v,true);
   UUID bound=uuid(r,"bound_user");
   if(bound!=null&&(principal==null||!bound.equals(principal.userId())||!uuid(r,"bound_session").equals(principal.sessionId())||!bound.equals(user)))throw problem("REAUTH_IDENTITY_MISMATCH",403);
   if(user==null){if(!TERMS.equals(termsVersion))throw problem("SIGNUP_CONSENT_REQUIRED",403);user=createMember(v.phone(),v.source(),TERMS);addIdentity(user,v);}
   else{
    var account=db.queryForMap("SELECT * FROM app_user WHERE id=? FOR UPDATE",user);
    if(!string(account,"status").equals("ACTIVE")||!string(account,"source").equals(v.source()))throw problem("ACCOUNT_UNAVAILABLE",403);
    if(!readPhone(user).equals(v.phone())){if(!confirmPhoneChange)throw problem("PHONE_CHANGE_REQUIRED",409);db.update("UPDATE app_user SET phone_cipher=? WHERE id=?",box.encrypt("account","phone:"+user,v.phone()),user);db.update("UPDATE auth_session SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",ts(now),user);}
    addIdentity(user,v);
   }
   if(bound!=null)db.update("UPDATE auth_session SET revoked_at=? WHERE id=?",ts(now),principal.sessionId());
   Tokens tokens=issue(user);
   db.update("UPDATE verification_transaction SET state='CONSUMED',consumed_at=?,verified_cipher=NULL,completion_key=?,completion_cipher=?,completion_until=? WHERE id=?",ts(now),requestKey,box.encrypt("temporary","completion:"+id,box.json(tokens)),ts(now.plusSeconds(30)),id);
   return tokens;
  });
 }
 private UUID findIdentity(Verified v,boolean lock){
  Set<UUID> users=new HashSet<>();for(String version:box.versions("identity")){String digest=box.mac("identity",version,v.scope()+"|"+v.subject());users.addAll(db.queryForList("SELECT user_id FROM verified_identity WHERE scope=? AND key_version=? AND digest=?"+(lock?" FOR UPDATE":""),UUID.class,v.scope(),version,digest));}
  if(users.size()>1)throw problem("IDENTITY_CONFLICT",409);return users.stream().findFirst().orElse(null);
 }
 private void addIdentity(UUID user,Verified v){db.update("INSERT INTO verified_identity VALUES(?,?,?,?,?) ON CONFLICT(user_id,scope,key_version) DO NOTHING",user,v.scope(),box.active("identity"),box.mac("identity",v.scope()+"|"+v.subject()),ts(clock.instant()));}
 public UUID createMember(String phone,String source,String terms){UUID user=UUID.randomUUID();Instant now=clock.instant();db.update("INSERT INTO app_user(id,environment,source,role,phone_cipher,created_at) VALUES(?,?,?,?,?,?)",user,settings.environment,source,"MEMBER",box.encrypt("account","phone:"+user,phone),ts(now));db.update("INSERT INTO health_consent(user_id,updated_at) VALUES(?,?)",user,ts(now));consent(user,"SIGNUP",terms,"GRANTED",source);return user;}
 public void consent(UUID user,String kind,String version,String action,String source){db.update("INSERT INTO consent_record VALUES(?,?,?,?,?,?,?)",UUID.randomUUID(),user,kind,version,action,source,ts(clock.instant()));}
 private String readPhone(UUID user){return box.decrypt("account","phone:"+user,db.queryForObject("SELECT phone_cipher FROM app_user WHERE id=?",String.class,user));}
 Tokens issue(UUID user){var u=db.queryForMap("SELECT * FROM app_user WHERE id=?",user);Instant now=clock.instant(),end=now.plus(settings.absolute(string(u,"role")));UUID session=UUID.randomUUID();String logout=box.token();db.update("INSERT INTO auth_session(id,user_id,environment,created_at,last_activity_at,expires_at,reauthenticated_at,logout_hash) VALUES(?,?,?,?,?,?,?,?)",session,user,settings.environment,ts(now),ts(now),ts(end),ts(now),box.mac("session",logout));return tokens(session,end,logout);}
 private Tokens tokens(UUID session,Instant end,String logout){Instant now=clock.instant(),accessEnd=now.plus(settings.access);if(accessEnd.isAfter(end))accessEnd=end;String access=box.token(),refresh=box.token();db.update("INSERT INTO session_token(digest,session_id,kind,expires_at) VALUES(?,?,?,?)",box.mac("session",access),session,"ACCESS",ts(accessEnd));db.update("INSERT INTO session_token(digest,session_id,kind,expires_at) VALUES(?,?,?,?)",box.mac("session",refresh),session,"REFRESH",ts(end));return new Tokens(access,refresh,logout,accessEnd,end);}
 private Map<String,Object> token(String raw,String kind){enabled();if(raw==null||!raw.matches("[A-Za-z0-9_-]{43}"))throw problem("AUTH_REQUIRED",401);for(String digest:box.macs("session",raw)){var rows=db.queryForList("SELECT t.*,s.user_id,s.environment,s.created_at,s.last_activity_at,s.expires_at AS session_expires_at,s.revoked_at,u.role,u.source,u.status,u.environment AS user_environment FROM session_token t JOIN auth_session s ON s.id=t.session_id JOIN app_user u ON u.id=s.user_id WHERE t.digest=? AND t.kind=?",digest,kind);if(!rows.isEmpty())return rows.getFirst();}throw problem("AUTH_REQUIRED",401);}
 private void valid(Map<String,Object> r){Instant now=clock.instant();if(r.get("revoked_at")!=null||!settings.environment.equals(string(r,"environment"))||!settings.environment.equals(string(r,"user_environment"))||!string(r,"status").equals("ACTIVE")||!instant(r,"expires_at").isAfter(now)||!instant(r,"session_expires_at").isAfter(now)||!instant(r,"last_activity_at").plus(settings.idle(string(r,"role"))).isAfter(now)||settings.environment.equals("production")&&!string(r,"source").equals("PRODUCTION"))throw problem("SESSION_EXPIRED",401);}
 public Principal authenticate(String access){var r=token(access,"ACCESS");valid(r);return new Principal(uuid(r,"user_id"),uuid(r,"session_id"),string(r,"role"),string(r,"source"),settings.environment);}
 public void activity(Principal p){db.update("UPDATE auth_session SET last_activity_at=? WHERE id=? AND revoked_at IS NULL AND expires_at>? AND last_activity_at>?",ts(clock.instant()),p.sessionId(),ts(clock.instant()),ts(clock.instant().minus(settings.idle(p.role()))));}
 public Map<String,Object> me(Principal p){String phone=readPhone(p.userId());var session=db.queryForMap("SELECT created_at,expires_at FROM auth_session WHERE id=?",p.sessionId());var consent=db.queryForMap("SELECT state,epoch FROM health_consent WHERE user_id=?",p.userId());return Map.of("userId",p.userId(),"role",p.role(),"source",p.source(),"environment",settings.environment,"phone",phone.startsWith("dev:")?phone:phone.replaceAll(".(?=.{4})","*"),"sessionExpiresAt",instant(session,"expires_at"),"healthConsent",Map.of("state",string(consent,"state"),"epoch",number(consent,"epoch")));}
 public Tokens refresh(String refresh,String requestKey){requestKey(requestKey);Tokens result=tx.execute(s->{var initial=token(refresh,"REFRESH");db.queryForMap("SELECT id FROM auth_session WHERE id=? FOR UPDATE",uuid(initial,"session_id"));var r=token(refresh,"REFRESH");valid(r);Instant now=clock.instant();
  if(r.get("consumed_at")!=null){if(requestKey.equals(string(r,"request_key"))&&instant(r,"replay_until")!=null&&instant(r,"replay_until").isAfter(now))return box.parse(box.decrypt("temporary","refresh:"+string(r,"digest"),string(r,"replay_cipher")),Tokens.class);db.update("UPDATE auth_session SET revoked_at=? WHERE id=?",ts(now),uuid(r,"session_id"));return null;}
  Tokens next=tokens(uuid(r,"session_id"),instant(r,"session_expires_at"),null);db.update("UPDATE session_token SET consumed_at=?,request_key=?,replay_cipher=?,replay_until=? WHERE digest=?",ts(now),requestKey,box.encrypt("temporary","refresh:"+string(r,"digest"),box.json(next)),ts(now.plusSeconds(30)),string(r,"digest"));return next;
 });if(result==null)throw problem("REFRESH_REUSE_DETECTED",401);return result;}
 public void logout(String proof){enabled();if(proof==null||proof.length()>128)throw problem("INVALID_LOGOUT_PROOF",400);for(String hash:box.macs("session",proof))db.update("UPDATE auth_session SET revoked_at=COALESCE(revoked_at,?) WHERE logout_hash=? AND environment=?",ts(clock.instant()),hash,settings.environment);}
 public void logoutAll(Principal p){db.update("UPDATE auth_session SET revoked_at=COALESCE(revoked_at,?) WHERE user_id=?",ts(clock.instant()),p.userId());}
 public static void requestKey(String value){if(value==null||!value.matches("[a-zA-Z0-9_-]{16,100}"))throw problem("IDEMPOTENCY_KEY_REQUIRED",400);}
}
