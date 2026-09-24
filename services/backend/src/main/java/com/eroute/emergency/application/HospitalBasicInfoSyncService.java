package com.eroute.emergency.application;

import com.eroute.common.config.*;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.BasicModels.*;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.port.HospitalBasicInfoProvider;
import com.eroute.emergency.infrastructure.nmc.*;
import com.eroute.emergency.infrastructure.persistence.*;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class HospitalBasicInfoSyncService {
 private static final String ENDPOINT=NmcBasicInfoDiscoveryProbe.ENDPOINT;
 private final JdbcTemplate db;private final HospitalBasicInfoProvider provider;private final NmcXmlParser parser;private final NmcBasicInfoNormalizer normalizer;private final JdbcHospitalBasicInfoStore store;private final NmcBasicInfoDiscoveryProbe discovery;private final JsonCodec json;private final ERouteProperties config;private final BasicInfoProperties basic;private final TransactionTemplate tx;
 public HospitalBasicInfoSyncService(JdbcTemplate db,HospitalBasicInfoProvider provider,NmcXmlParser parser,NmcBasicInfoNormalizer normalizer,JdbcHospitalBasicInfoStore store,NmcBasicInfoDiscoveryProbe discovery,JsonCodec json,ERouteProperties config,BasicInfoProperties basic,PlatformTransactionManager tm){this.db=db;this.provider=provider;this.parser=parser;this.normalizer=normalizer;this.store=store;this.discovery=discovery;this.json=json;this.config=config;this.basic=basic;tx=new TransactionTemplate(tm);}
 private List<String> targets(){return db.queryForList("SELECT hpid FROM hospital WHERE active ORDER BY hpid",String.class);}
 public UUID synchronize(UUID resume){
  UUID owner=UUID.randomUUID();UUID run=tx.execute(s->{
   db.queryForList("SELECT pg_advisory_xact_lock(hashtext('eroute:basic:start'))");
   var unfinished=db.queryForList("SELECT * FROM provider_sync_run WHERE endpoint=? AND status IN ('RUNNING','FAILED','BUDGET_DEFERRED')",ENDPOINT);
   UUID id;
   if(!unfinished.isEmpty()){
    var r=unfinished.getFirst();id=(UUID)r.get("id");
    if(resume!=null&&!resume.equals(id))throw new ServiceProblem("BASIC_RUN_MISMATCH");
    if(r.get("lease_until")!=null&&((Timestamp)r.get("lease_until")).toInstant().isAfter(Instant.now()))throw new ServiceProblem("BASIC_SYNC_IN_PROGRESS");
    var details=json.read(r.get("details").toString(),com.fasterxml.jackson.databind.JsonNode.class);
    if(!discovery.sourceHash().equals(details.path("sourceHash").asText()))throw new ServiceProblem("DISCOVERY_SOURCE_CHANGED");
    if(!NmcBasicInfoNormalizer.VERSION.equals(details.path("normalizerVersion").asText(NmcBasicInfoNormalizer.VERSION)))throw new ServiceProblem("BASIC_NORMALIZER_CHANGED");
    if(details.path("restartRequired").asBoolean())throw new ServiceProblem("BASIC_REDISCOVERY_REQUIRED");
   }else{
    if(resume!=null)throw new ServiceProblem("BASIC_RUN_NOT_RESUMABLE");
    var gates=db.queryForList("SELECT * FROM discovery_result WHERE endpoint=? AND passed AND pdf_sha256=? ORDER BY id DESC LIMIT 1",ENDPOINT,discovery.sourceHash());
    if(gates.isEmpty())throw new ServiceProblem("BASIC_DISCOVERY_GATE_NOT_PASSED");var gate=gates.getFirst();
    var report=json.read(gate.get("report").toString(),com.fasterxml.jackson.databind.JsonNode.class);
    if(!NmcBasicInfoDiscoveryProbe.VERSION.equals(report.path("probeVersion").asText()))throw new ServiceProblem("BASIC_DISCOVERY_VERSION_CHANGED");
    String mode=gate.get("mode").toString();if(!Set.of("NATIONWIDE","PER_HPID").contains(mode))throw new ServiceProblem("UNKNOWN_COLLECTION_PLAN");
    var targets=targets();if(targets.isEmpty())throw new ServiceProblem("BASIC_MASTER_EMPTY");
    id=UUID.randomUUID();int size=((Number)gate.get("page_size")).intValue();
    var details=new LinkedHashMap<String,Object>();details.put("targets",targets);details.put("discoveryId",gate.get("id"));details.put("sourceHash",discovery.sourceHash());details.put("pageSize",size);details.put("normalizerVersion",NmcBasicInfoNormalizer.VERSION);details.put("catalogVersion",db.queryForObject("SELECT version::text FROM catalog_state",String.class));
    db.update("INSERT INTO provider_sync_run(id,endpoint,mode,status,started_at,details) VALUES(?,?,?,'RUNNING',clock_timestamp(),?::jsonb)",id,ENDPOINT,mode,json.write(details));
    if(mode.equals("PER_HPID"))for(String hpid:targets)addWork(id,"HPID:"+hpid,"HPID",hpid,1,size);else addWork(id,"PAGE:1","PAGE",null,1,size);
   }
   db.update("UPDATE provider_sync_run SET status='RUNNING',completed_at=NULL,lease_owner=?,lease_until=clock_timestamp()+interval '2 minutes',next_attempt_at=NULL,details=details-'error' WHERE id=?",owner,id);
   return id;
  });
  try{
   var r=db.queryForMap("SELECT mode,details::text FROM provider_sync_run WHERE id=?",run);String mode=r.get("mode").toString();
   // Pages from separate windows are not assumed to belong to a provider snapshot.
   if(mode.equals("NATIONWIDE"))revalidateBulk(run,owner);
   expireStaging(run,owner);
   while(true){
    heartbeat(run,owner);
    var work=db.queryForList("SELECT * FROM provider_sync_work WHERE run_id=? AND status<>'SUCCESS' ORDER BY page_no,unit_key LIMIT 1",run);
    if(work.isEmpty()){
     if(reconcileTargets(run,owner,mode))continue;
     publish(run,owner);return run;
    }
    var w=work.getFirst();String unit=w.get("unit_key").toString(),scope="BASIC:"+run+":"+unit;var started=Instant.now();
    try{
     var fetched=provider.fetchPage(scope,(String)w.get("hpid"),((Number)w.get("page_no")).intValue(),((Number)w.get("num_of_rows")).intValue());
     var p=fetched.page();var raws=parser.basicItems(p.rawXml());
     if(w.get("kind").equals("HPID")){
      if(p.pageNo()!=1||p.totalCount()!=p.items().size()||p.totalCount()>1)throw new ServiceProblem("BASIC_HPID_MISMATCH");
      if(!p.items().isEmpty())NmcBasicInfoDiscoveryProbe.verifySingle(p,(String)w.get("hpid"));
     }else validateBulk(run,owner,w,p);
     tx.executeWithoutResult(s->{
      requireLease(run,owner);
      if(p.items().isEmpty()&&w.get("kind").equals("HPID"))store.absence(run,(String)w.get("hpid"),fetched.responseId(),p.fetchedAt());
      for(int i=0;i<p.items().size();i++){
       String hpid=NmcBasicInfoDiscoveryProbe.hpid(p.items().get(i));
       if(Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM hospital_basic_info_snapshot WHERE sync_run_id=? AND hpid=?)",Boolean.class,run,hpid)))throw new ServiceProblem("BASIC_DUPLICATE_HPID");
       store.stage(run,hpid,fetched.responseId(),p.fetchedAt(),raws.get(i),normalizer.normalize(raws.get(i)),discovery.sourceHash());
      }
      db.update("UPDATE provider_sync_work SET status='SUCCESS',response_id=?,error=NULL WHERE run_id=? AND unit_key=?",fetched.responseId(),run,unit);recordAttempts(run,unit,scope);
     });
    }catch(RuntimeException e){recordAttempts(run,unit,scope);db.update("UPDATE provider_sync_work SET status='FAILED',error=? WHERE run_id=? AND unit_key=? AND EXISTS(SELECT 1 FROM provider_sync_run WHERE id=? AND lease_owner=?)",code(e),run,unit,run,owner);throw e;}
    pause();
   }
  }catch(RuntimeException e){
   String code=code(e);boolean deferred=Set.of("CALL_BUDGET_LIMIT","CALL_RATE_LIMIT").contains(code);boolean restart=Set.of("BASIC_BULK_INVALID","BASIC_DUPLICATE_HPID","BASIC_MISSING_HPID","BASIC_UNSTABLE_PAGINATION").contains(code);
   Instant next=deferred?nextBudget(code):Set.of("NMC_TRANSPORT_ERROR","NMC_TRANSIENT_HTTP").contains(code)?Instant.now().plus(Duration.ofDays(1)):null;
   db.update("UPDATE provider_sync_run SET status=?,details=details||?::jsonb,next_attempt_at=?,lease_owner=NULL,lease_until=NULL WHERE id=? AND lease_owner=?",deferred?"BUDGET_DEFERRED":restart?"SUPERSEDED":"FAILED",json.write(Map.of("error",code,"restartRequired",restart)),next==null?null:Timestamp.from(next),run,owner);
   throw new ServiceProblem(code);
  }finally{db.update("UPDATE provider_sync_run SET lease_owner=NULL,lease_until=NULL WHERE id=? AND lease_owner=?",run,owner);}
 }
 private void addWork(UUID run,String unit,String kind,String hpid,int page,int size){db.update("INSERT INTO provider_sync_work(run_id,unit_key,kind,hpid,page_no,num_of_rows) VALUES(?,?,?,?,?,?) ON CONFLICT DO NOTHING",run,unit,kind,hpid,page,size);}
 private void recordAttempts(UUID run,String unit,String scope){db.update("UPDATE provider_sync_work SET attempts=(SELECT count(*) FROM nmc_call_attempt WHERE scope=?),last_attempt_at=COALESCE((SELECT max(requested_at) FROM nmc_call_attempt WHERE scope=?),last_attempt_at) WHERE run_id=? AND unit_key=?",scope,scope,run,unit);}
 private void validateBulk(UUID run,UUID owner,Map<String,Object> work,Page page){
  int number=((Number)work.get("page_no")).intValue();var d=json.read(db.queryForObject("SELECT details::text FROM provider_sync_run WHERE id=?",String.class,run),com.fasterxml.jackson.databind.JsonNode.class);
  int total=d.path("totalCount").asInt(-1),size=((Number)work.get("num_of_rows")).intValue();
  if(total<0){if(page.totalCount()==0)throw new ServiceProblem("BASIC_BULK_INVALID");total=page.totalCount();size=page.numOfRows();final int t=total,z=size;tx.executeWithoutResult(s->{requireLease(run,owner);db.update("UPDATE provider_sync_run SET details=details||?::jsonb WHERE id=?",json.write(Map.of("totalCount",t,"pageSize",z)),run);db.update("UPDATE provider_sync_work SET num_of_rows=? WHERE run_id=?",z,run);for(int n=2;n<=(t+z-1)/z;n++)addWork(run,"PAGE:"+n,"PAGE",null,n,z);});}
  NmcBasicInfoDiscoveryProbe.validatePage(page,number,size,total);
 }
 private void revalidateBulk(UUID run,UUID owner){
  var first=db.queryForList("SELECT w.*,r.raw_xml,r.fetched_at FROM provider_sync_work w JOIN provider_response r ON r.id=w.response_id WHERE w.run_id=? AND w.unit_key='PAGE:1' AND w.status='SUCCESS'",run);
  if(first.isEmpty())return;heartbeat(run,owner);var w=first.getFirst();var old=parser.parse(w.get("raw_xml").toString(),((Timestamp)w.get("fetched_at")).toInstant());
  var p=provider.fetchPage("BASIC:"+run+":REVALIDATE",null,1,old.numOfRows()).page();NmcBasicInfoDiscoveryProbe.validatePage(p,1,old.numOfRows(),old.totalCount());
  if(!p.items().stream().map(NmcBasicInfoDiscoveryProbe::hpid).toList().equals(old.items().stream().map(NmcBasicInfoDiscoveryProbe::hpid).toList()))throw new ServiceProblem("BASIC_UNSTABLE_PAGINATION");pause();
 }
 private void expireStaging(UUID run,UUID owner){tx.executeWithoutResult(s->{requireLease(run,owner);
  var expired=db.queryForList("SELECT DISTINCT w.unit_key FROM provider_sync_work w JOIN provider_response r ON r.id=w.response_id WHERE w.run_id=? AND w.status='SUCCESS' AND r.fetched_at<clock_timestamp()-interval '7 days'",String.class,run);
  for(String unit:expired){var response=db.queryForObject("SELECT response_id FROM provider_sync_work WHERE run_id=? AND unit_key=?",Long.class,run,unit);db.update("DELETE FROM hospital_basic_info_dataset_member WHERE run_id=? AND response_id=?",run,response);db.update("DELETE FROM hospital_basic_info_snapshot WHERE sync_run_id=? AND provider_response_id=?",run,response);db.update("UPDATE provider_sync_work SET status='PENDING',response_id=NULL WHERE run_id=? AND unit_key=?",run,unit);}
 });}
 private boolean reconcileTargets(UUID run,UUID owner,String mode){return Boolean.TRUE.equals(tx.execute(s->{requireLease(run,owner);
  db.queryForList("SELECT pg_advisory_xact_lock(hashtext('eroute:catalog:publish'))");var active=targets();var details=json.read(db.queryForObject("SELECT details::text FROM provider_sync_run WHERE id=?",String.class,run),com.fasterxml.jackson.databind.JsonNode.class);int size=details.path("pageSize").asInt(10);
  for(String h:active)if(!Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM hospital_basic_info_dataset_member WHERE run_id=? AND hpid=?)",Boolean.class,run,h))){
   if(mode.equals("NATIONWIDE"))throw new ServiceProblem("BASIC_UNSTABLE_PAGINATION");addWork(run,"HPID:"+h,"HPID",h,1,size);
  }
  db.update("UPDATE provider_sync_run SET details=jsonb_set(details,'{targets}',?::jsonb) WHERE id=?",json.write(active),run);
  return db.queryForObject("SELECT EXISTS(SELECT 1 FROM provider_sync_work WHERE run_id=? AND status<>'SUCCESS')",Boolean.class,run);
 }));}
 public void publish(UUID run,UUID owner){tx.executeWithoutResult(s->{
  requireLease(run,owner);db.queryForList("SELECT pg_advisory_xact_lock(hashtext('eroute:catalog:publish'))");
  if(Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM provider_sync_work WHERE run_id=? AND status<>'SUCCESS')",Boolean.class,run)))throw new ServiceProblem("BASIC_INCOMPLETE_DATASET");
  if(Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM hospital h WHERE h.active AND NOT EXISTS(SELECT 1 FROM hospital_basic_info_dataset_member m WHERE m.run_id=? AND m.hpid=h.hpid))",Boolean.class,run)))throw new ServiceProblem("BASIC_INCOMPLETE_DATASET");
  if(db.queryForObject("SELECT count(*) FROM hospital_basic_info_dataset_member WHERE run_id=?",Long.class,run)==0)throw new ServiceProblem("BASIC_INCOMPLETE_DATASET");
  var row=db.queryForMap("SELECT mode,details::text FROM provider_sync_run WHERE id=?",run);if(row.get("mode").equals("NATIONWIDE")){int total=json.read(row.get("details").toString(),com.fasterxml.jackson.databind.JsonNode.class).path("totalCount").asInt();if(db.queryForObject("SELECT count(*) FROM hospital_basic_info_snapshot WHERE sync_run_id=?",Integer.class,run)!=total)throw new ServiceProblem("BASIC_INCOMPLETE_DATASET");}
  db.update("INSERT INTO hospital_basic_info_state(singleton,current_run_id,published_at) VALUES(true,?,clock_timestamp()) ON CONFLICT(singleton) DO UPDATE SET previous_run_id=hospital_basic_info_state.current_run_id,current_run_id=excluded.current_run_id,published_at=excluded.published_at",run);
  db.update("UPDATE provider_sync_run SET status='COMPLETE',completed_at=clock_timestamp(),next_attempt_at=?,details=details-'error',lease_owner=NULL,lease_until=NULL WHERE id=?",Timestamp.from(Instant.now().plus(basic.refreshInterval())),run);
 });}
 private void requireLease(UUID run,UUID owner){if(!Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM provider_sync_run WHERE id=? AND lease_owner=? AND lease_until>clock_timestamp() AND status='RUNNING' FOR UPDATE)",Boolean.class,run,owner)))throw new ServiceProblem("BASIC_LEASE_LOST");}
 private void heartbeat(UUID run,UUID owner){if(db.update("UPDATE provider_sync_run SET lease_until=clock_timestamp()+interval '2 minutes' WHERE id=? AND lease_owner=? AND lease_until>clock_timestamp()",run,owner)!=1)throw new ServiceProblem("BASIC_LEASE_LOST");}
 private Instant nextBudget(String error){if(error.equals("CALL_RATE_LIMIT"))return Instant.now().plusSeconds(2);var t=db.queryForObject("SELECT min(requested_at)+interval '24 hours 1 second' FROM nmc_call_attempt WHERE key_alias=? AND endpoint=? AND requested_at>clock_timestamp()-interval '24 hours'",Timestamp.class,config.keyAlias(),ENDPOINT);var blocked=db.query("SELECT blocked_until FROM nmc_budget_block WHERE key_alias=? AND endpoint=?",(r,n)->r.getTimestamp(1),config.keyAlias(),ENDPOINT);Instant next=t==null?Instant.now().plusSeconds(60):t.toInstant();if(!blocked.isEmpty()&&blocked.getFirst().toInstant().isAfter(next))next=blocked.getFirst().toInstant();return next;}
 private void pause(){try{Thread.sleep(Math.max(550,1000/config.requestsPerSecond()+50));}catch(InterruptedException e){Thread.currentThread().interrupt();throw new ServiceProblem("REQUEST_DEADLINE");}}
 private String code(RuntimeException e){return e instanceof ServiceProblem p?p.code():"BASIC_SYNC_FAILED";}
}
