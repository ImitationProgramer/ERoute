package com.eroute.emergency.application;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.infrastructure.nmc.*;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import java.time.*;
import java.sql.Timestamp;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
@Service
public class HospitalCatalogSyncService {
 private final JdbcTemplate db;private final NmcPageCollector collector;private final NmcRegionResolver regions;private final JsonCodec json;private final Clock clock;private final TransactionTemplate tx;
 public HospitalCatalogSyncService(JdbcTemplate db,NmcPageCollector collector,NmcRegionResolver regions,JsonCodec json,Clock clock,PlatformTransactionManager tm){this.db=db;this.collector=collector;this.regions=regions;this.json=json;this.clock=clock;tx=new TransactionTemplate(tm);}
 public void synchronize(){
  db.execute((org.springframework.jdbc.core.ConnectionCallback<Void>) connection->{
   try(var statement=connection.prepareStatement("SELECT pg_try_advisory_lock(hashtext('eroute:catalog:sync'))");var rs=statement.executeQuery()){
    rs.next();if(!rs.getBoolean(1))throw new ServiceProblem("CATALOG_SYNC_IN_PROGRESS");
   }
   try{performSync();}finally{try(var statement=connection.prepareStatement("SELECT pg_advisory_unlock(hashtext('eroute:catalog:sync'))")){statement.execute();}}
   return null;
  });
 }
 private void performSync(){
  var gates=db.queryForList("SELECT mode,page_size,pdf_sha256,report::text AS report FROM discovery_result WHERE passed AND endpoint='getEgytListInfoInqire' ORDER BY id DESC LIMIT 1");
  if(gates.isEmpty())throw new ServiceProblem("DISCOVERY_GATE_NOT_PASSED");
  var gate=gates.getFirst();String mode=gate.get("mode").toString();int size=((Number)gate.get("page_size")).intValue();
  try(var in=new org.springframework.core.io.ClassPathResource("nmc/codebooks/v13/codebook.json").getInputStream()){
   if(!json.mapper().readTree(in).path("officialSource").path("sha256").asText().equals(gate.get("pdf_sha256")))throw new ServiceProblem("DISCOVERY_SOURCE_CHANGED");
  }catch(java.io.IOException e){throw new ServiceProblem("CODEBOOK_MISSING");}
  UUID run=UUID.randomUUID();db.update("INSERT INTO provider_sync_run(id,mode,status,started_at) VALUES(?,?,'RUNNING',?)",run,mode,Timestamp.from(clock.instant()));
  try{
   var records=new LinkedHashMap<String,RawItem>();var responseIds=new ArrayList<Long>();
   if(mode.equals("NATIONWIDE")){
    var batch=collector.collect(NmcFieldNormalizer.LIST,"NATIONWIDE",Map.of(),size);responseIds.addAll(batch.responseIds());for(var row:batch.items())records.put(row.single("hpid").strip(),row);
   }else if(mode.equals("REGIONAL")){
    var report=json.read(gate.get("report").toString(),java.util.Map.class);
    Object validated=report.get("validatedRegionIds");
    if(!(validated instanceof java.util.List<?> regionIds)||regionIds.isEmpty())throw new ServiceProblem("REGIONAL_DISCOVERY_INCOMPLETE");
    var scopes=new ArrayList<Map<String,Object>>();
    for(Object id:regionIds){var matches=db.queryForList("SELECT stage1,stage2 FROM nmc_region_mapping WHERE id=?",id.toString());if(matches.size()!=1)throw new ServiceProblem("REGION_MAPPING_CHANGED");scopes.add(matches.getFirst());}
    if(scopes.isEmpty())throw new ServiceProblem("REGION_MAPPING_NOT_READY");
    for(var scope:scopes){var batch=collector.collect(NmcFieldNormalizer.LIST,scope.toString(),Map.of("Q0",scope.get("stage1").toString(),"Q1",scope.get("stage2").toString()),size);responseIds.addAll(batch.responseIds());for(var row:batch.items())records.put(row.single("hpid").strip(),row);}
   }else throw new ServiceProblem("UNKNOWN_COLLECTION_PLAN");
   if(records.isEmpty())throw new ServiceProblem("EMPTY_CATALOG_REQUIRES_REVIEW");
   Instant now=clock.instant();
   tx.executeWithoutResult(status->{
    db.queryForList("SELECT pg_advisory_xact_lock(hashtext('eroute:catalog:publish'))");
    for(var e:records.entrySet()){
     var row=e.getValue();String name=row.single("dutyName");if(name==null||name.isBlank())throw new ServiceProblem("INVALID_MASTER_NAME");
     Double lat=coordinate(row.single("wgs84Lat"),90),lon=coordinate(row.single("wgs84Lon"),180);
     db.update("""
      INSERT INTO hospital(hpid,name,class_code,class_name,address,latitude,longitude,main_phone,secondary_phone,region_id,raw_json,catalog_version,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?::jsonb,?,?) ON CONFLICT(hpid) DO UPDATE SET
      name=excluded.name,class_code=excluded.class_code,class_name=excluded.class_name,address=excluded.address,
      latitude=excluded.latitude,longitude=excluded.longitude,main_phone=excluded.main_phone,secondary_phone=excluded.secondary_phone,
      region_id=excluded.region_id,raw_json=excluded.raw_json,catalog_version=excluded.catalog_version,updated_at=excluded.updated_at,active=true,missing_runs=0
      """,e.getKey(),name,row.single("dutyEmcls"),row.single("dutyEmclsName"),row.single("dutyAddr"),lat,lon,row.single("dutyTel1"),row.single("dutyTel3"),regions.resolveId(row.single("dutyAddr")),json.write(row.fields()),run,Timestamp.from(now));
    }
    db.update("UPDATE hospital SET missing_runs=missing_runs+1,active=(missing_runs+1<2) WHERE catalog_version<>?",run);
    db.update("INSERT INTO catalog_state VALUES(true,?,?) ON CONFLICT(singleton) DO UPDATE SET version=excluded.version,fetched_at=excluded.fetched_at",run,Timestamp.from(now));
    db.update("UPDATE provider_sync_run SET status='COMPLETE',completed_at=?,details=?::jsonb WHERE id=?",Timestamp.from(now),json.write(Map.of("count",records.size(),"responseIds",responseIds)),run);
   });
  }catch(RuntimeException e){db.update("UPDATE provider_sync_run SET status='FAILED',completed_at=?,details=?::jsonb WHERE id=?",Timestamp.from(clock.instant()),json.write(Map.of("code",e instanceof ServiceProblem p?p.code():"SYNC_FAILED")),run);throw e;}
 }
 private Double coordinate(String raw,int bound){try{double v=Double.parseDouble(raw);return Double.isFinite(v)&&v>=-bound&&v<=bound?v:null;}catch(Exception e){return null;}}
}
