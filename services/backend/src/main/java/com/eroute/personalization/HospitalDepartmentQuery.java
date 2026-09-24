package com.eroute.personalization;

import com.eroute.common.config.BasicInfoProperties;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;

/** Published public data only: no member data, provider dependency or refresh. */
@Service
public class HospitalDepartmentQuery {
 private final JdbcTemplate db;private final Clock clock;private final BasicInfoProperties config;
 public HospitalDepartmentQuery(JdbcTemplate db,Clock clock,BasicInfoProperties config){this.db=db;this.clock=clock;this.config=config;}
 @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
 public Map<String,Object> query(List<String> hpids){
  if(hpids==null||hpids.isEmpty()||hpids.size()>100||new HashSet<>(hpids).size()!=hpids.size()||hpids.stream().anyMatch(h->h==null||h.isBlank()||h.length()>100))throw new IllegalArgumentException("INVALID_HPID_BATCH");
  var versions=db.queryForList("SELECT current_run_id::text FROM hospital_basic_info_state",String.class);
  String version=versions.isEmpty()?null:versions.getFirst();Instant now=clock.instant();
  String placeholders=String.join(",",Collections.nCopies(hpids.size(),"?"));
  var rows=db.queryForList("""
   SELECT h.hpid,h.active,m.record_status,s.id AS snapshot_id,s.departments_status,s.normalizer_version,s.fetched_at,r.status AS refresh_status
   FROM hospital h LEFT JOIN hospital_basic_info_state st ON true
   LEFT JOIN hospital_basic_info_dataset_member m ON m.run_id=st.current_run_id AND m.hpid=h.hpid
   LEFT JOIN hospital_basic_info_snapshot s ON s.id=m.snapshot_id
   LEFT JOIN LATERAL (SELECT status FROM provider_sync_run WHERE endpoint='getEgytBassInfoInqire' AND jsonb_exists(details->'targets',h.hpid) ORDER BY started_at DESC LIMIT 1) r ON true
   WHERE h.hpid IN ("""+placeholders+")",hpids.toArray());
  var tokens=db.queryForList("""
   SELECT m.hpid,d.* FROM hospital_basic_info_state st
   JOIN hospital_basic_info_dataset_member m ON m.run_id=st.current_run_id
   JOIN hospital_department d ON d.snapshot_id=m.snapshot_id
   WHERE m.hpid IN ("""+placeholders+") ORDER BY m.hpid,d.ordinal",hpids.toArray());
  var result=new ArrayList<Map<String,Object>>();
  for(String hpid:hpids){
   var row=rows.stream().filter(r->hpid.equals(r.get("hpid"))).findFirst().orElse(null);
   var item=new LinkedHashMap<String,Object>();item.put("hpid",hpid);item.put("datasetVersion",version);
   String status=row==null?"NOT_FOUND":!Boolean.TRUE.equals(row.get("active"))?"INACTIVE":row.get("record_status")==null?"NOT_COLLECTED":row.get("record_status").toString();
   item.put("recordStatus",status);item.put("snapshotId",row==null?null:row.get("snapshot_id"));
   item.put("departmentsStatus",row==null||row.get("departments_status")==null?"MISSING":row.get("departments_status"));
   item.put("normalizerVersion",row==null?null:row.get("normalizer_version"));
   Instant fetched=row==null||row.get("fetched_at")==null?null:((Timestamp)row.get("fetched_at")).toInstant();item.put("fetchedAt",fetched);item.put("validUntil",fetched==null?null:fetched.plus(config.refreshInterval()));
   var reasons=new ArrayList<String>();
   if(fetched!=null&&fetched.plus(config.refreshInterval()).isBefore(now))reasons.add("TTL_EXPIRED");
   if(fetched!=null&&"NOT_PROVIDED".equals(status))reasons.add("SOURCE_RECORD_NOT_PROVIDED");
   if(fetched!=null&&row.get("refresh_status")!=null){switch(row.get("refresh_status").toString()){case "FAILED","SUPERSEDED" -> reasons.add("REFRESH_ERROR");case "BUDGET_DEFERRED" -> reasons.add("BUDGET_DEFERRED");default -> {}}}
   item.put("stale",!reasons.isEmpty());item.put("staleReasons",reasons);
   var departments=new ArrayList<Map<String,Object>>();
   if(!Set.of("NOT_FOUND","INACTIVE").contains(status))for(var token:tokens)if(hpid.equals(token.get("hpid"))){var d=new LinkedHashMap<String,Object>();d.put("name",token.get("department_name"));d.put("rawValue",token.get("raw_value"));d.put("source",token.get("source"));d.put("interpretationStatus",token.get("interpretation_status"));d.put("ordinal",token.get("ordinal"));departments.add(d);}
   item.put("departments",departments);result.add(item);
  }
  var out=new LinkedHashMap<String,Object>();out.put("datasetVersion",version);out.put("generatedAt",now);out.put("hospitals",result);return out;
 }
}
