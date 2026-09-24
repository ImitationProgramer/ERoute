package com.eroute.emergency.infrastructure.persistence;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.port.*;
import com.eroute.emergency.infrastructure.nmc.NmcFieldNormalizer;
import com.fasterxml.jackson.core.type.TypeReference;
import java.sql.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;
@Repository
public class JdbcHospitalStore implements HospitalRepository,HospitalObservationRepository {
 private final JdbcTemplate db;private final JsonCodec json;private final NmcFieldNormalizer normalizer;
 public JdbcHospitalStore(JdbcTemplate db,JsonCodec json,NmcFieldNormalizer normalizer){this.db=db;this.json=json;this.normalizer=normalizer;}
 @Transactional(readOnly=true,isolation=org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
 public Optional<Catalog> catalog(){
  var states=db.query("SELECT version,fetched_at FROM catalog_state",(rs,n)->Map.entry(rs.getString(1),rs.getTimestamp(2).toInstant()));
  if(states.isEmpty())return Optional.empty();
  var rows=db.query("""
   SELECT h.*,r.stage1,r.stage2,r.verified FROM hospital h LEFT JOIN nmc_region_mapping r ON h.region_id=r.id
   WHERE h.active AND h.latitude IS NOT NULL AND h.longitude IS NOT NULL
   """,(rs,n)->hospital(rs));
  return Optional.of(new Catalog(rows,states.getFirst().getValue(),states.getFirst().getKey()));
 }
 @Transactional(readOnly=true)
 public Optional<HospitalMaster> findActiveByHpid(String hpid){
  return db.query("""
   SELECT h.*,r.stage1,r.stage2,c.version::text AS catalog_state_version,c.fetched_at AS catalog_fetched_at
   FROM hospital h
   LEFT JOIN nmc_region_mapping r ON h.region_id=r.id
   CROSS JOIN catalog_state c
   WHERE h.active AND h.latitude IS NOT NULL AND h.longitude IS NOT NULL AND h.hpid=?
   """,(rs,n)->new HospitalMaster(hospital(rs),instant(rs,"updated_at"),instant(rs,"catalog_fetched_at"),rs.getString("catalog_state_version")),hpid).stream().findFirst();
 }
 public Optional<Batch> lastComplete(String region){return db.query("SELECT batch_json::text FROM region_cache WHERE region_id=? AND batch_json IS NOT NULL",(rs,n)->json.read(rs.getString(1),Batch.class),region).stream().findFirst();}
 public Instant lastAttemptAt(String region){return db.query("SELECT last_attempt_at FROM region_cache WHERE region_id=?",(rs,n)->rs.getTimestamp(1)==null?null:rs.getTimestamp(1).toInstant(),region).stream().filter(Objects::nonNull).findFirst().orElse(null);}
 @Transactional(readOnly=true)
 public CurrentHospitalObservation current(String hpid,String region){
  return db.query("""
   SELECT o.coverage_status,o.checked_at,s.fetched_at,s.raw_json::text AS raw_json,
          c.last_attempt_at,c.last_error
   FROM hospital h
   LEFT JOIN hospital_observation o ON o.hpid=h.hpid
   LEFT JOIN hospital_realtime_snapshot s ON s.id=o.snapshot_id
   LEFT JOIN region_cache c ON c.region_id=h.region_id
   WHERE h.hpid=? AND h.region_id=?
   """,(rs,n)->{
    Coverage coverage=coverage(rs.getString("coverage_status"));
    String error=rs.getString("last_error");
    if(regionMappingError(error))error="REGION_MAPPING_ERROR";
    Refresh refresh=error==null?(coverage==Coverage.LIVE_UNKNOWN?Refresh.NOT_REQUESTED:Refresh.CACHE_HIT):deferred(error)?Refresh.BUDGET_DEFERRED:(regionMappingError(error)||"REQUEST_NOT_STARTED".equals(error))?Refresh.NOT_REQUESTED:Refresh.ERROR;
    RawItem item=rs.getString("raw_json")==null?null:rawItem(rs.getString("raw_json"));
    Instant fetched=item==null?instant(rs,"checked_at"):instant(rs,"fetched_at");
    return new CurrentHospitalObservation(coverage,refresh,item,fetched,instant(rs,"last_attempt_at"),error);
   },hpid,region).stream().findFirst().orElse(new CurrentHospitalObservation(Coverage.LIVE_UNKNOWN,Refresh.NOT_REQUESTED,null,null,null,null));
 }
 public String lastError(String region){return db.query("SELECT last_error FROM region_cache WHERE region_id=?",(rs,n)->rs.getString(1),region).stream().filter(Objects::nonNull).findFirst().orElse(null);}
 public boolean acquireLease(String region,UUID owner){
  return db.update("""
   INSERT INTO region_cache(region_id,lease_owner,lease_until) VALUES(?,?,clock_timestamp()+interval '30 seconds')
   ON CONFLICT(region_id) DO UPDATE SET lease_owner=excluded.lease_owner,lease_until=excluded.lease_until
   WHERE region_cache.lease_until IS NULL OR region_cache.lease_until<clock_timestamp()
   """,region,owner)==1;
 }
 public void releaseLease(String region,UUID owner){db.update("UPDATE region_cache SET lease_owner=NULL,lease_until=NULL WHERE region_id=? AND lease_owner=?",region,owner);}
 public void markAttempt(String region){db.update("UPDATE region_cache SET last_attempt_at=clock_timestamp() WHERE region_id=?",region);}
 public void markError(String region,String error){db.update("UPDATE region_cache SET last_error=? WHERE region_id=?",error,region);}
 public long response(String endpoint,String scope,int page,String xml,Instant fetchedAt,String outcome){
  return db.queryForObject("INSERT INTO provider_response(endpoint,scope,page_no,raw_xml,fetched_at,outcome) VALUES(?,?,?,?,?,?) RETURNING id",Long.class,endpoint,scope,page,xml,Timestamp.from(fetchedAt),outcome);
 }
 @Transactional
 public void complete(String region,Batch batch,UUID owner){
  int changed=db.update("UPDATE region_cache SET batch_json=?::jsonb,fetched_at=?,last_error=NULL WHERE region_id=? AND lease_owner=? AND lease_until>clock_timestamp()",json.write(batch),Timestamp.from(batch.fetchedAt()),region,owner);
  if(changed!=1)throw new IllegalStateException("Refresh lease expired");
  var ids=new HashSet<String>();
  for(var item:batch.items()){
   String hpid=item.single("hpid").strip();ids.add(hpid);var time=normalizer.timestamp(item.single("hvidate"));
   Long id=db.queryForObject("""
    INSERT INTO hospital_realtime_snapshot(hpid,region_id,fetched_at,source_raw_timestamp,parsed_source_timestamp,raw_json,response_ids)
    VALUES(?,?,?,?,?,?::jsonb,?::jsonb) RETURNING id
    """,Long.class,hpid,region,Timestamp.from(batch.fetchedAt()),time.sourceRawTimestamp(),time.parsedSourceTimestamp()==null?null:LocalDateTime.parse(time.parsedSourceTimestamp()),json.write(item.fields()),json.write(batch.responseIds()));
   for(String field:item.fields().keySet()){
    var value=normalizer.value(NmcFieldNormalizer.BEDS,field,item);
    db.update("INSERT INTO hospital_resource_value VALUES(?,?,?,?,?,?,?)",id,NmcFieldNormalizer.BEDS,field,value.rawValue(),value.numericValue()==null?"RAW":"INTEGER",value.numericValue(),value.interpretationStatus().name());
   }
   db.update("INSERT INTO hospital_observation VALUES(?,?,?,?) ON CONFLICT(hpid) DO UPDATE SET snapshot_id=excluded.snapshot_id,coverage_status=excluded.coverage_status,checked_at=excluded.checked_at",hpid,id,"LIVE_AVAILABLE",Timestamp.from(batch.fetchedAt()));
  }
  for(String hpid:db.queryForList("SELECT hpid FROM hospital WHERE active AND region_id=?",String.class,region))if(!ids.contains(hpid)){
   db.update("INSERT INTO hospital_observation VALUES(?,NULL,'LIVE_NOT_PROVIDED',?) ON CONFLICT(hpid) DO UPDATE SET snapshot_id=NULL,coverage_status=excluded.coverage_status,checked_at=excluded.checked_at",hpid,Timestamp.from(batch.fetchedAt()));
  }
 }
 private Hospital hospital(ResultSet rs)throws SQLException{
  return new Hospital(rs.getString("hpid"),rs.getString("name"),rs.getString("class_code"),rs.getString("class_name"),rs.getString("address"),
   new Point(rs.getDouble("latitude"),rs.getDouble("longitude")),rs.getString("main_phone"),rs.getString("secondary_phone"),
   rs.getString("region_id")==null?null:new Region(rs.getString("region_id"),rs.getString("stage1"),rs.getString("stage2")));
 }
 private Instant instant(ResultSet rs,String column)throws SQLException{Timestamp value=rs.getTimestamp(column);return value==null?null:value.toInstant();}
 private Coverage coverage(String raw){try{return raw==null?Coverage.LIVE_UNKNOWN:Coverage.valueOf(raw);}catch(IllegalArgumentException e){return Coverage.LIVE_UNKNOWN;}}
 private boolean regionMappingError(String error){return "REGION_MAPPING_ERROR".equals(error)||"REGION_UNVERIFIED".equals(error)||"REGION_UNRESOLVED".equals(error);}
 private boolean deferred(String error){return "CALL_BUDGET_LIMIT".equals(error)||"CALL_RATE_LIMIT".equals(error);}
 private RawItem rawItem(String raw){try{return new RawItem(json.mapper().readValue(raw,new TypeReference<Map<String,List<String>>>(){}));}catch(Exception e){throw new IllegalStateException("Stored realtime JSON invalid",e);}}
}
