package com.eroute.emergency.infrastructure.persistence;
import com.eroute.common.config.BasicInfoProperties;
import com.eroute.emergency.domain.model.BasicModels.*;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.port.HospitalBasicInfoRepository;
import com.eroute.emergency.infrastructure.nmc.*;
import java.sql.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;
@Repository
public class JdbcHospitalBasicInfoStore implements HospitalBasicInfoRepository {
 private final JdbcTemplate db;private final JsonCodec json;private final BasicInfoProperties config;private final Clock clock;
 public JdbcHospitalBasicInfoStore(JdbcTemplate db,JsonCodec json,BasicInfoProperties config,Clock clock){this.db=db;this.json=json;this.config=config;this.clock=clock;}
 public long stage(UUID run,String hpid,long response,Instant fetched,RawBasicItem raw,NormalizedBasic data,String sourceHash){
  long id=db.queryForObject("""
   INSERT INTO hospital_basic_info_snapshot(sync_run_id,hpid,fetched_at,fetch_status,provider_response_id,raw_payload,raw_department_text,departments_status,source_schema_version,normalizer_version)
   VALUES(?,?,?,'SUCCESS',?,?::jsonb,?,?,?,?) RETURNING id
   """,Long.class,run,hpid,Timestamp.from(fetched),response,json.write(raw.fields()),data.rawDepartmentText(),data.departmentsStatus().name(),"v13:"+sourceHash,NmcBasicInfoNormalizer.VERSION);
  for(var d:data.departments())db.update("INSERT INTO hospital_department VALUES(?,?,?,?,?,?)",id,d.ordinal(),d.name(),d.rawValue(),d.source(),d.interpretationStatus().name());
  for(var h:data.operatingHours())db.update("INSERT INTO hospital_operating_hours VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",id,h.day().name(),h.open()==null?null:LocalTime.parse(h.open()),h.close()==null?null:LocalTime.parse(h.close()),h.rawOpenValue(),h.rawCloseValue(),h.openPresence().name(),h.closePresence().name(),h.openStatus().name(),h.closeStatus().name(),h.status().name(),h.source());
  member(run,hpid,id,"PROVIDED",fetched,response);return id;
 }
 public void absence(UUID run,String hpid,long response,Instant checked){
  var ids=db.query("SELECT m.snapshot_id FROM hospital_basic_info_dataset_member m JOIN hospital_basic_info_state s ON s.current_run_id=m.run_id WHERE m.hpid=?",(r,n)->(Long)r.getObject(1),hpid);
  member(run,hpid,ids.isEmpty()?null:ids.getFirst(),"NOT_PROVIDED",checked,response);
 }
 private void member(UUID run,String hpid,Long snapshot,String status,Instant checked,long response){db.update("INSERT INTO hospital_basic_info_dataset_member VALUES(?,?,?,?,?,?) ON CONFLICT(run_id,hpid) DO UPDATE SET snapshot_id=excluded.snapshot_id,record_status=excluded.record_status,checked_at=excluded.checked_at,response_id=excluded.response_id",run,hpid,snapshot,status,Timestamp.from(checked),response);}
 @Transactional(readOnly=true,isolation=org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
 public Optional<HospitalBasicInfo> current(String hpid){
  var members=db.queryForList("""
   SELECT m.*,s.fetched_at,s.raw_department_text,s.departments_status
   FROM hospital_basic_info_state state JOIN hospital_basic_info_dataset_member m ON m.run_id=state.current_run_id
   LEFT JOIN hospital_basic_info_snapshot s ON s.id=m.snapshot_id WHERE m.hpid=?
   """,hpid);
  var runs=db.queryForList("SELECT id,status,details,started_at FROM provider_sync_run WHERE endpoint=? AND jsonb_exists(details->'targets',?) ORDER BY started_at DESC LIMIT 1",NmcBasicInfoDiscoveryProbe.ENDPOINT,hpid);
  Map<String,Object> member=members.isEmpty()?null:members.getFirst(),run=runs.isEmpty()?null:runs.getFirst();
  Instant fetched=member==null?null:instant(member.get("fetched_at")),attempt=null;String error=null;Refresh refresh=member==null?Refresh.NOT_REQUESTED:Refresh.CACHE_HIT;
  boolean failed=run!=null&&Set.of("FAILED","SUPERSEDED").contains(run.get("status")),deferred=run!=null&&"BUDGET_DEFERRED".equals(run.get("status")),running=run!=null&&"RUNNING".equals(run.get("status"));
  if(run!=null){
   var a=db.query("SELECT max(last_attempt_at) FROM provider_sync_work WHERE run_id=? AND (hpid=? OR kind='PAGE')",(r,n)->r.getTimestamp(1),run.get("id"),hpid);if(!a.isEmpty())attempt=instant(a.getFirst());
   var details=json.read(run.get("details").toString(),com.fasterxml.jackson.databind.JsonNode.class);error=details.path("error").isTextual()?details.path("error").asText():null;
  }
  if(failed)refresh=Refresh.ERROR;else if(deferred)refresh=Refresh.BUDGET_DEFERRED;else if(running)refresh=Refresh.IN_PROGRESS;
  boolean absent=member!=null&&"NOT_PROVIDED".equals(member.get("record_status"));
  var reasons=new ArrayList<String>();if(fetched!=null&&fetched.plus(config.refreshInterval()).isBefore(clock.instant()))reasons.add("TTL_EXPIRED");if(fetched!=null&&failed)reasons.add("REFRESH_ERROR");if(fetched!=null&&deferred)reasons.add("BUDGET_DEFERRED");if(fetched!=null&&absent)reasons.add("SOURCE_RECORD_NOT_PROVIDED");
  var departments=new ArrayList<Department>();var hours=new ArrayList<OperatingHours>();Status status=Status.MISSING;
  if(member!=null&&member.get("snapshot_id")!=null){
   long snapshot=((Number)member.get("snapshot_id")).longValue();status=Status.valueOf(member.get("departments_status").toString());
   var unique=new LinkedHashMap<String,Department>();
   db.query("SELECT * FROM hospital_department WHERE snapshot_id=? ORDER BY ordinal",(r,n)->new Department(r.getInt("ordinal"),r.getString("department_name"),r.getString("raw_value"),r.getString("source"),Status.valueOf(r.getString("interpretation_status"))),snapshot).forEach(d->{if(d.interpretationStatus()==Status.KNOWN)unique.putIfAbsent(d.name(),d);});departments.addAll(unique.values());
   hours.addAll(db.query("SELECT * FROM hospital_operating_hours WHERE snapshot_id=?",(r,n)->new OperatingHours(Day.valueOf(r.getString("day_type")),time(r,"open_time"),time(r,"close_time"),r.getString("raw_open_value"),r.getString("raw_close_value"),Presence.valueOf(r.getString("open_presence")),Presence.valueOf(r.getString("close_presence")),Status.valueOf(r.getString("open_status")),Status.valueOf(r.getString("close_status")),Status.valueOf(r.getString("interpretation_status")),r.getString("source")),snapshot));hours.sort(Comparator.comparing(OperatingHours::day));
  }else if(absent){status=Status.NOT_PROVIDED;for(var day:Day.values())hours.add(new OperatingHours(day,null,null,null,null,Presence.MISSING,Presence.MISSING,Status.NOT_PROVIDED,Status.NOT_PROVIDED,Status.NOT_PROVIDED,"NMC"));}
  var legacy=hours.stream().map(h->new ClinicHours(h.day().name(),h.rawOpenValue(),h.rawCloseValue(),h.status()==Status.UNPARSEABLE?Interpretation.UNVERIFIED:Interpretation.valueOf(h.status().name()))).toList();
  return Optional.of(new HospitalBasicInfo(failed?FetchStatus.ERROR:member!=null?FetchStatus.SUCCESS:FetchStatus.NOT_REQUESTED,member==null?null:(String)member.get("raw_department_text"),member==null?null:legacy,null,null,fetched,attempt,error,fetched!=null?"PROVIDED":absent?"NOT_PROVIDED":"NOT_COLLECTED",refresh,status,List.copyOf(departments),List.copyOf(hours),!reasons.isEmpty(),List.copyOf(reasons),member==null?null:member.get("run_id").toString()));
 }
 private Instant instant(Object value){return value==null?null:((Timestamp)value).toInstant();}
 private String time(ResultSet rs,String key)throws SQLException{var t=rs.getTime(key);return t==null?null:t.toLocalTime().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm"));}
}
