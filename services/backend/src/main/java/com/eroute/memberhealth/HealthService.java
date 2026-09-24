package com.eroute.memberhealth;

import static com.eroute.auth.AuthData.*;
import com.eroute.auth.*;
import com.eroute.personalization.DiseaseReference;
import com.eroute.personalization.DiseaseCatalog;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class HealthService {
 private final DiseaseCatalog catalog;private final DiseaseReference reference;private final JdbcTemplate db;private final SecretBox box;private final AuthService auth;private final Clock clock;private final TransactionTemplate tx;
 public HealthService(JdbcTemplate db,SecretBox box,AuthService auth,Clock clock,PlatformTransactionManager tm,DiseaseReference reference,DiseaseCatalog catalog){this.catalog=catalog;this.reference=reference;this.db=db;this.box=box;this.auth=auth;this.clock=clock;tx=new TransactionTemplate(tm);}
 private void member(Principal p){if(!p.role().equals("MEMBER"))throw problem("MEMBER_REQUIRED",403);}
 private Map<String,Object> lock(Principal p){member(p);return db.queryForMap("SELECT * FROM health_consent WHERE user_id=? FOR UPDATE",p.userId());}
 private Map<String,Object> allowed(Principal p,Long epoch){var c=lock(p);if(!string(c,"state").equals("GRANTED"))throw problem("HEALTH_CONSENT_REQUIRED",403);if(epoch!=null&&number(c,"epoch")!=epoch)throw problem("CONSENT_GENERATION_CHANGED",409);return c;}
 public Map<String,Object> consentState(Principal p){return tx.execute(s->summary(lock(p)));}
 private Map<String,Object> summary(Map<String,Object> c){return Map.of("state",string(c,"state"),"epoch",number(c,"epoch"),"documentVersion",AuthService.HEALTH_TERMS);}
 public Map<String,Object> grant(Principal p,String version,long expectedEpoch){return tx.execute(s->{var c=lock(p);if(number(c,"epoch")!=expectedEpoch)throw problem("CONSENT_GENERATION_CHANGED",409);if(string(c,"state").equals("REVOKING"))throw problem("ERASURE_IN_PROGRESS",409);if(!AuthService.HEALTH_TERMS.equals(version))throw problem("CONSENT_VERSION_REQUIRED",400);if(!string(c,"state").equals("GRANTED")){db.update("UPDATE health_consent SET state='GRANTED',epoch=epoch+1,document_version=?,updated_at=? WHERE user_id=?",version,ts(clock.instant()),p.userId());auth.consent(p.userId(),"HEALTH",version,"GRANTED",p.source());}return summary(lock(p));});}
 public Map<String,Object> snapshot(Principal p){return tx.execute(s->{var c=allowed(p,null);long epoch=number(c,"epoch");var result=new LinkedHashMap<String,Object>(readProfile(p.userId(),epoch));result.put("medications",db.queryForList("SELECT * FROM member_medication WHERE user_id=? ORDER BY updated_at,id",p.userId()).stream().map(r->medication(r,epoch)).toList());return result;});}
 private long requiredVersion(Map<String,Object> input,String key){if(!input.containsKey(key)||input.get(key)==null)throw problem("PRECONDITION_REQUIRED",400);return integer(input,key);}
 private void profileVersion(Principal p,long epoch,long expected){if(((Number)readProfile(p.userId(),epoch).get("version")).longValue()!=expected)throw problem("DATA_VERSION_CONFLICT",409);}
 public Map<String,Object> profile(Principal p){return tx.execute(s->{var c=allowed(p,null);return readProfile(p.userId(),number(c,"epoch"));});}
 @SuppressWarnings("unchecked")
 private Map<String,Object> readProfile(UUID user,long epoch){var rows=db.queryForList("SELECT * FROM member_health_profile WHERE user_id=?",user);if(rows.isEmpty()){var result=empty();result.put("version",0L);result.put("consentEpoch",epoch);result.put("updatedAt",null);return result;}var r=rows.getFirst();if(number(r,"consent_epoch")!=epoch)throw problem("CONSENT_GENERATION_CHANGED",409);var result=new LinkedHashMap<String,Object>(box.parse(box.decrypt("health","profile:"+user+":"+epoch,string(r,"body_cipher")),Map.class));result.putIfAbsent("standardDiseaseSelection",noStandardSelection());result.put("mapDiseaseSelection",effectiveSelection(result.get("mapDiseaseSelection")));result.put("version",number(r,"version"));result.put("consentEpoch",epoch);result.put("updatedAt",instant(r,"updated_at").toString());return result;}
 private LinkedHashMap<String,Object> empty(){var r=new LinkedHashMap<String,Object>();r.put("allergies",Map.of("status","UNSET","text",""));r.put("conditions",Map.of("status","UNSET","text",""));r.put("note","");r.put("medicationsStatus","UNSET");r.put("source","USER_ENTERED");r.put("mapDiseaseSelection",noSelection());r.put("standardDiseaseSelection",noStandardSelection());return r;}
 public Map<String,Object> saveProfile(Principal p,Map<String,Object> input,boolean clear){return tx.execute(s->{long epoch=integer(input,"consentEpoch"),version=integer(input,"version");allowed(p,epoch);var old=readProfile(p.userId(),epoch);if(((Number)old.get("version")).longValue()!=version)throw problem("DATA_VERSION_CONFLICT",409);
  Map<String,Object> body;
  if(clear){body=empty();body.put("medicationsStatus",old.get("medicationsStatus"));ledger(p.userId(),epoch,p.userId());}
  else {only(input,Set.of("consentEpoch","version","allergies","conditions","note","medicationsStatus"));body=empty();body.put("allergies",field(input.get("allergies")));body.put("conditions",field(input.get("conditions")));body.put("note",text(input.get("note"),2000,false));String status=text(input.get("medicationsStatus"),20,true);if(!Set.of("UNSET","NONE","RECORDED").contains(status))throw problem("INVALID_HEALTH_INPUT",400);long count=db.queryForObject("SELECT count(*) FROM member_medication WHERE user_id=?",Long.class,p.userId());if((count>0)!=status.equals("RECORDED"))throw problem("MEDICATION_STATUS_CONFLICT",409);body.put("medicationsStatus",status);
   if(old.containsKey("conditionEntries")){
    var supplied=(Map<?,?>)body.get("conditions");var previous=(Map<?,?>)old.get("conditions");
    if(Objects.equals(supplied.get("status"),previous.get("status"))&&Objects.equals(supplied.get("text"),((String)previous.get("text")).strip()))body.put("conditions",previous);
   }
   var conditions=(Map<?,?>)body.get("conditions");var selection=effectiveSelection(old.get("mapDiseaseSelection"));
   if(old.containsKey("conditionEntries")){
    if(!conditions.equals(old.get("conditions"))&&!"NONE".equals(conditions.get("status")))throw problem("STRUCTURED_CONDITIONS_REQUIRED",409);
    body.put("conditionEntries","NONE".equals(conditions.get("status"))?List.of():old.get("conditionEntries"));
    body.put("conditionSchemaVersion",1);if(!"NONE".equals(conditions.get("status"))&&old.containsKey("legacyConditionText"))body.put("legacyConditionText",old.get("legacyConditionText"));
   }
   body.put("standardDiseaseSelection",old.getOrDefault("standardDiseaseSelection",noStandardSelection()));
   if("NONE".equals(conditions.get("status"))){selection=noSelection();body.put("standardDiseaseSelection",noStandardSelection());}
   else if(!conditions.equals(old.get("conditions"))&&!"NOT_SELECTED".equals(selection.get("state"))){selection=new LinkedHashMap<>(selection);selection.put("state","RECONFIRM_REQUIRED");}
   body.put("mapDiseaseSelection",selection);
  }
  writeProfile(p.userId(),epoch,version+1,body);return readProfile(p.userId(),epoch);
 });}


 private Map<String,Object> noStandardSelection(){return Map.of("diseaseIds",List.of());}
 private List<?> standardIds(Map<String,Object> profile){var value=profile.get("standardDiseaseSelection");return value instanceof Map<?,?> m&&m.get("diseaseIds") instanceof List<?> ids?ids:List.of();}
 private Map<String,Object> conditionView(Map<String,Object> profile){
  var raw=(Map<?,?>)profile.get("conditions");var out=new LinkedHashMap<String,Object>();
  out.put("version",profile.get("version"));out.put("consentEpoch",profile.get("consentEpoch"));
  out.put("status",!standardIds(profile).isEmpty()?"RECORDED":raw.get("status"));out.put("freeText",raw.get("text"));
  out.put("standardDiseaseSelection",profile.getOrDefault("standardDiseaseSelection",noStandardSelection()));
  out.put("mapDiseaseSelection",profile.get("mapDiseaseSelection"));if(profile.containsKey("conditionEntries"))out.put("conditionEntries",profile.get("conditionEntries"));out.put("catalogVersion",catalog.version());return out;
 }
 public Map<String,Object> conditions(Principal p){return tx.execute(s->{var c=allowed(p,null);return conditionView(readProfile(p.userId(),number(c,"epoch")));});}
 public Map<String,Object> saveConditions(Principal p,Map<String,Object> input){return tx.execute(s->{
  only(input,Set.of("version","consentEpoch","status","freeText","diseaseIds","catalogVersion","conditionEntries"));
  long epoch=requiredVersion(input,"consentEpoch"),version=requiredVersion(input,"version");allowed(p,epoch);
  var old=readProfile(p.userId(),epoch);if(((Number)old.get("version")).longValue()!=version)throw problem("DATA_VERSION_CONFLICT",409);
  boolean structured=input.containsKey("conditionEntries");
  String status=text(input.get("status"),20,true),raw;
  List<Map<String,Object>> entries;List<?> ids;
  if(structured){
   if(input.containsKey("freeText")||input.containsKey("diseaseIds"))throw problem("INVALID_HEALTH_INPUT",400);
   if(!catalog.version().equals(input.get("catalogVersion")))throw problem("REFERENCE_VERSION_CONFLICT",409);
   entries=ConditionEntries.validate(input.get("conditionEntries"),catalog,standardIds(old));ids=ConditionEntries.ids(entries);raw=ConditionEntries.freeText(entries);
  }else{
   raw=text(input.get("freeText"),2000,false);
   if(!(input.get("diseaseIds") instanceof List<?> legacy)||legacy.size()>100||new HashSet<>(legacy).size()!=legacy.size())throw problem("INVALID_DISEASE_SELECTION",400);
   ids=legacy;
   if(old.containsKey("conditionEntries")&&!status.equals("NONE")&&!status.equals("UNSET"))throw problem("STRUCTURED_CONDITIONS_REQUIRED",409);
   if(!ids.isEmpty()&&!reference.catalogVersion().equals(input.get("catalogVersion")))throw problem("REFERENCE_VERSION_CONFLICT",409);
   for(Object id:ids)if(!(id instanceof String name)||!catalog.known(name)||(!catalog.active(name)&&!standardIds(old).contains(name)))throw problem("INVALID_DISEASE_SELECTION",400);
   entries=null;
  }
  if(!Set.of("RECORDED","NONE","UNSET").contains(status)||status.equals("RECORDED")==(ids.isEmpty()&&raw.isBlank()))throw problem("INVALID_HEALTH_INPUT",400);
  var body=new LinkedHashMap<>(old);body.remove("version");body.remove("consentEpoch");body.remove("updatedAt");
  var rawField=Map.of("status",raw.isBlank()?(status.equals("NONE")?"NONE":"UNSET"):"RECORDED","text",raw);
  body.put("conditions",rawField);
  if(structured){body.put("conditionEntries",entries);body.put("conditionSchemaVersion",1);if(status.equals("RECORDED"))body.putIfAbsent("legacyConditionText",((Map<?,?>)old.get("conditions")).get("text"));else body.remove("legacyConditionText");}
  else if(old.containsKey("conditionEntries"))body.put("conditionEntries",List.of());
  body.put("standardDiseaseSelection",ids.isEmpty()?noStandardSelection():Map.of("diseaseIds",List.copyOf(ids),"catalogVersion",structured?catalog.version():reference.catalogVersion(),"confirmedAt",clock.instant().toString()));
  var selection=effectiveSelection(old.get("mapDiseaseSelection"));
  if(!"NOT_SELECTED".equals(selection.get("state"))){
   var remaining=((List<?>)selection.get("diseaseIds")).stream().filter(ids::contains).toList();
   if(remaining.isEmpty()||!status.equals("RECORDED"))selection=noSelection();
   else{selection=new LinkedHashMap<>(selection);selection.put("diseaseIds",remaining);if(!rawField.equals(old.get("conditions")))selection.put("state","RECONFIRM_REQUIRED");}
  }
  body.put("mapDiseaseSelection",selection);writeProfile(p.userId(),epoch,version+1,body);return conditionView(readProfile(p.userId(),epoch));
 });}

 private Map<String,Object> noSelection(){return Map.of("state","NOT_SELECTED","diseaseIds",List.of());}
 @SuppressWarnings("unchecked")
 private Map<String,Object> effectiveSelection(Object value){
  if(!(value instanceof Map<?,?> m))return noSelection();
  var result=new LinkedHashMap<String,Object>((Map<String,Object>)m);
  if("CONFIRMED".equals(result.get("state"))&&(!reference.availableNow()||!reference.version().equals(result.get("referenceVersion"))||!reference.purposeVersion().equals(result.get("purposeVersion"))))result.put("state","RECONFIRM_REQUIRED");
  return result;
 }
 private Map<String,Object> selectionView(Map<String,Object> profile){return Map.of("version",profile.get("version"),"consentEpoch",profile.get("consentEpoch"),"mapDiseaseSelection",profile.get("mapDiseaseSelection"));}
 public Map<String,Object> mapSelection(Principal p){return tx.execute(s->{var c=allowed(p,null);return selectionView(readProfile(p.userId(),number(c,"epoch")));});}
 public Map<String,Object> saveMapSelection(Principal p,Map<String,Object> input,boolean clear){return tx.execute(s->{
  only(input,clear?Set.of("version","consentEpoch"):Set.of("version","consentEpoch","diseaseIds","purpose","purposeVersion","referenceVersion","confirmed"));
  long epoch=requiredVersion(input,"consentEpoch"),version=requiredVersion(input,"version");allowed(p,epoch);
  var old=readProfile(p.userId(),epoch);if(((Number)old.get("version")).longValue()!=version)throw problem("DATA_VERSION_CONFLICT",409);
  Map<String,Object> selection=noSelection();
  if(!clear){
   
   if(!reference.version().equals(input.get("referenceVersion"))||!reference.purposeVersion().equals(input.get("purposeVersion")))throw problem("REFERENCE_VERSION_CONFLICT",409);
   if(!reference.purpose().equals(input.get("purpose"))||!Boolean.TRUE.equals(input.get("confirmed")))throw problem("MAP_USE_CONFIRMATION_REQUIRED",400);
   if(!(input.get("diseaseIds") instanceof List<?> ids)||ids.isEmpty()||ids.size()>100||new HashSet<>(ids).size()!=ids.size())throw problem("INVALID_DISEASE_SELECTION",400);
   for(Object id:ids)if(!(id instanceof String name)||!catalog.active(name)||!standardIds(old).contains(name))throw problem("INVALID_DISEASE_SELECTION",400);
   selection=Map.of("state","CONFIRMED","diseaseIds",List.copyOf(ids),"purpose",reference.purpose(),"purposeVersion",reference.purposeVersion(),"referenceVersion",reference.version(),"confirmedAt",clock.instant().toString());
  }
  var body=new LinkedHashMap<>(old);body.remove("version");body.remove("consentEpoch");body.remove("updatedAt");body.put("mapDiseaseSelection",selection);
  writeProfile(p.userId(),epoch,version+1,body);return selectionView(readProfile(p.userId(),epoch));
 });}
 private void writeProfile(UUID user,long epoch,long version,Map<String,Object> body){db.update("INSERT INTO member_health_profile VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET consent_epoch=excluded.consent_epoch,version=excluded.version,body_cipher=excluded.body_cipher,updated_at=excluded.updated_at",user,epoch,version,box.encrypt("health","profile:"+user+":"+epoch,box.json(body)),ts(clock.instant()));}
 private void medicationStatus(UUID user,long epoch,String status){var p=readProfile(user,epoch);long version=((Number)p.remove("version")).longValue();p.remove("consentEpoch");p.remove("updatedAt");p.put("medicationsStatus",status);writeProfile(user,epoch,version+1,p);}
 private Map<String,Object> field(Object value){if(!(value instanceof Map<?,?> m)||!Set.of("status","text").containsAll(m.keySet()))throw problem("INVALID_HEALTH_INPUT",400);String status=text(m.get("status"),20,true),content=text(m.get("text"),2000,false);if(!Set.of("UNSET","NONE","RECORDED").contains(status)||status.equals("RECORDED")==content.isBlank())throw problem("INVALID_HEALTH_INPUT",400);return Map.of("status",status,"text",content);}
 public List<Map<String,Object>> medications(Principal p){return tx.execute(s->{var c=allowed(p,null);return db.queryForList("SELECT * FROM member_medication WHERE user_id=? ORDER BY updated_at,id",p.userId()).stream().map(r->medication(r,number(c,"epoch"))).toList();});}
 public Map<String,Object> medication(Principal p,UUID id){return tx.execute(s->{var c=allowed(p,null);return medication(owned(p,id),number(c,"epoch"));});}
 private Map<String,Object> owned(Principal p,UUID id){var rows=db.queryForList("SELECT * FROM member_medication WHERE id=? AND user_id=?",id,p.userId());if(rows.isEmpty())throw problem("MEDICATION_NOT_FOUND",404);return rows.getFirst();}
 @SuppressWarnings("unchecked") private Map<String,Object> medication(Map<String,Object> r,long epoch){if(number(r,"consent_epoch")!=epoch)throw problem("CONSENT_GENERATION_CHANGED",409);var result=new LinkedHashMap<String,Object>(box.parse(box.decrypt("health","medication:"+uuid(r,"user_id")+":"+uuid(r,"id")+":"+epoch,string(r,"body_cipher")),Map.class));result.put("id",uuid(r,"id"));result.put("version",number(r,"version"));result.put("consentEpoch",epoch);result.put("updatedAt",instant(r,"updated_at").toString());result.put("source","MANUAL");result.put("productCode",null);return result;}
 public Map<String,Object> saveMedication(Principal p,UUID id,Map<String,Object> input){return tx.execute(s->{only(input,Set.of("consentEpoch","baseVersion","version","name","note"));long epoch=requiredVersion(input,"consentEpoch"),baseVersion=requiredVersion(input,"baseVersion");allowed(p,epoch);long version=0;UUID target=id;
  if(target==null){if(db.queryForObject("SELECT count(*) FROM member_medication WHERE user_id=?",Long.class,p.userId())>=100)throw problem("MEDICATION_LIMIT",400);target=UUID.randomUUID();}
  else{var old=owned(p,target);medication(old,epoch);version=number(old,"version");if(version!=requiredVersion(input,"version"))throw problem("DATA_VERSION_CONFLICT",409);}
  profileVersion(p,epoch,baseVersion);
  var body=Map.of("name",text(input.get("name"),200,true),"note",text(input.get("note"),2000,false));String encrypted=box.encrypt("health","medication:"+p.userId()+":"+target+":"+epoch,box.json(body));
  if(id==null)db.update("INSERT INTO member_medication VALUES(?,?,?,?,?,?)",target,p.userId(),epoch,1,encrypted,ts(clock.instant()));else db.update("UPDATE member_medication SET version=version+1,body_cipher=?,updated_at=? WHERE id=? AND user_id=?",encrypted,ts(clock.instant()),target,p.userId());
  medicationStatus(p.userId(),epoch,"RECORDED");return medication(owned(p,target),epoch);
 });}
 public void deleteMedication(Principal p,UUID id,Map<String,Object> input){long epoch=requiredVersion(input,"consentEpoch"),version=requiredVersion(input,"version"),baseVersion=requiredVersion(input,"baseVersion");tx.executeWithoutResult(s->{allowed(p,epoch);var old=owned(p,id);profileVersion(p,epoch,baseVersion);if(number(old,"version")!=version)throw problem("DATA_VERSION_CONFLICT",409);db.update("DELETE FROM member_medication WHERE id=? AND user_id=?",id,p.userId());ledger(p.userId(),epoch,id);long count=db.queryForObject("SELECT count(*) FROM member_medication WHERE user_id=?",Long.class,p.userId());medicationStatus(p.userId(),epoch,count==0?"UNSET":"RECORDED");});}
 public Map<String,Object> withdraw(Principal p,long epoch,String key){AuthService.requestKey(key);UUID job=tx.execute(s->{var c=lock(p);var previous=db.queryForList("SELECT id FROM health_erasure WHERE user_id=? AND request_key=?",UUID.class,p.userId(),key);if(!previous.isEmpty())return previous.getFirst();if(number(c,"epoch")!=epoch)throw problem("CONSENT_GENERATION_CHANGED",409);if(!string(c,"state").equals("GRANTED")){var jobs=db.queryForList("SELECT id FROM health_erasure WHERE user_id=? ORDER BY created_at DESC LIMIT 1",UUID.class,p.userId());if(!jobs.isEmpty())return jobs.getFirst();throw problem("HEALTH_CONSENT_REQUIRED",403);}
  UUID id=UUID.randomUUID();Instant now=clock.instant();db.update("UPDATE health_consent SET state='REVOKING',epoch=epoch+1,updated_at=? WHERE user_id=?",ts(now),p.userId());auth.consent(p.userId(),"HEALTH",AuthService.HEALTH_TERMS,"WITHDRAWN",p.source());db.update("INSERT INTO health_erasure(id,user_id,request_key,erased_epoch,state,created_at,backup_due_at) VALUES(?,?,?,?,?,?,?)",id,p.userId(),key,epoch,"PENDING",ts(now),ts(now.plus(Duration.ofDays(30))));return id;
 });process(job);return erasure(p,job);}
 public Map<String,Object> erasure(Principal p,UUID id){member(p);var rows=db.queryForList("SELECT id,state,attempts,created_at,completed_at,backup_due_at,backup_completed_at FROM health_erasure WHERE id=? AND user_id=?",id,p.userId());if(rows.isEmpty())throw problem("ERASURE_NOT_FOUND",404);var r=rows.getFirst();var out=new LinkedHashMap<String,Object>();out.put("id",id);out.put("state",string(r,"state"));out.put("attempts",number(r,"attempts"));out.put("completedAt",instant(r,"completed_at"));out.put("backupDueAt",instant(r,"backup_due_at"));out.put("backupComplete",r.get("backup_completed_at")!=null);return out;}
 public List<Map<String,Object>> erasures(Principal p){member(p);return db.queryForList("SELECT id FROM health_erasure WHERE user_id=? ORDER BY created_at DESC LIMIT 20",UUID.class,p.userId()).stream().map(id->erasure(p,id)).toList();}
 public Map<String,Object> retry(Principal p,UUID id){erasure(p,id);process(id);return erasure(p,id);}
 private void process(UUID id){try{tx.executeWithoutResult(s->{var initial=db.queryForMap("SELECT user_id FROM health_erasure WHERE id=?",id);UUID user=uuid(initial,"user_id");db.queryForMap("SELECT user_id FROM health_consent WHERE user_id=? FOR UPDATE",user);var job=db.queryForMap("SELECT * FROM health_erasure WHERE id=? FOR UPDATE",id);if(string(job,"state").equals("COMPLETE"))return;long epoch=number(job,"erased_epoch");db.update("DELETE FROM member_medication WHERE user_id=? AND consent_epoch<=?",user,epoch);db.update("DELETE FROM member_health_profile WHERE user_id=? AND consent_epoch<=?",user,epoch);ledger(user,epoch,null);db.update("UPDATE health_erasure SET state='COMPLETE',attempts=attempts+1,completed_at=? WHERE id=?",ts(clock.instant()),id);db.update("UPDATE health_consent SET state='REVOKED',updated_at=? WHERE user_id=? AND state='REVOKING' AND epoch=?",ts(clock.instant()),user,epoch+1);});}
  catch(RuntimeException e){db.update("UPDATE health_erasure SET state='FAILED',attempts=attempts+1 WHERE id=? AND state<>'COMPLETE'",id);}
 }
 private void ledger(UUID user,long epoch,UUID resource){db.update("INSERT INTO health_deletion_ledger VALUES(?,?,?,?,?,?)",UUID.randomUUID(),user,epoch,resource,ts(clock.instant()),ts(clock.instant().plus(Duration.ofDays(37))));}
 @Scheduled(initialDelayString="PT15S",fixedDelayString="PT15S") public void retryPending(){for(UUID id:db.queryForList("SELECT id FROM health_erasure WHERE state<>'COMPLETE' AND attempts<5 ORDER BY created_at LIMIT 20",UUID.class))process(id);}
 public static long integer(Map<String,Object> map,String key){Object value=map.get(key);if(!(value instanceof Number n)||n.longValue()<0||n.doubleValue()!=n.longValue())throw problem("INVALID_HEALTH_INPUT",400);return n.longValue();}
 public static String text(Object value,int max,boolean required){if(value==null&&!required)return "";if(!(value instanceof String s)||s.length()>max||required&&s.isBlank())throw problem("INVALID_HEALTH_INPUT",400);return s.strip();}
 public static void only(Map<String,Object> map,Set<String> keys){if(!keys.containsAll(map.keySet()))throw problem("INVALID_HEALTH_INPUT",400);}
}
