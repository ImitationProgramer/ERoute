package com.eroute;

import com.eroute.auth.*;
import com.eroute.memberhealth.HealthService;
import com.fasterxml.jackson.databind.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import static org.junit.jupiter.api.Assertions.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.*;

/** Real HTTP Security chain, real sessions and JDBC. Bootstrap is an explicit preceding command. */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={"eroute.auth.environment=test","eroute.auth.provider=development","eroute.auth.allow-development=true","eroute.jobs-enabled=false"})
@EnabledIfEnvironmentVariable(named="EROUTE_AUTH_TEST_CREDENTIALS",matches=".+")
class AuthHttpIntegrationTest {
 @LocalServerPort int port;
 @Autowired JdbcTemplate db;
 @Autowired MutableClock time;
 @Autowired SecretBox box;
 @Autowired HealthService health;
 @Autowired org.springframework.transaction.PlatformTransactionManager tm;
 @Autowired org.springframework.beans.factory.ObjectProvider<PhoneIdentityVerificationProvider> providers;
 static final ObjectMapper JSON=new ObjectMapper().findAndRegisterModules();
 final HttpClient http=HttpClient.newHttpClient();
 static JsonNode credentials;
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r)throws Exception{
  credentials=JSON.readTree(Files.readString(Path.of(System.getenv("EROUTE_AUTH_TEST_CREDENTIALS"))));
  r.add("spring.datasource.url",()->System.getenv("EROUTE_TEST_JDBC_URL"));r.add("spring.datasource.username",()->System.getenv("EROUTE_TEST_DB_USER"));r.add("spring.datasource.password",()->System.getenv().getOrDefault("EROUTE_TEST_DB_PASSWORD",""));r.add("eroute.auth.key-file",()->System.getenv("EROUTE_AUTH_TEST_KEYS"));
 }
 @TestConfiguration static class Config {@Bean @Primary MutableClock authClock(){return new MutableClock();}}
 static class MutableClock extends Clock {volatile Instant now=Instant.parse("2026-09-15T00:00:00Z");public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId z){return this;}public Instant instant(){return now;}void advance(Duration d){now=now.plus(d);}}
 record Reply(int status,JsonNode body){}
 Reply call(String method,String path,Object body,String access,Map<String,String> headers)throws Exception{
  var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+path)).header("Content-Type","application/json");if(access!=null)b.header("Authorization","Bearer "+access);headers.forEach(b::header);b.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body)));var r=http.send(b.build(),HttpResponse.BodyHandlers.ofString());return new Reply(r.statusCode(),r.body().isBlank()?JSON.createObjectNode():JSON.readTree(r.body()));
 }
 Reply call(String method,String path,Object body,String access)throws Exception{return call(method,path,body,access,Map.of());}
 JsonNode account(String alias){for(JsonNode a:credentials.path("accounts"))if(a.path("alias").asText().equals(alias))return a;throw new AssertionError("fixture missing");}
 record Verification(String id,String proof){}
 Verification verify(JsonNode fixture)throws Exception{
  String proof=box.token();var start=call("POST","/api/v1/auth/transactions",Map.of("phone",fixture.path("phone").asText(),"challenge",SecretBox.sha256(proof),"purpose","LOGIN"),null);assertEquals(200,start.status);String id=start.body.path("transactionId").asText();var verified=call("POST","/api/v1/auth/development/transactions/"+id+"/verify",Map.of("credential",fixture.path("credential").asText()),null,Map.of("X-Verification-Proof",proof));assertEquals(200,verified.status);return new Verification(id,proof);
 }
 JsonNode login(String alias)throws Exception{var v=verify(account(alias));var r=complete(v,Map.of("confirmPhoneChange",false),null);assertEquals(200,r.status);return r.body;}
 Reply complete(Verification v,Object body,String token)throws Exception{return call("POST","/api/v1/auth/transactions/"+v.id+"/complete",body,token,Map.of("X-Verification-Proof",v.proof,"Idempotency-Key",box.token()));}
 String access(JsonNode tokens){return tokens.path("accessToken").asText();}
 long grant(String a)throws Exception{var state=call("GET","/api/v1/me/health-consent",null,a);var r=call("POST","/api/v1/me/health-consent",Map.of("documentVersion","health-v1","epoch",state.body.path("epoch").asLong()),a);assertEquals(200,r.status);return r.body.path("epoch").asLong();}
 Map<String,Object> profile(long epoch,long version){return Map.of("consentEpoch",epoch,"version",version,"allergies",Map.of("status","RECORDED","text","가상 알레르기"),"conditions",Map.of("status","NONE","text",""),"note","가상 응급 메모","medicationsStatus","UNSET");}
 @BeforeEach void reset(){assertTrue(db.queryForObject("SELECT current_database()",String.class).endsWith("_test"));time.now=Instant.parse("2026-09-15T00:00:00Z");db.execute("TRUNCATE session_token,auth_session,verification_transaction,member_medication,member_health_profile,health_erasure,health_deletion_ledger,auth_rate_window");db.update("UPDATE health_consent SET state='UNSET',epoch=0");}
 @Test void operatorCannotReadMemberReviewPreview()throws Exception{
  assertEquals(403,call("GET","/api/v1/dev/reference/disease-departments-review-preview",null,access(login("operator"))).status);
 }
 @Test void fullCrudOwnershipLogoutAndReLogin()throws Exception{
  var a=login("member-a");String at=access(a);long e=grant(at);String bt=access(login("member-b"));grant(bt);
  assertEquals(200,call("PUT","/api/v1/me/emergency-profile",profile(e,0),at).status);
  assertEquals("",call("GET","/api/v1/me/emergency-profile",null,bt).body.path("note").asText());
  var added=call("POST","/api/v1/me/medications",Map.of("baseVersion",1,"consentEpoch",e,"name","가상 약 A","note","수동 기록"),at);assertEquals(200,added.status);assertTrue(added.body.path("productCode").isNull());String id=added.body.path("id").asText();
  for(String method:List.of("GET","PUT","DELETE")){
   Object body=method.equals("PUT")?Map.of("baseVersion",0,"consentEpoch",e,"version",1,"name","위조 변경","note",""):null;
   String path="/api/v1/me/medications/"+id+(method.equals("DELETE")?"?consentEpoch="+e+"&version=1&baseVersion=0":"");
   assertEquals(404,call(method,path,body,bt).status);assertEquals(401,call(method,path,body,null).status);
  }
  assertEquals(400,call("PUT","/api/v1/me/emergency-profile",Map.of("userId",UUID.randomUUID(),"consentEpoch",e,"version",0),bt).status);
  assertEquals(200,call("PUT","/api/v1/me/medications/"+id,Map.of("baseVersion",2,"consentEpoch",e,"version",1,"name","가상 약 수정","note","수정 메모"),at).status);
  assertEquals(200,call("POST","/api/v1/auth/logout",Map.of("logoutProof",a.path("logoutProof").asText()),null).status);
  assertEquals(401,call("GET","/api/v1/me",null,at).status);
  assertEquals(401,call("POST","/api/v1/auth/refresh",Map.of("refreshToken",a.path("refreshToken").asText()),null,Map.of("Idempotency-Key",box.token())).status);
  assertEquals(200,call("GET","/api/v1/me",null,bt).status);
  String again=access(login("member-a"));var stored=call("GET","/api/v1/me/medications/"+id,null,again);assertEquals("가상 약 수정",stored.body.path("name").asText());
  assertEquals(200,call("DELETE","/api/v1/me/medications/"+id+"?consentEpoch="+e+"&version=2&baseVersion=3",null,again).status);
  assertEquals(404,call("GET","/api/v1/me/medications/"+id,null,again).status);
  var p=call("GET","/api/v1/me/emergency-profile",null,again);assertEquals("UNSET",p.body.path("medicationsStatus").asText());
  assertEquals(200,call("DELETE","/api/v1/me/emergency-profile",Map.of("consentEpoch",e,"version",p.body.path("version").asLong()),again).status);
  assertEquals("UNSET",call("GET","/api/v1/me/emergency-profile",null,again).body.path("allergies").path("status").asText());
 }
 @Test void withdrawalKeepsSessionBlocksOldAndOtherDeviceWrites()throws Exception{
  var a=login("member-a");String at=access(a),other=access(login("member-a")),bt=access(login("member-b"));long e=grant(at);grant(bt);call("PUT","/api/v1/me/emergency-profile",profile(e,0),at);call("PUT","/api/v1/me/emergency-profile",profile(e,0),bt);
  String key=box.token();var r=call("POST","/api/v1/me/health-consent/withdrawals",Map.of("epoch",e),at,Map.of("Idempotency-Key",key));assertEquals(200,r.status);assertEquals("COMPLETE",r.body.path("state").asText());assertFalse(r.body.path("backupComplete").asBoolean());
  assertEquals(200,call("GET","/api/v1/me",null,at).status);assertEquals(200,call("GET","/api/v1/me/health-consent/withdrawals/"+r.body.path("id").asText(),null,at).status);
  for(String token:List.of(at,other)){assertEquals(403,call("GET","/api/v1/me/emergency-profile",null,token).status);assertEquals(403,call("PUT","/api/v1/me/emergency-profile",profile(e,1),token).status);assertEquals(403,call("POST","/api/v1/me/medications",Map.of("baseVersion",1,"consentEpoch",e,"name","늦은 가상 약"),token).status);}
  assertEquals(200,call("POST","/api/v1/auth/refresh",Map.of("refreshToken",a.path("refreshToken").asText()),null,Map.of("Idempotency-Key",box.token())).status);
  assertEquals(r.body.path("id"),call("POST","/api/v1/me/health-consent/withdrawals",Map.of("epoch",e),at,Map.of("Idempotency-Key",key)).body.path("id"));
  assertEquals(200,call("GET","/api/v1/me/emergency-profile",null,bt).status);grant(at);
  assertEquals(409,call("PUT","/api/v1/me/emergency-profile",profile(e,0),other).status);
  assertEquals("UNSET",call("GET","/api/v1/me/emergency-profile",null,at).body.path("allergies").path("status").asText());
 }
 @Test void refreshDuplicateReuseIdleAndAbsoluteExpiry()throws Exception{
  var a=login("member-a");String key=box.token();var body=Map.of("refreshToken",a.path("refreshToken").asText());
  var first=call("POST","/api/v1/auth/refresh",body,null,Map.of("Idempotency-Key",key));var duplicate=call("POST","/api/v1/auth/refresh",body,null,Map.of("Idempotency-Key",key));assertEquals(first.body,duplicate.body);
  assertEquals(401,call("POST","/api/v1/auth/refresh",body,null,Map.of("Idempotency-Key",box.token())).status);assertEquals(401,call("GET","/api/v1/me",null,access(first.body)).status);
  var idle=login("member-a");time.advance(Duration.ofDays(7));assertEquals(401,call("POST","/api/v1/auth/refresh",Map.of("refreshToken",idle.path("refreshToken").asText()),null,Map.of("Idempotency-Key",box.token())).status);
  var absolute=login("member-a");for(int i=0;i<5;i++){time.advance(Duration.ofDays(5));var next=call("POST","/api/v1/auth/refresh",Map.of("refreshToken",absolute.path("refreshToken").asText()),null,Map.of("Idempotency-Key",box.token()));assertEquals(200,next.status);absolute=next.body;assertEquals(200,call("POST","/api/v1/me/activity",Map.of(),access(absolute)).status);}
  time.advance(Duration.ofDays(5));assertEquals(401,call("POST","/api/v1/auth/refresh",Map.of("refreshToken",absolute.path("refreshToken").asText()),null,Map.of("Idempotency-Key",box.token())).status);
 }
 @Test void transactionBindingExpiryAndOperatorBoundary()throws Exception{
  var v=verify(account("member-a"));
  String owner=access(login("member-a"));
  assertEquals(400,call("POST","/api/v1/me/phone-change",Map.of("transactionId",v.id),owner,Map.of("X-Verification-Proof",v.proof,"Idempotency-Key",box.token())).status);
  assertEquals(404,complete(new Verification(v.id,box.token()),Map.of("confirmPhoneChange",false),null).status);
  time.advance(Duration.ofMinutes(5));assertEquals(409,complete(v,Map.of("confirmPhoneChange",false),null).status);
  String op=access(login("operator"));assertEquals(200,call("GET","/api/v1/ops/status",null,op).status);assertEquals(403,call("GET","/api/v1/me/emergency-profile",null,op).status);assertEquals(403,call("GET","/api/v1/ops/status",null,access(login("member-b"))).status);
  assertEquals(200,call("GET","/api/v1/map-config",null,"invalid-token").status);
 }
 @Test void encryptedDataTamperDoesNotBecomeEmptyAndCanBeErased()throws Exception{
  String at=access(login("member-a"));long e=grant(at);call("PUT","/api/v1/me/emergency-profile",profile(e,0),at);
  String user=call("GET","/api/v1/me",null,at).body.path("userId").asText();String cipher=db.queryForObject("SELECT body_cipher FROM member_health_profile WHERE user_id=?",String.class,UUID.fromString(user));assertFalse(cipher.contains("가상"));
  assertThrows(com.eroute.common.error.ServiceProblem.class,()->box.decrypt("health","wrong-owner",cipher));
  db.update("UPDATE member_health_profile SET body_cipher='tampered' WHERE user_id=?",UUID.fromString(user));
  assertEquals(503,call("GET","/api/v1/me/emergency-profile",null,at).status);assertEquals(503,call("PUT","/api/v1/me/emergency-profile",profile(e,1),at).status);
  assertEquals("tampered",db.queryForObject("SELECT body_cipher FROM member_health_profile WHERE user_id=?",String.class,UUID.fromString(user)));
  assertEquals("COMPLETE",call("POST","/api/v1/me/health-consent/withdrawals",Map.of("epoch",e),at,Map.of("Idempotency-Key",box.token())).body.path("state").asText());
 }
 @Test void birthdayBoundaryAndConsentRequired()throws Exception{
  for(int offset:List.of(1,0,-1)){
   String phone="dev:age"+(offset+1),secret=box.token(),subject=UUID.randomUUID().toString();LocalDate birth=LocalDate.of(2012,9,15).plusDays(offset);
   db.update("INSERT INTO dev_identity_fixture VALUES(?,?,?,?) ON CONFLICT(phone) DO UPDATE SET subject=excluded.subject,credential_hash=excluded.credential_hash,birth_date=excluded.birth_date",phone,subject,SecretBox.sha256(secret),java.sql.Date.valueOf(birth));
   String proof=box.token();var start=call("POST","/api/v1/auth/transactions",Map.of("phone",phone,"challenge",SecretBox.sha256(proof)),null);String id=start.body.path("transactionId").asText();var verified=call("POST","/api/v1/auth/development/transactions/"+id+"/verify",Map.of("credential",secret),null,Map.of("X-Verification-Proof",proof));
   if(offset==1){assertEquals(403,verified.status);assertEquals("AGE_RESTRICTED",verified.body.path("code").asText());}else{assertEquals(200,verified.status);assertEquals(403,complete(new Verification(id,proof),Map.of("confirmPhoneChange",false),null).status);assertEquals(200,complete(new Verification(id,proof),Map.of("confirmPhoneChange",false,"termsVersion","signup-v1"),null).status);}
  }
 }
 @Test void concurrentWithdrawalAndSaveCannotResurrect()throws Exception{
  String at=access(login("member-a"));long e=grant(at);call("PUT","/api/v1/me/emergency-profile",profile(e,0),at);
  try(var pool=Executors.newVirtualThreadPerTaskExecutor()){
   var start=new CountDownLatch(1);var save=pool.submit(()->{start.await();return call("PUT","/api/v1/me/emergency-profile",profile(e,1),at);});var withdraw=pool.submit(()->{start.await();return call("POST","/api/v1/me/health-consent/withdrawals",Map.of("epoch",e),at,Map.of("Idempotency-Key",box.token()));});start.countDown();assertTrue(Set.of(200,403,409).contains(save.get().status));assertEquals(200,withdraw.get().status);
  }
  assertEquals(0L,db.queryForObject("SELECT count(*) FROM member_health_profile",Long.class));assertEquals(403,call("GET","/api/v1/me/emergency-profile",null,at).status);
 }
 @Test void erasureFailureRemainsBlockedAndRetryIsIdempotent()throws Exception{
  String at=access(login("member-a"));long e=grant(at);call("PUT","/api/v1/me/emergency-profile",profile(e,0),at);
  db.execute("CREATE OR REPLACE FUNCTION auth_test_delete_failure() RETURNS trigger LANGUAGE plpgsql AS 'BEGIN RAISE EXCEPTION ''synthetic deletion failure''; END;'");
  db.execute("CREATE TRIGGER auth_test_delete_failure BEFORE DELETE ON member_health_profile FOR EACH ROW EXECUTE FUNCTION auth_test_delete_failure()");
  String id;
  try{var r=call("POST","/api/v1/me/health-consent/withdrawals",Map.of("epoch",e),at,Map.of("Idempotency-Key",box.token()));assertEquals(200,r.status);assertEquals("FAILED",r.body.path("state").asText());id=r.body.path("id").asText();assertEquals(403,call("GET","/api/v1/me/emergency-profile",null,at).status);assertEquals(200,call("GET","/api/v1/me",null,at).status);assertEquals(409,call("POST","/api/v1/me/health-consent",Map.of("documentVersion","health-v1","epoch",e+1),at).status);}
  finally{db.execute("DROP TRIGGER auth_test_delete_failure ON member_health_profile");db.execute("DROP FUNCTION auth_test_delete_failure()");}
  for(int i=0;i<2;i++)assertEquals("COMPLETE",call("POST","/api/v1/me/health-consent/withdrawals/"+id+"/retry",Map.of(),at).body.path("state").asText());
 }
 @Test void rotationRetainsIdentityAndCiphertextAndMissingKeysFailClosed()throws Exception{
  String at=access(login("member-a"));long e=grant(at);call("PUT","/api/v1/me/emergency-profile",profile(e,0),at);
  String before=call("GET","/api/v1/me",null,at).body.path("userId").asText();
  var config=(com.fasterxml.jackson.databind.node.ObjectNode)JSON.readTree(Files.readString(Path.of(System.getenv("EROUTE_AUTH_TEST_KEYS"))));String ver="rotate-"+UUID.randomUUID().toString().substring(0,8);
  for(String purpose:List.of("health","identity")){var ring=(com.fasterxml.jackson.databind.node.ObjectNode)config.path(purpose);ring.put("active",ver);((com.fasterxml.jackson.databind.node.ObjectNode)ring.path("keys")).put(ver,box.token());}
  Path file=Files.createTempFile("eroute-test-keys-",".json");
  try{
   Files.writeString(file,JSON.writeValueAsString(config));
   var env=new org.springframework.mock.env.MockEnvironment().withProperty("eroute.auth.environment","test").withProperty("eroute.auth.provider","development").withProperty("eroute.auth.allow-development","true").withProperty("eroute.auth.key-file",file.toString());
   var settings=new AuthSettings(env);var next=new SecretBox(settings,db,tm);next.validateRegistry();var service=new AuthService(db,next,settings,time,tm,providers);
   String proof=next.token();UUID transaction=(UUID)service.start(account("member-a").path("phone").asText(),SecretBox.sha256(proof),"LOGIN",null).get("transactionId");service.verify(transaction,proof,account("member-a").path("credential").asText());var tokens=service.complete(transaction,proof,next.token(),null,false,null);
   assertEquals(before,service.authenticate(tokens.accessToken()).userId().toString());
   new AuthMaintenance(db,next,settings,time).reencrypt();String encrypted=db.queryForObject("SELECT body_cipher FROM member_health_profile WHERE user_id=?",String.class,UUID.fromString(before));assertTrue(encrypted.startsWith("v1."+ver+"."));assertTrue(next.decrypt("health","profile:"+before+":"+e,encrypted).contains("가상 응급 메모"));
   ((com.fasterxml.jackson.databind.node.ObjectNode)config.path("identity").path("keys")).remove("v1");Files.writeString(file,JSON.writeValueAsString(config));assertThrows(IllegalStateException.class,()->new SecretBox(settings,db,tm).validateRegistry());
   ((com.fasterxml.jackson.databind.node.ObjectNode)config.path("health").path("keys")).put(ver,box.token());Files.writeString(file,JSON.writeValueAsString(config));assertThrows(IllegalStateException.class,()->new SecretBox(settings,db,tm).validateRegistry());
  }finally{Files.deleteIfExists(file);}
 }
 @Test void nonceAuthenticationAndUsageLimit()throws Exception{
  String first=box.encrypt("health","test:A","가상 데이터"),second=box.encrypt("health","test:A","가상 데이터");assertNotEquals(first,second);
  String[] parts=first.split("\\.");parts[4]=box.token().substring(0,22);assertThrows(com.eroute.common.error.ServiceProblem.class,()->box.decrypt("health","test:A",String.join(".",parts)));
  String key="test:health:"+box.active("health");long previous=db.queryForObject("SELECT encryptions FROM crypto_key_usage WHERE key_id=?",Long.class,key);db.update("UPDATE crypto_key_usage SET encryptions=4294967296 WHERE key_id=?",key);try{assertThrows(com.eroute.common.error.ServiceProblem.class,()->box.encrypt("health","test:A","가상 데이터"));}finally{db.update("UPDATE crypto_key_usage SET encryptions=? WHERE key_id=?",previous,key);}
 }
 @Test void providerResultCannotBeSwappedAndPhoneChangeRevokesAllSessions()throws Exception{
  var existing=login("member-a");String oldAccess=access(existing);String subject=db.queryForObject("SELECT subject FROM dev_identity_fixture WHERE phone='dev:member-a'",String.class);String credential=box.token();
  db.update("INSERT INTO dev_identity_fixture VALUES('dev:changed-a',?,?,DATE '2000-01-01') ON CONFLICT(phone) DO UPDATE SET subject=excluded.subject,credential_hash=excluded.credential_hash",subject,SecretBox.sha256(credential));
  var fixture=JSON.valueToTree(Map.of("phone","dev:changed-a","credential",credential));var v=verify(fixture);assertEquals(409,complete(v,Map.of("confirmPhoneChange",false),null).status);assertEquals(200,complete(v,Map.of("confirmPhoneChange",true),null).status);assertEquals(401,call("GET","/api/v1/me",null,oldAccess).status);
  var original=verify(account("member-a"));assertEquals(200,complete(original,Map.of("confirmPhoneChange",true),null).status);
  String proof=box.token();var start=call("POST","/api/v1/auth/transactions",Map.of("phone",account("member-a").path("phone").asText(),"challenge",SecretBox.sha256(proof)),null);String id=start.body.path("transactionId").asText();assertEquals(403,call("POST","/api/v1/auth/development/transactions/"+id+"/verify",Map.of("credential",account("member-b").path("credential").asText()),null,Map.of("X-Verification-Proof",proof)).status);
 }

}
