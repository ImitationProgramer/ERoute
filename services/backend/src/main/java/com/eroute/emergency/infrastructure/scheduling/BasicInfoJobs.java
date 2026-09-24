package com.eroute.emergency.infrastructure.scheduling;
import com.eroute.common.config.BasicInfoProperties;
import com.eroute.emergency.application.HospitalBasicInfoSyncService;
import com.eroute.emergency.infrastructure.nmc.NmcBasicInfoDiscoveryProbe;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(name="eroute.jobs-enabled",havingValue="true",matchIfMissing=true)
public class BasicInfoJobs {
 private final JdbcTemplate db;private final HospitalBasicInfoSyncService sync;private final BasicInfoProperties config;
 public BasicInfoJobs(JdbcTemplate db,HospitalBasicInfoSyncService sync,BasicInfoProperties config){this.db=db;this.sync=sync;this.config=config;}
 /** Checks DB due times only; no periodic nationwide provider polling. */
 @Scheduled(initialDelayString="PT1M",fixedDelayString="PT1M")
 public void due(){
  if(!config.schedulerEnabled())return;
  if(!Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM hospital_basic_info_state)",Boolean.class)))return;
  var rows=db.queryForList("SELECT * FROM provider_sync_run WHERE endpoint=? ORDER BY started_at DESC LIMIT 1",NmcBasicInfoDiscoveryProbe.ENDPOINT);if(rows.isEmpty())return;var r=rows.getFirst();String status=r.get("status").toString();
  if(status.equals("RUNNING")){
   if(r.get("lease_until")!=null&&((java.sql.Timestamp)r.get("lease_until")).toInstant().isAfter(java.time.Instant.now()))return;
  }else{
   if(r.get("next_attempt_at")==null||((java.sql.Timestamp)r.get("next_attempt_at")).toInstant().isAfter(java.time.Instant.now()))return;
   if(status.equals("FAILED")&&db.update("UPDATE provider_sync_run SET automatic_retries=automatic_retries+1 WHERE id=? AND automatic_retries<1",r.get("id"))!=1)return;
  }
  try{sync.synchronize(status.equals("COMPLETE")?null:(UUID)r.get("id"));}catch(RuntimeException ignored){/* persisted run status; preserve current dataset */}
 }
}
