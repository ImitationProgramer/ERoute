package com.eroute.emergency.infrastructure.scheduling;
import com.eroute.common.config.ERouteProperties;
import com.eroute.emergency.application.HospitalCatalogSyncService;
import java.sql.Timestamp;
import java.time.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
@Component
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(name="eroute.jobs-enabled",havingValue="true",matchIfMissing=true)
public class MaintenanceJobs {
 private final JdbcTemplate db;private final ERouteProperties config;private final HospitalCatalogSyncService sync;private final TransactionTemplate tx;
 public MaintenanceJobs(JdbcTemplate db,ERouteProperties config,HospitalCatalogSyncService sync,PlatformTransactionManager tm){this.db=db;this.config=config;this.sync=sync;tx=new TransactionTemplate(tm);}
 // Catalog only. There is deliberately no scheduled real-time regional poller.
 @Scheduled(initialDelayString="PT1H",fixedDelayString="PT1H")
 public void catalog(){
  var last=db.query("SELECT max(started_at) FROM provider_sync_run WHERE endpoint='getEgytListInfoInqire'",(rs,n)->rs.getTimestamp(1));
  if(!last.isEmpty()&&last.getFirst()!=null&&last.getFirst().toInstant().plus(config.masterTtl()).isAfter(Instant.now()))return;
  if(Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM discovery_result WHERE passed AND endpoint='getEgytListInfoInqire')",Boolean.class)))try{sync.synchronize();}catch(RuntimeException ignored){/* Sync failure is persisted; the last catalog stays available. */}
 }
 @Scheduled(initialDelayString="PT1H",fixedDelayString="PT24H")
 public void retain(){tx.executeWithoutResult(s->{
  Timestamp cutoff=Timestamp.from(Instant.now().minus(Duration.ofDays(config.rawRetentionDays())));
  db.update("""
   DELETE FROM hospital_realtime_snapshot old WHERE old.fetched_at<?
    AND old.id NOT IN (SELECT DISTINCT ON(hpid) id FROM hospital_realtime_snapshot ORDER BY hpid,fetched_at DESC,id DESC)
    AND old.id NOT IN (SELECT snapshot_id FROM hospital_observation WHERE snapshot_id IS NOT NULL)
   """,cutoff);
  // Keep current/previous datasets and every unfinished run, including carried-forward snapshots.
  db.update("""
   DELETE FROM hospital_basic_info_dataset_member m USING provider_sync_run r
   WHERE m.run_id=r.id AND r.status IN ('COMPLETE','SUPERSEDED') AND r.started_at<?
   AND NOT EXISTS(SELECT 1 FROM hospital_basic_info_state s WHERE s.current_run_id=r.id OR s.previous_run_id=r.id)
   """,cutoff);
  db.update("""
   DELETE FROM hospital_basic_info_snapshot b USING provider_sync_run r
   WHERE b.sync_run_id=r.id AND r.status IN ('COMPLETE','SUPERSEDED') AND b.fetched_at<?
   AND NOT EXISTS(SELECT 1 FROM hospital_basic_info_dataset_member m WHERE m.snapshot_id=b.id)
   """,cutoff);
  db.update("""
   DELETE FROM provider_sync_work w USING provider_sync_run r
   WHERE w.run_id=r.id AND r.status IN ('COMPLETE','SUPERSEDED') AND r.started_at<?
   AND NOT EXISTS(SELECT 1 FROM hospital_basic_info_state s WHERE s.current_run_id=r.id OR s.previous_run_id=r.id)
   """,cutoff);
  db.update("""
   DELETE FROM provider_response r WHERE r.fetched_at<?
    AND r.id NOT IN (SELECT jsonb_array_elements_text(response_ids)::bigint FROM hospital_realtime_snapshot)
    AND r.id NOT IN (SELECT jsonb_array_elements_text(batch_json->'responseIds')::bigint FROM region_cache WHERE batch_json IS NOT NULL)
    AND r.id NOT IN (SELECT jsonb_array_elements_text(details->'responseIds')::bigint FROM provider_sync_run WHERE id=(SELECT version FROM catalog_state))
    AND NOT EXISTS(SELECT 1 FROM hospital_basic_info_snapshot b WHERE b.provider_response_id=r.id)
    AND NOT EXISTS(SELECT 1 FROM hospital_basic_info_dataset_member m WHERE m.response_id=r.id)
    AND NOT EXISTS(SELECT 1 FROM provider_sync_work w WHERE w.response_id=r.id)
    AND r.scope NOT LIKE 'DISCOVERY:%'
   """,cutoff);
  db.update("DELETE FROM nmc_call_attempt WHERE requested_at<?",cutoff);
 });}
}
