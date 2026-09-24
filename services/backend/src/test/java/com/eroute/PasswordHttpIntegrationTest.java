package com.eroute;

import com.eroute.auth.*;
import com.eroute.memberhealth.HealthService;
import com.fasterxml.jackson.databind.*;
import java.net.*;
import java.net.http.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import static org.junit.jupiter.api.Assertions.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.*;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={"eroute.auth.environment=test","eroute.auth.provider=password","eroute.jobs-enabled=false"})
@EnabledIfEnvironmentVariable(named="EROUTE_AUTH_TEST_KEYS",matches=".+")
class PasswordHttpIntegrationTest {
 @LocalServerPort int port;
 @Autowired JdbcTemplate db;@Autowired AuthService auth;@Autowired HealthService health;
 @Autowired PasswordAuthService passwords;@Autowired org.springframework.transaction.PlatformTransactionManager tm;
 @Autowired com.eroute.personalization.DiseaseReference runtimeReference;
 static final ObjectMapper JSON=new ObjectMapper().findAndRegisterModules();
 final HttpClient http=HttpClient.newHttpClient();
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r){
  r.add("spring.datasource.url",()->System.getenv("EROUTE_TEST_JDBC_URL"));r.add("spring.datasource.username",()->System.getenv("EROUTE_TEST_DB_USER"));r.add("spring.datasource.password",()->System.getenv().getOrDefault("EROUTE_TEST_DB_PASSWORD",""));r.add("eroute.auth.key-file",()->System.getenv("EROUTE_AUTH_TEST_KEYS"));
 }
 record Reply(int status,JsonNode body){}
 Reply call(String method,String path,Object body,String access)throws Exception{
  var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+path)).header("Content-Type","application/json").header("Idempotency-Key",UUID.randomUUID().toString());
  if(access!=null)b.header("Authorization","Bearer "+access);
  b.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body)));
  var r=http.send(b.build(),HttpResponse.BodyHandlers.ofString());return new Reply(r.statusCode(),r.body().isBlank()?JSON.createObjectNode():JSON.readTree(r.body()));
 }
 String phone(){return "010"+String.format("%08d",new java.security.SecureRandom().nextInt(100000000));}
 String password(){return " 가상 e\u0301 😀 "+UUID.randomUUID()+" ";}
 Map<String,Object> signupBody(String phone,String password){return Map.of("phone",phone,"password",password,"termsVersion",PasswordPolicy.TERMS,"termsAccepted",true,"age14OrOlder",true);}
 record Account(String phone,String password,String access,UUID user){}
 Account signup()throws Exception{return signup(phone(),password());}
 Account signup(String phone,String password)throws Exception{
  var r=call("POST","/api/v1/auth/signup",signupBody(phone,password),null);assertEquals(200,r.status);
  String access=r.body.path("accessToken").asText();var me=call("GET","/api/v1/me",null,access);assertEquals(200,me.status);
  return new Account(phone,password,access,UUID.fromString(me.body.path("userId").asText()));
 }
 long grant(Account a)throws Exception{
  var state=call("GET","/api/v1/me/health-consent",null,a.access);long epoch=state.body.path("epoch").asLong();
  var r=call("POST","/api/v1/me/health-consent",Map.of("documentVersion","health-v1","epoch",epoch),a.access);assertEquals(200,r.status);return r.body.path("epoch").asLong();
 }
 Map<String,Object> medication(long base,long epoch){return Map.of("baseVersion",base,"consentEpoch",epoch,"name","가상 수동약","note","가상 메모");}
 Map<String,Object> profile(long version,long epoch){return Map.of("version",version,"consentEpoch",epoch,"allergies",Map.of("status","RECORDED","text","가상 알레르기"),"conditions",Map.of("status","NONE","text",""),"note","가상 응급 메모","medicationsStatus","UNSET");}
 @BeforeEach void onlyDisposable(){assertTrue(db.queryForObject("SELECT current_database()",String.class).startsWith("member_run_"));db.execute("DELETE FROM auth_rate_window");}
 @Test void developmentReviewProjectionIsAuthenticatedMinimalAndPublicStaysApprovedOnly()throws Exception{
  String path="/api/v1/dev/reference/disease-departments-review-preview";
  assertEquals(401,call("GET",path,null,null).status);
  var a=signup();var result=call("GET",path,null,a.access);
  boolean built;try{Class.forName("com.eroute.personalization.DiseaseReviewPreviewController");built=true;}catch(ClassNotFoundException e){built=false;}
  if(built){
   assertEquals(200,result.status);assertEquals("DEVELOPMENT_REVIEW_PREVIEW",result.body.path("documentType").asText());
   assertEquals(61,result.body.path("mappings").size());
   var names=new HashSet<String>();result.body.fieldNames().forEachRemaining(names::add);
   assertEquals(Set.of("documentType","referenceVersion","mappings"),names);
   for(var m:result.body.path("mappings")){
    assertEquals("DRAFT",m.path("reviewStatus").asText());assertEquals("DIRECT",m.path("relationType").asText());
    var fields=new HashSet<String>();m.fieldNames().forEachRemaining(fields::add);
    assertEquals(Set.of("id","diseaseId","departmentId","relationType","reviewStatus","reviewClass","mappingScope","version"),fields);
   }
  }else assertTrue(Set.of(403,404).contains(result.status));
  var publicResult=call("GET","/api/v1/reference/disease-departments",null,null);
  assertEquals(200,publicResult.status);assertEquals(0,JSON.readTree(publicResult.body.path("document").asText()).path("mappings").size());
 }
 @Test void independentCatalogAndStructuredConditionsPreserveOtherEdits()throws Exception{
  int nmcBefore=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class);
  var catalog=call("GET","/api/v1/reference/diseases",null,null);assertEquals(200,catalog.status);assertEquals(46,catalog.body.path("diseases").size());
  var a=signup();long epoch=grant(a);
  var input=new LinkedHashMap<String,Object>();input.put("version",0);input.put("consentEpoch",epoch);input.put("status","RECORDED");input.put("catalogVersion",catalog.body.path("catalogVersion").asText());input.put("conditionEntries",List.of(Map.of("type","STANDARD","diseaseId","D018"),Map.of("type","CUSTOM","customName","  가상 미등록 질환  ")));
  var saved=call("PUT","/api/v1/me/conditions",input,a.access);assertEquals(200,saved.status);assertEquals(2,saved.body.path("conditionEntries").size());assertEquals("이상지질혈증",saved.body.path("conditionEntries").get(0).path("displayName").asText());assertEquals("NOT_SELECTED",saved.body.path("mapDiseaseSelection").path("state").asText());
  assertEquals(409,call("PUT","/api/v1/me/conditions",input,a.access).status);
  var snapshot=call("GET","/api/v1/me/health-snapshot",null,a.access);
  var update=new LinkedHashMap<String,Object>(profile(1,epoch));update.put("conditions",JSON.convertValue(snapshot.body.path("conditions"),Map.class));
  assertEquals(200,call("PUT","/api/v1/me/emergency-profile",update,a.access).status);
  assertEquals(saved.body.path("conditionEntries"),call("GET","/api/v1/me/conditions",null,a.access).body.path("conditionEntries"));
  input.put("version",2);input.put("freeText","mixed");assertEquals(400,call("PUT","/api/v1/me/conditions",input,a.access).status);
  assertEquals(nmcBefore,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class));
 }
 @Test void realPasswordSignupLoginConsentPersistenceAndLogout()throws Exception{
  long nmc=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class);
  var a=signup();assertEquals(0,db.queryForObject("SELECT count(*) FROM verified_identity WHERE user_id=?",Integer.class,a.user));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM consent_record WHERE user_id=? AND kind='AGE_SELF_DECLARATION'",Integer.class,a.user));
  assertEquals(403,call("GET","/api/v1/me/health-snapshot",null,a.access).status);
  assertEquals(401,call("POST","/api/v1/auth/login",Map.of("phone",a.phone,"password",password()),null).status);
  assertEquals(200,call("POST","/api/v1/auth/reauth",Map.of("password",a.password),a.access).status);
  long e=grant(a);assertEquals(200,call("PUT","/api/v1/me/emergency-profile",profile(0,e),a.access).status);
  assertEquals(200,call("POST","/api/v1/me/medications",medication(1,e),a.access).status);
  var login=call("POST","/api/v1/auth/login",Map.of("phone",a.phone,"password",PasswordPolicy.normalize(a.password)),null);assertEquals(200,login.status);
  String token=login.body.path("accessToken").asText();var snap=call("GET","/api/v1/me/health-snapshot",null,token);
  assertEquals(2,snap.body.path("version").asInt());assertEquals(1,snap.body.path("medications").size());assertEquals("NONE",snap.body.path("conditions").path("status").asText());
  String cipher=db.queryForObject("SELECT body_cipher FROM member_health_profile WHERE user_id=?",String.class,a.user);assertFalse(cipher.contains("가상"));
  assertEquals(200,call("POST","/api/v1/auth/logout",Map.of("logoutProof",login.body.path("logoutProof").asText()),null).status);
  assertEquals(401,call("GET","/api/v1/me",null,token).status);assertEquals(401,call("POST","/api/v1/auth/refresh",Map.of("refreshToken",login.body.path("refreshToken").asText()),null).status);
  assertEquals(200,call("GET","/api/v1/me",null,a.access).status);assertEquals(nmc,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class));
 }
 @Test void missingConflictOwnershipAndProductRejection()throws Exception{
  var a=signup();var b=signup();var operator=signup();db.update("UPDATE app_user SET role='OPERATOR' WHERE id=?",operator.user);long e=grant(a);grant(b);
  var missing=call("POST","/api/v1/me/medications",Map.of("consentEpoch",e,"name","가상"),a.access);assertEquals(400,missing.status);assertEquals("PRECONDITION_REQUIRED",missing.body.path("code").asText());
  assertEquals(400,call("POST","/api/v1/me/medications",Map.of("baseVersion",0,"name","가상"),a.access).status);
  assertEquals(409,call("POST","/api/v1/me/medications",medication(99,e),a.access).status);
  var product=new HashMap<>(medication(0,e));product.put("productCode","preview-product-fake");assertEquals(400,call("POST","/api/v1/me/medications",product,a.access).status);
  var added=call("POST","/api/v1/me/medications",medication(0,e),a.access);assertEquals(200,added.status);String id=added.body.path("id").asText();
  var update=new HashMap<>(medication(1,e));update.put("version",1);
  assertEquals(404,call("GET","/api/v1/me/medications/"+id,null,b.access).status);
  assertEquals(404,call("PUT","/api/v1/me/medications/"+id,update,b.access).status);
  assertEquals(404,call("DELETE","/api/v1/me/medications/"+id+"?baseVersion=0&version=1&consentEpoch="+e,null,b.access).status);
  assertEquals(403,call("GET","/api/v1/me/health-snapshot",null,operator.access).status);
  assertEquals(400,call("DELETE","/api/v1/me/medications/"+id+"?version=1&consentEpoch="+e,null,a.access).status);
  assertEquals(400,call("DELETE","/api/v1/me/medications/"+id+"?baseVersion=invalid&version=1&consentEpoch="+e,null,a.access).status);
  assertEquals(409,call("DELETE","/api/v1/me/medications/"+id+"?baseVersion=0&version=1&consentEpoch="+e,null,a.access).status);
  assertEquals(200,call("PUT","/api/v1/me/medications/"+id,update,a.access).status);
  assertEquals(409,call("PUT","/api/v1/me/medications/"+id,update,a.access).status);
  assertEquals(200,call("DELETE","/api/v1/me/medications/"+id+"?baseVersion=2&version=2&consentEpoch="+e,null,a.access).status);
 }
 @Test void simultaneousSignupCannotOverwriteExistingCredential()throws Exception{
  String phone=phone(),pw=password(),other=password();
  try(var executor=Executors.newVirtualThreadPerTaskExecutor()){
   var one=executor.submit(()->call("POST","/api/v1/auth/signup",signupBody(phone,pw),null));
   var two=executor.submit(()->call("POST","/api/v1/auth/signup",signupBody(phone.substring(0,3)+"-"+phone.substring(3,7)+"-"+phone.substring(7),other),null));
   var r1=one.get();var r2=two.get();assertEquals(Set.of(200,409),Set.of(r1.status,r2.status));
   String winner=r1.status==200?pw:other,loser=r1.status==200?other:pw;
   assertEquals(200,call("POST","/api/v1/auth/login",Map.of("phone",phone,"password",winner),null).status);
   assertEquals(401,call("POST","/api/v1/auth/login",Map.of("phone",phone,"password",loser),null).status);
  }
 }
 @Test void snapshotWaitsForWholeMutationAndWithdrawalNeverMixesEpochs()throws Exception{
  var a=signup();long e=grant(a);var p=auth.authenticate(a.access);var entered=new CountDownLatch(1);var release=new CountDownLatch(1);
  try(var executor=Executors.newVirtualThreadPerTaskExecutor()){
   var write=executor.submit(()->new TransactionTemplate(tm).execute(s->{health.saveProfile(p,profile(0,e),false);entered.countDown();try{if(!release.await(5,TimeUnit.SECONDS))throw new IllegalStateException("timeout");}catch(InterruptedException ex){throw new RuntimeException(ex);}health.saveMedication(p,null,medication(1,e));return true;}));
   assertTrue(entered.await(5,TimeUnit.SECONDS));var read=executor.submit(()->call("GET","/api/v1/me/health-snapshot",null,a.access));
   Thread.sleep(150);assertFalse(read.isDone());release.countDown();assertTrue(write.get());var snapshot=read.get();assertEquals(200,snapshot.status);
   assertEquals(2,snapshot.body.path("version").asInt());assertEquals("RECORDED",snapshot.body.path("medicationsStatus").asText());assertEquals(1,snapshot.body.path("medications").size());assertEquals(e,snapshot.body.path("medications").get(0).path("consentEpoch").asLong());
   var withdraw=executor.submit(()->call("POST","/api/v1/me/health-consent/withdrawals",Map.of("epoch",e),a.access));
   var concurrent=executor.submit(()->call("GET","/api/v1/me/health-snapshot",null,a.access));
   var during=concurrent.get();assertTrue(during.status==200||during.status==403);if(during.status==200){assertEquals(e,during.body.path("consentEpoch").asLong());assertEquals(1,during.body.path("medications").size());}
   assertEquals(200,withdraw.get().status);assertEquals(200,call("GET","/api/v1/me",null,a.access).status);assertEquals(403,call("GET","/api/v1/me/health-snapshot",null,a.access).status);
   long newEpoch=grant(a);assertTrue(newEpoch>e);assertEquals(409,call("POST","/api/v1/me/medications",medication(2,e),a.access).status);
   var empty=call("GET","/api/v1/me/health-snapshot",null,a.access);assertEquals(0,empty.body.path("version").asInt());assertEquals(0,empty.body.path("medications").size());assertEquals("",empty.body.path("note").asText());
  }
 }
 Map<String,Object> conditionsInput(long version,long epoch,String text,List<String> ids,String status){return Map.of("version",version,"consentEpoch",epoch,"freeText",text,"diseaseIds",ids,"status",status,"catalogVersion",runtimeReference.catalogVersion());}
 Map<String,Object> mapSelection(long version,long epoch){return Map.of("version",version,"consentEpoch",epoch,"diseaseIds",List.of("D001","D010"),"purpose",runtimeReference.purpose(),"purposeVersion",runtimeReference.purposeVersion(),"referenceVersion",runtimeReference.version(),"confirmed",true);}
 @Test void staleReferenceIsRejectedWhileInjectedRuntimeVersionSucceeds()throws Exception{
  var a=signup();long epoch=grant(a);
  var response=call("GET","/api/v1/reference/disease-departments",null,null);
  assertEquals(200,response.status);
  var published=JSON.readTree(response.body.path("document").asText());
  assertEquals(runtimeReference.version(),published.path("datasetVersion").asText());
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(0,epoch,"",List.of("D001","D010"),"RECORDED"),a.access).status);
  String historical=new com.eroute.personalization.FileReferenceRepository("reference/disease-departments/v0.4.json").read().datasetVersion();
  var stale=new HashMap<>(mapSelection(1,epoch));
  // In development this is the actual immutable v0.4. Keep the contract test useful in production-profile builds too.
  stale.put("referenceVersion",historical.equals(runtimeReference.version())?historical+"-stale":historical);
  assertEquals(409,call("PUT","/api/v1/me/map-disease-selection",stale,a.access).status);
  assertEquals("NOT_SELECTED",call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection").path("state").asText());
  assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",mapSelection(1,epoch),a.access).status);
  var saved=call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection");
  assertEquals("CONFIRMED",saved.path("state").asText());assertEquals(runtimeReference.version(),saved.path("referenceVersion").asText());
 }
 @Test void explicitSelectionPreservesRawAndOldClientsRequireReconfirmation()throws Exception{
  long nmc=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class);var a=signup();long e=grant(a);
  var p=new HashMap<>(profile(0,e));p.put("conditions",Map.of("status","RECORDED","text","천식 의심 · 사용자가 기록한 문장"));
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(0,e,"천식 의심 · 사용자가 기록한 문장",List.of("D001","D010"),"RECORDED"),a.access).status);
  assertEquals("NOT_SELECTED",call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection").path("state").asText());
  assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",mapSelection(1,e),a.access).status);
  var raw=call("GET","/api/v1/me/health-snapshot",null,a.access).body;assertEquals("천식 의심 · 사용자가 기록한 문장",raw.path("conditions").path("text").asText());assertEquals(2,raw.path("version").asInt());
  String cipher=db.queryForObject("SELECT body_cipher FROM member_health_profile WHERE user_id=?",String.class,a.user);assertFalse(cipher.contains("D001"));assertFalse(cipher.contains("천식"));
  p.put("version",2);p.put("note","관련 없는 메모 수정");assertEquals(200,call("PUT","/api/v1/me/emergency-profile",p,a.access).status);
  assertEquals("CONFIRMED",call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection").path("state").asText());
  p.put("version",3);p.put("conditions",Map.of("status","RECORDED","text","천식 없음"));assertEquals(200,call("PUT","/api/v1/me/emergency-profile",p,a.access).status);
  var changed=call("GET","/api/v1/me/map-disease-selection",null,a.access).body;assertEquals("RECONFIRM_REQUIRED",changed.path("mapDiseaseSelection").path("state").asText());assertEquals(2,changed.path("mapDiseaseSelection").path("diseaseIds").size());
  assertEquals(409,call("PUT","/api/v1/me/map-disease-selection",mapSelection(3,e),a.access).status);
  assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",mapSelection(4,e),a.access).status);
  assertEquals(200,call("DELETE","/api/v1/me/map-disease-selection",Map.of("version",5,"consentEpoch",e),a.access).status);
  assertEquals("천식 없음",call("GET","/api/v1/me/health-snapshot",null,a.access).body.path("conditions").path("text").asText());
  assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",mapSelection(6,e),a.access).status);
  p.put("version",7);p.put("conditions",Map.of("status","NONE","text",""));assertEquals(200,call("PUT","/api/v1/me/emergency-profile",p,a.access).status);
  assertEquals(0,call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection").path("diseaseIds").size());
  assertEquals(400,call("PUT","/api/v1/me/map-disease-selection",mapSelection(8,e),a.access).status);
  assertEquals(nmc,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class));
 }
 @Test void selectionValidationDeletionAndOwnershipUseExistingConsentBoundary()throws Exception{
  var a=signup();var b=signup();long e=grant(a);grant(b);
  var p=new HashMap<>(profile(0,e));p.put("conditions",Map.of("status","RECORDED","text","가상 기록"));assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(0,e,"가상 기록",List.of("D001","D010"),"RECORDED"),a.access).status);
  assertEquals(401,call("GET","/api/v1/me/map-disease-selection",null,null).status);
  var input=new HashMap<>(mapSelection(1,e));input.remove("version");assertEquals(400,call("PUT","/api/v1/me/map-disease-selection",input,a.access).status);
  input=new HashMap<>(mapSelection(1,e));input.put("confirmed",false);assertEquals(400,call("PUT","/api/v1/me/map-disease-selection",input,a.access).status);
  input=new HashMap<>(mapSelection(1,e));input.put("diseaseIds",List.of("D001","D001"));assertEquals(400,call("PUT","/api/v1/me/map-disease-selection",input,a.access).status);
  input.put("diseaseIds",List.of("D999"));assertEquals(400,call("PUT","/api/v1/me/map-disease-selection",input,a.access).status);
  input=new HashMap<>(mapSelection(1,e));input.put("referenceVersion","old");assertEquals(409,call("PUT","/api/v1/me/map-disease-selection",input,a.access).status);
  input=new HashMap<>(mapSelection(1,e));input.put("userId",b.user);assertEquals(400,call("PUT","/api/v1/me/map-disease-selection",input,a.access).status);
  assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",mapSelection(1,e),a.access).status);
  assertEquals("NOT_SELECTED",call("GET","/api/v1/me/map-disease-selection",null,b.access).body.path("mapDiseaseSelection").path("state").asText());
  assertEquals(200,call("DELETE","/api/v1/me/emergency-profile",Map.of("version",2,"consentEpoch",e),a.access).status);
  assertEquals("NOT_SELECTED",call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection").path("state").asText());
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(3,e,"",List.of("D001","D010"),"RECORDED"),a.access).status);assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",mapSelection(4,e),a.access).status);
  call("POST","/api/v1/me/health-consent/withdrawals",Map.of("epoch",e),a.access);
  assertEquals(403,call("GET","/api/v1/me/map-disease-selection",null,a.access).status);assertEquals(0,db.queryForObject("SELECT count(*) FROM member_health_profile WHERE user_id=?",Integer.class,a.user));
  db.update("UPDATE app_user SET role='OPERATOR' WHERE id=?",b.user);assertEquals(403,call("GET","/api/v1/me/map-disease-selection",null,b.access).status);
 }
 @Test void publicReferenceAndBatchNeverReceiveDiseaseOrCallNmc()throws Exception{
  long nmc=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class);
  var r=call("GET","/api/v1/reference/disease-departments",null,null);assertEquals(200,r.status);assertEquals("READY",JSON.readTree(r.body.path("document").asText()).path("status").asText());for(var mapping:JSON.readTree(r.body.path("document").asText()).path("mappings"))assertEquals("APPROVED",mapping.path("reviewStatus").asText());
  var batch=call("POST","/api/v1/emergency-hospitals/departments/query",Map.of("hpids",List.of("synthetic-not-present")),null);assertEquals(200,batch.status);assertEquals("NOT_FOUND",batch.body.path("hospitals").get(0).path("recordStatus").asText());
  assertEquals(400,call("POST","/api/v1/emergency-hospitals/departments/query",Map.of("hpids",List.of("X"),"diseaseIds",List.of("D001")),null).status);
  assertEquals(400,call("POST","/api/v1/emergency-hospitals/departments/query",Map.of("hpids",List.of()),null).status);
  assertEquals(400,call("POST","/api/v1/emergency-hospitals/departments/query",Map.of("hpids",List.of("X","X")),null).status);
  assertEquals(nmc,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class));
 }

 @Test void tagsWithoutMappingsAreIndependentFromTextAndMapConsent()throws Exception{
  var a=signup();long e=grant(a);var input=conditionsInput(0,e,"",List.of("D001","D010"),"RECORDED");
  assertEquals(401,call("PUT","/api/v1/me/conditions",input,null).status);
  assertEquals(200,call("PUT","/api/v1/me/conditions",input,a.access).status);
  var recorded=call("GET","/api/v1/me/health-snapshot",null,a.access).body;
  assertEquals("UNSET",recorded.path("conditions").path("status").asText());assertEquals(2,recorded.path("standardDiseaseSelection").path("diseaseIds").size());
  assertEquals("NOT_SELECTED",recorded.path("mapDiseaseSelection").path("state").asText());
  assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",mapSelection(1,e),a.access).status);
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(2,e,"",List.of("D010"),"RECORDED"),a.access).status);
  var remaining=call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection");
  assertEquals("CONFIRMED",remaining.path("state").asText());assertEquals(List.of("D010"),JSON.convertValue(remaining.path("diseaseIds"),List.class));
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(3,e,"가상 원문",List.of("D010"),"RECORDED"),a.access).status);
  assertEquals("RECONFIRM_REQUIRED",call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection").path("state").asText());
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(4,e,"",List.of("D010"),"RECORDED"),a.access).status);
  assertEquals(1,call("GET","/api/v1/me/conditions",null,a.access).body.path("standardDiseaseSelection").path("diseaseIds").size());
  assertEquals(409,call("PUT","/api/v1/me/conditions",conditionsInput(4,e,"",List.of(),"NONE"),a.access).status);
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(5,e,"",List.of(),"NONE"),a.access).status);
  var none=call("GET","/api/v1/me/conditions",null,a.access).body;assertEquals("NONE",none.path("status").asText());assertEquals(0,none.path("standardDiseaseSelection").path("diseaseIds").size());
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(6,e,"",List.of(),"UNSET"),a.access).status);
  assertEquals("UNSET",call("GET","/api/v1/me/conditions",null,a.access).body.path("status").asText());
 }

 @Test void batchTwoTagsSaveWithoutMappingAndNeverAutomaticallyJoinMapUse()throws Exception{
  var a=signup();long epoch=grant(a);long nmc=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class);
  var r=call("GET","/api/v1/reference/disease-departments",null,null);assertEquals(200,r.status);
  var data=JSON.readTree(r.body.path("document").asText());assertEquals(46,data.path("diseases").size());assertEquals(0,data.path("mappings").size());
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(0,epoch,"가상 자유입력",List.of("D017"),"RECORDED"),a.access).status);
  var recorded=call("GET","/api/v1/me/health-snapshot",null,a.access).body;
  assertEquals("D017",recorded.path("standardDiseaseSelection").path("diseaseIds").get(0).asText());assertEquals("NOT_SELECTED",recorded.path("mapDiseaseSelection").path("state").asText());
  var use=new HashMap<>(mapSelection(1,epoch));use.put("diseaseIds",List.of("D017"));assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",use,a.access).status);
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(2,epoch,"가상 자유입력",List.of("D017","D025","D046"),"RECORDED"),a.access).status);
  var selection=call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection");assertEquals("CONFIRMED",selection.path("state").asText());assertEquals(JSON.valueToTree(List.of("D017")),selection.path("diseaseIds"));
  var other=signup();grant(other);assertTrue(call("GET","/api/v1/me/conditions",null,other.access).body.path("standardDiseaseSelection").path("diseaseIds").isEmpty());
  assertEquals(nmc,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class));
 }

 @Test void evidenceStagingTagsAndMapUseSaveIndependentlyDespiteDraftMappings()throws Exception{
  var a=signup();long epoch=grant(a);long nmc=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class);
  var response=call("GET","/api/v1/reference/disease-departments",null,null);assertEquals(200,response.status);
  var reference=JSON.readTree(response.body.path("document").asText());assertEquals(runtimeReference.version(),reference.path("datasetVersion").asText());assertTrue(reference.path("mappings").isEmpty());
  assertEquals(runtimeReference.response().sha256(),response.body.path("sha256").asText());
  var tags=List.of("D001","D003","D010","D017");
  assertEquals(200,call("PUT","/api/v1/me/conditions",conditionsInput(0,epoch,"합성 자유입력 보존",tags,"RECORDED"),a.access).status);
  var saved=call("GET","/api/v1/me/health-snapshot",null,a.access).body;
  assertEquals(JSON.valueToTree(tags),saved.path("standardDiseaseSelection").path("diseaseIds"));assertEquals("NOT_SELECTED",saved.path("mapDiseaseSelection").path("state").asText());
  var use=new HashMap<>(mapSelection(1,epoch));use.put("diseaseIds",tags);
  assertEquals(200,call("PUT","/api/v1/me/map-disease-selection",use,a.access).status);
  var selection=call("GET","/api/v1/me/map-disease-selection",null,a.access).body.path("mapDiseaseSelection");
  assertEquals("CONFIRMED",selection.path("state").asText());assertEquals(JSON.valueToTree(tags),selection.path("diseaseIds"));
  assertEquals(nmc,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Long.class));
 }

}
