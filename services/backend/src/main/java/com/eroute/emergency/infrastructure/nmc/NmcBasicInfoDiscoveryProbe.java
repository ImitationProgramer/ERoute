package com.eroute.emergency.infrastructure.nmc;

import com.eroute.common.config.ERouteProperties;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import com.fasterxml.jackson.databind.node.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Explicit, resumable discovery. Never writes hospital or published datasets. */
@Component
public class NmcBasicInfoDiscoveryProbe {
 public static final String ENDPOINT="getEgytBassInfoInqire", VERSION="basic-probe-v1";
 private final NmcApiClient client; private final NmcXmlParser parser; private final JdbcTemplate db; private final JsonCodec json; private final ERouteProperties config;
 public NmcBasicInfoDiscoveryProbe(NmcApiClient client,NmcXmlParser parser,JdbcTemplate db,JsonCodec json,ERouteProperties config){this.client=client;this.parser=parser;this.db=db;this.json=json;this.config=config;}
 public String sourceHash(){try(var in=new org.springframework.core.io.ClassPathResource("nmc/codebooks/v13/codebook.json").getInputStream()){return json.mapper().readTree(in).path("officialSource").path("sha256").asText();}catch(Exception e){throw new ServiceProblem("CODEBOOK_MISSING");}}
 public Map<String,Object> run(Long resume){
  return db.execute((org.springframework.jdbc.core.ConnectionCallback<Map<String,Object>>) connection->{
   try(var statement=connection.prepareStatement("SELECT pg_try_advisory_lock(hashtext('eroute:basic:discovery'))");var result=statement.executeQuery()){
    result.next();if(!result.getBoolean(1))throw new ServiceProblem("BASIC_DISCOVERY_IN_PROGRESS");
   }
   try{return perform(resume);}finally{try(var statement=connection.prepareStatement("SELECT pg_advisory_unlock(hashtext('eroute:basic:discovery'))")){statement.execute();}}
  });
 }
 private Map<String,Object> perform(Long resume){
  ObjectNode report;
  long id;
  if(resume==null){
   report=json.mapper().createObjectNode();report.put("probeVersion",VERSION);report.put("status","PENDING");report.put("maximumPageSize","UNVERIFIED");report.set("calls",json.mapper().createArrayNode());
   id=db.queryForObject("INSERT INTO discovery_result(passed,mode,report,pdf_sha256,endpoint) VALUES(false,'PENDING',?::jsonb,?,?) RETURNING id",Long.class,json.write(report),sourceHash(),ENDPOINT);
  }else{
   var row=db.queryForMap("SELECT report::text,pdf_sha256,created_at FROM discovery_result WHERE id=? AND endpoint=?",resume,ENDPOINT);
   if(!sourceHash().equals(row.get("pdf_sha256")))throw new ServiceProblem("DISCOVERY_SOURCE_CHANGED");
   if(((java.sql.Timestamp)row.get("created_at")).toInstant().plus(Duration.ofDays(7)).isBefore(Instant.now()))throw new ServiceProblem("DISCOVERY_EXPIRED");
   report=(ObjectNode)json.read(row.get("report").toString(),com.fasterxml.jackson.databind.JsonNode.class);id=resume;
  }
  report.put("id",id);
  var session=new Session(id,report);
  boolean passed=false;String mode="PENDING";Integer size=null;
  try{
   List<String> targets=db.queryForList("SELECT hpid FROM (SELECT h.hpid,r.stage1,row_number() OVER(PARTITION BY r.stage1 ORDER BY h.class_code,h.hpid) AS n FROM hospital h LEFT JOIN nmc_region_mapping r ON r.id=h.region_id WHERE h.active) h ORDER BY n,stage1,hpid LIMIT 5",String.class);
   if(targets.isEmpty())throw new ServiceProblem("BASIC_MASTER_EMPTY");
   for(String hpid:targets){var p=session.page("HPID:"+hpid,1,10,hpid);verifySingle(p,hpid);}
   try{
    Page first=null;
    for(int requested:List.of(10,100,500,1000)){
     var p=session.page("SIZE:"+requested,1,requested,null);
     if(first==null)first=p;
     if(p.totalCount()==0||p.pageNo()!=1||p.totalCount()!=first.totalCount()||p.items().size()!=Math.min(p.numOfRows(),p.totalCount()))throw new ServiceProblem("BASIC_BULK_INVALID");
    }
    var initial=session.page("BULK:1",1,100,null);size=initial.numOfRows();
    int total=initial.totalCount(),pages=Math.max(1,(total+size-1)/size);var all=new LinkedHashMap<String,RawItem>();
    for(int n=1;n<=pages;n++){
     var p=n==1?initial:session.page("BULK:"+n,n,size,null);validatePage(p,n,size,total);
     for(var item:p.items()){String h=hpid(item);if(all.putIfAbsent(h,item)!=null)throw new ServiceProblem("BASIC_DUPLICATE_HPID");}
    }
    var end=session.page("END",pages+1,size,null);
    if(end.pageNo()!=pages+1||end.numOfRows()!=size||end.totalCount()!=total||!end.items().isEmpty())throw new ServiceProblem("BASIC_BULK_INVALID");
    var repeat=session.page("REPEAT",1,size,null);validatePage(repeat,1,size,total);
    if(!repeat.items().stream().map(NmcBasicInfoDiscoveryProbe::hpid).toList().equals(initial.items().stream().map(NmcBasicInfoDiscoveryProbe::hpid).toList()))throw new ServiceProblem("BASIC_UNSTABLE_PAGINATION");
    for(var call:report.withArray("calls"))if(call.path("unit").asText().startsWith("SIZE:")){
     Page p=session.stored(call.path("responseId").asLong());for(var item:p.items())if(!all.containsKey(hpid(item)))throw new ServiceProblem("BASIC_PAGE_SIZE_COVERAGE");
    }
    var expected=new TreeSet<>(db.queryForList("SELECT hpid FROM hospital WHERE active",String.class));var missing=new TreeSet<>(expected);missing.removeAll(all.keySet());var extra=new TreeSet<>(all.keySet());extra.removeAll(expected);
    report.set("missingMasterHpids",json.mapper().valueToTree(missing));report.set("extraHpids",json.mapper().valueToTree(extra));report.put("bulkObservedPageSize",size);report.put("activeMasterCount",expected.size());report.put("totalCount",total);report.put("uniqueHpidCount",all.size());
    if(!missing.isEmpty()){
     for(String missingId:missing.stream().limit(5).toList()){
      var check=session.page("MISSING:"+missingId,1,10,missingId);
      if(check.totalCount()==0&&check.items().isEmpty())report.withArray("confirmedAbsentHpids").add(missingId);
      else verifySingle(check,missingId);
     }
     throw new ServiceProblem("BASIC_MASTER_COVERAGE_MISSING");
    }
    mode="NATIONWIDE";passed=true;
   }catch(ServiceProblem e){
    if(Set.of("BASIC_BULK_INVALID","BASIC_DUPLICATE_HPID","BASIC_MISSING_HPID","BASIC_UNSTABLE_PAGINATION","BASIC_PAGE_SIZE_COVERAGE","BASIC_MASTER_COVERAGE_MISSING").contains(e.code())){mode="PER_HPID";size=10;passed=true;report.put("bulkFailure",e.code());}
    else throw e;
   }
   report.remove("error");report.put("status","PASSED");report.put("mode",mode);report.put("safePageSize",size);
  }catch(ServiceProblem e){report.put("status","INCONCLUSIVE");report.put("error",e.code());}
  finally{report.put("totalAttempts",report.path("totalAttempts").asInt()+session.attempts());report.put("invocationAttempts",session.attempts());report.put("completedAt",Instant.now().toString());db.update("UPDATE discovery_result SET passed=?,mode=?,page_size=?,report=?::jsonb WHERE id=?",passed,mode,size,json.write(report),id);}
  return Map.of("discoveryId",id,"status",report.path("status").asText(),"mode",mode,"report",report);
 }
 public static String hpid(RawItem row){String h=row.single("hpid");if(h==null||h.isBlank())throw new ServiceProblem("BASIC_MISSING_HPID");return h.strip();}
 public static void verifySingle(Page p,String requested){if(p.pageNo()!=1||p.totalCount()!=1||p.items().size()!=1||!hpid(p.items().getFirst()).equals(requested))throw new ServiceProblem("BASIC_HPID_MISMATCH");}
 public static void validatePage(Page p,int number,int size,int total){if(p.pageNo()!=number||p.numOfRows()!=size||p.totalCount()!=total||p.items().size()!=Math.min(size,Math.max(0,total-(number-1)*size)))throw new ServiceProblem("BASIC_BULK_INVALID");}
 private class Session {
  final long id;final ObjectNode report;final Instant started=Instant.now();
  Session(long id,ObjectNode report){this.id=id;this.report=report;}
  int attempts(){return db.queryForObject("SELECT count(*) FROM nmc_call_attempt WHERE key_alias=? AND endpoint=? AND scope LIKE ? AND requested_at>=?",Integer.class,config.keyAlias(),ENDPOINT,"DISCOVERY:BASIC:"+id+":%",java.sql.Timestamp.from(started));}
  Page stored(long response){var row=db.queryForMap("SELECT raw_xml,fetched_at FROM provider_response WHERE id=? AND endpoint=?",response,ENDPOINT);return parser.parse(row.get("raw_xml").toString(),((java.sql.Timestamp)row.get("fetched_at")).toInstant());}
  Page page(String unit,int no,int size,String hpid){
   for(var call:report.withArray("calls"))if(call.path("unit").asText().equals(unit))return stored(call.path("responseId").asLong());
   int allowance=40-attempts();if(allowance<=0)throw new ServiceProblem("DISCOVERY_RUN_BUDGET_REACHED");
   var params=new LinkedHashMap<String,String>();params.put("pageNo",""+no);params.put("numOfRows",""+size);if(hpid!=null)params.put("HPID",hpid);
   var fetched=client.fetch(ENDPOINT,"DISCOVERY:BASIC:"+id+":"+unit,params,Math.min(2,allowance));var p=fetched.page();
   var node=report.withArray("calls").addObject();node.put("unit",unit);node.put("requestedPage",no);node.put("requestedSize",size);node.put("responseId",fetched.responseId());node.put("pageNo",p.pageNo());node.put("numOfRows",p.numOfRows());node.put("totalCount",p.totalCount());node.put("actualCount",p.items().size());node.put("fetchedAt",p.fetchedAt().toString());
   var fields=new TreeMap<String,Set<String>>();for(var item:p.items())item.fields().forEach((k,v)->fields.computeIfAbsent(k,x->new TreeSet<>()).addAll(v));node.set("observedValues",json.mapper().valueToTree(fields));
   db.update("UPDATE discovery_result SET report=?::jsonb WHERE id=?",json.write(report),id);
   try{Thread.sleep(Math.max(550,1000/config.requestsPerSecond()+50));}catch(InterruptedException e){Thread.currentThread().interrupt();throw new ServiceProblem("REQUEST_DEADLINE");}
   return p;
  }
 }
}
