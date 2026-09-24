package com.eroute.emergency.application;
import com.eroute.common.config.ERouteProperties;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.policy.GeoDistance;
import com.eroute.emergency.domain.port.*;

import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.springframework.stereotype.Service;
@Service
public class EmergencyHospitalService {
 private final HospitalRepository hospitals;private final HospitalObservationRepository observations;
 private final EmergencyHospitalProvider provider;private final ResourceInterpreter normalizer;
 private final ERouteProperties config;private final Clock clock;private final ExecutorService executor;
 public EmergencyHospitalService(HospitalRepository hospitals,HospitalObservationRepository observations,EmergencyHospitalProvider provider,ResourceInterpreter normalizer,ERouteProperties config,Clock clock,ExecutorService executor){
  this.hospitals=hospitals;this.observations=observations;this.provider=provider;this.normalizer=normalizer;this.config=config;this.clock=clock;this.executor=executor;
 }
 public MapConfig mapConfig(){
  var catalog=hospitals.catalog();Bounds bounds=null;
  if(catalog.isPresent()&&!catalog.get().hospitals().isEmpty()){
   var rows=catalog.get().hospitals();
   bounds=new Bounds(new Point(rows.stream().mapToDouble(h->h.location().latitude()).min().orElseThrow(),rows.stream().mapToDouble(h->h.location().longitude()).min().orElseThrow()),
    new Point(rows.stream().mapToDouble(h->h.location().latitude()).max().orElseThrow(),rows.stream().mapToDouble(h->h.location().longitude()).max().orElseThrow()));
  }
  return new MapConfig(config.radiusSteps(),config.radiusSteps().getFirst(),false,bounds,"v0.1");
 }
 public SearchResponse search(SearchRequest request){
  if(request==null||request.center()==null||request.centerSource()==null)throw new IllegalArgumentException("Search center required");
  int initial=request.radiusMeters()==null?config.radiusSteps().getFirst():request.radiusMeters();
  if(!config.radiusSteps().contains(initial))throw new IllegalArgumentException("Unsupported radius");
  Catalog catalog=hospitals.catalog().orElseThrow(()->new ServiceProblem("CATALOG_NOT_READY"));
  var attempted=new ArrayList<Integer>();List<Hospital> candidates=List.of();
  for(int radius:config.radiusSteps())if(radius>=initial){
   attempted.add(radius);candidates=catalog.hospitals().stream().filter(h->GeoDistance.meters(request.center(),h.location())<=radius).toList();
   if(!candidates.isEmpty())break;
  }
  Instant searchStarted=clock.instant();
  long deadline=System.nanoTime()+config.refreshDeadline().toNanos();
  var tasks=new LinkedHashMap<String,Future<RegionObservation>>();
  for(Hospital h:candidates)if(h.region()!=null)tasks.computeIfAbsent(h.region().id(),id->executor.submit(()->provider.fetchRealtimeBeds(h.region(),deadline)));
  var results=new HashMap<String,RegionObservation>();
  for(var task:tasks.entrySet()){
   try{long remaining=deadline-System.nanoTime();if(remaining<=0&&!task.getValue().isDone())throw new TimeoutException();results.put(task.getKey(),task.getValue().get(Math.max(0,remaining),TimeUnit.NANOSECONDS));}
   catch(Exception e){
    task.getValue().cancel(true);Instant regionAttempted=observations.lastAttemptAt(task.getKey());
    boolean requested=regionAttempted!=null&&!regionAttempted.isBefore(searchStarted);
    results.put(task.getKey(),new RegionObservation(observations.lastComplete(task.getKey()).orElse(null),requested?Refresh.ERROR:Refresh.NOT_REQUESTED,regionAttempted,e instanceof TimeoutException?"REQUEST_DEADLINE":"REFRESH_FAILED"));
   }
  }
  var warnings=new TreeSet<String>();var rows=new ArrayList<NearbyHospital>();
  for(Hospital h:candidates){
   RegionObservation observation=h.region()==null?new RegionObservation(null,Refresh.NOT_REQUESTED,null,"REGION_MAPPING_ERROR"):results.get(h.region().id());
   if(observation.error()!=null)warnings.add(observation.error());
   Realtime realtime=present(h.hpid(),observation);
   var classification=new LinkedHashMap<String,String>();classification.put("code",h.classCode());classification.put("name",h.className());
   rows.add(new NearbyHospital(h.hpid(),h.name(),classification,h.location(),Math.round(GeoDistance.meters(request.center(),h.location())),request.userLocation()==null?null:Math.round(GeoDistance.meters(request.userLocation(),h.location())),realtime));
  }
  rows.sort(Comparator.comparingLong(NearbyHospital::distanceFromCenterMeters).thenComparing(NearbyHospital::hpid));
  String status=warnings.isEmpty()?"COMPLETE":!rows.isEmpty()&&rows.stream().allMatch(h->h.realtime().coverageStatus()==Coverage.LIVE_ERROR)?"ERROR":"PARTIAL";
  return new SearchResponse(new SearchMeta(request.center(),request.centerSource(),attempted,attempted.getLast(),attempted.size()>1,clock.instant(),catalog.version(),catalog.fetchedAt(),catalog.fetchedAt().plus(config.masterTtl()).isBefore(clock.instant()),status,rows.size(),List.copyOf(warnings)),List.copyOf(rows));
 }
 public Realtime present(String hpid,RegionObservation observation){
  Batch batch=observation.batch();RawItem item=batch==null?null:batch.items().stream().filter(i->hpid.equals(i.single("hpid")==null?null:i.single("hpid").strip())).findFirst().orElse(null);
  Coverage coverage=batch==null?Coverage.LIVE_UNKNOWN:item==null?Coverage.LIVE_NOT_PROVIDED:Coverage.LIVE_AVAILABLE;
  return present(new CurrentHospitalObservation(coverage,observation.refresh(),item,batch==null?null:batch.fetchedAt(),observation.attemptedAt(),observation.error()));
 }
 public Realtime present(CurrentHospitalObservation observation){
  RawItem item=observation.item();
  Coverage coverage=observation.refreshStatus()==Refresh.ERROR?Coverage.LIVE_ERROR:observation.coverageStatus();
  var reasons=new ArrayList<String>();
  if(observation.fetchedAt()!=null&&!observation.fetchedAt().plus(config.realtimeTtl()).isAfter(clock.instant()))reasons.add("CACHE_EXPIRED");
  if(observation.error()!=null)reasons.add(observation.error());
  if(observation.fetchedAt()==null)reasons.add("NO_SNAPSHOT");
  var source=normalizer.timestamp(item==null?null:item.single("hvidate"));
  var fresh=new Freshness(source,observation.fetchedAt(),observation.lastAttemptAt(),!reasons.isEmpty(),List.copyOf(reasons),"UNKNOWN");
  return new Realtime(coverage,observation.refreshStatus(),normalizer.availableBeds(item),normalizer.referenceResources(item),fresh,observation.error());
 }
}
