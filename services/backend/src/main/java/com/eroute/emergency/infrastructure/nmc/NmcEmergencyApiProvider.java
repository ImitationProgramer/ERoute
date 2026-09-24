package com.eroute.emergency.infrastructure.nmc;
import com.eroute.common.config.ERouteProperties;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.port.EmergencyHospitalProvider;
import com.eroute.emergency.infrastructure.persistence.JdbcHospitalStore;
import java.time.*;
import java.util.*;
import java.util.concurrent.Semaphore;
import org.springframework.stereotype.Component;
@Component
public class NmcEmergencyApiProvider implements EmergencyHospitalProvider {
 private final JdbcHospitalStore store;private final NmcPageCollector collector;private final ERouteProperties config;private final Clock clock;private final Semaphore permits;private final NmcRegionResolver regions;
 public NmcEmergencyApiProvider(JdbcHospitalStore store,NmcPageCollector collector,ERouteProperties config,Clock clock,NmcRegionResolver regions){this.regions=regions;this.store=store;this.collector=collector;this.config=config;this.clock=clock;permits=new Semaphore(config.maxConcurrency());}
 public RegionObservation fetchRealtimeBeds(Region region){
  return fetchRealtimeBeds(region,System.nanoTime()+config.refreshDeadline().toNanos());
 }
 @Override public RegionObservation fetchRealtimeBeds(Region region,long deadlineNanos){
  Instant started=clock.instant();
  Batch previous=store.lastComplete(region.id()).orElse(null);Instant last=store.lastAttemptAt(region.id());
  if(previous!=null&&previous.fetchedAt().plus(config.realtimeTtl()).isAfter(clock.instant()))return new RegionObservation(previous,Refresh.CACHE_HIT,last,null);
  UUID owner=UUID.randomUUID();
  if(!store.acquireLease(region.id(),owner))return new RegionObservation(previous,Refresh.IN_PROGRESS,last,"REFRESH_IN_PROGRESS");
  boolean acquired=false,realtimePhase=false;
  try{
   permits.acquire();acquired=true;
   // Recheck after lease acquisition: another request may just have completed.
   previous=store.lastComplete(region.id()).orElse(previous);
   if(previous!=null&&previous.fetchedAt().plus(config.realtimeTtl()).isAfter(clock.instant()))return new RegionObservation(previous,Refresh.CACHE_HIT,store.lastAttemptAt(region.id()),null);
   regions.verify(region,collector,deadlineNanos);
   Region request=regions.requestRegion(region,NmcFieldNormalizer.BEDS);
   realtimePhase=true;
   Batch batch=collector.collect(NmcFieldNormalizer.BEDS,region.id(),Map.of("STAGE1",request.stage1(),"STAGE2",request.stage2()),100,deadlineNanos);
   store.complete(region.id(),batch,owner);return new RegionObservation(batch,Refresh.UPDATED,store.lastAttemptAt(region.id()),null);
  }catch(InterruptedException e){Thread.currentThread().interrupt();return new RegionObservation(previous,realtimePhase?Refresh.ERROR:Refresh.NOT_REQUESTED,last,realtimePhase?"REQUEST_DEADLINE":"REGION_MAPPING_ERROR");}
  catch(ServiceProblem e){
   boolean deferred=e.code().equals("CALL_BUDGET_LIMIT")||e.code().equals("CALL_RATE_LIMIT");
   String code=deferred||realtimePhase?e.code():"REGION_MAPPING_ERROR";
   Instant attempted=store.lastAttemptAt(region.id());
   boolean requested=attempted!=null&&!attempted.isBefore(started);
   // Deadline/cancellation before admission is not a failed provider call.
   boolean notStarted=!deferred&&realtimePhase&&!requested;
   if(notStarted)code="REQUEST_NOT_STARTED";
   org.slf4j.LoggerFactory.getLogger(getClass()).warn("region_refresh region={} stage1={} stage2={} phase={} cause={} error={}",region.id(),region.stage1(),region.stage2(),realtimePhase?"REALTIME":"VALIDATION",e.code(),code);
   store.markError(region.id(),code);return new RegionObservation(previous,deferred?Refresh.BUDGET_DEFERRED:realtimePhase&&!notStarted?Refresh.ERROR:Refresh.NOT_REQUESTED,attempted,code);
  }finally{if(acquired)permits.release();store.releaseLease(region.id(),owner);}
 }
}
