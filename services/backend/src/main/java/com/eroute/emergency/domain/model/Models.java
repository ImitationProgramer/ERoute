package com.eroute.emergency.domain.model;
import java.time.*;
import java.util.*;
public final class Models {
 private Models(){}
 public enum Coverage { LIVE_AVAILABLE, LIVE_NOT_PROVIDED, LIVE_ERROR, LIVE_UNKNOWN }
 public enum Refresh { UPDATED, CACHE_HIT, BUDGET_DEFERRED, IN_PROGRESS, ERROR, NOT_REQUESTED }
 public enum Interpretation { KNOWN, NOT_PROVIDED, MISSING, UNKNOWN_CODE, UNVERIFIED }
 public enum Acceptance { AVAILABLE, UNAVAILABLE, NOT_PROVIDED, UNKNOWN }
 public enum FetchStatus { NOT_REQUESTED, SUCCESS, ERROR }
 public enum CenterSource { GPS, MANUAL }
 public record Point(double latitude,double longitude) {
  public Point { if(!Double.isFinite(latitude)||!Double.isFinite(longitude)||latitude < -90||latitude>90||longitude< -180||longitude>180) throw new IllegalArgumentException("Invalid coordinates"); }
 }
 public record Region(String id,String stage1,String stage2) {}
 public record Hospital(String hpid,String name,String classCode,String className,String address,
  Point location,String mainPhone,String secondaryPhone,Region region) {}
 public record HospitalMaster(Hospital hospital,Instant updatedAt,Instant catalogFetchedAt,String catalogVersion) {}
 public record ContactNumber(String sourceField,String officialLabel,String rawValue) {}
 public record ClinicHours(String dayCode,String startRaw,String closeRaw,Interpretation interpretationStatus) {}
 public record HospitalBasicInfo(FetchStatus fetchStatus,String departmentsRaw,List<ClinicHours> clinicHours,
  String sourceRawTimestamp,String parsedSourceTimestamp,Instant fetchedAt,Instant lastAttemptAt,String error,
  String dataStatus,Refresh refreshStatus,BasicModels.Status departmentsStatus,List<BasicModels.Department> departments,
  List<BasicModels.OperatingHours> operatingHours,boolean stale,List<String> staleReasons,String datasetVersion) {
  public HospitalBasicInfo(FetchStatus fetchStatus,String departmentsRaw,List<ClinicHours> clinicHours,String sourceRawTimestamp,String parsedSourceTimestamp,Instant fetchedAt,Instant lastAttemptAt,String error){
   this(fetchStatus,departmentsRaw,clinicHours,sourceRawTimestamp,parsedSourceTimestamp,fetchedAt,lastAttemptAt,error,"NOT_COLLECTED",Refresh.NOT_REQUESTED,BasicModels.Status.MISSING,List.of(),List.of(),false,List.of(),null);
  }
 }
 public record ResourceValue(String endpoint,String sourceField,String officialLabel,String rawValue,
  Long numericValue,Interpretation interpretationStatus) {}
 public record SourceTime(String sourceRawTimestamp,String parsedSourceTimestamp,String sourceTimezone,
  String sourceTimestampStatus,Instant sourceUpdatedAt) {}
 public record Freshness(SourceTime source,Instant fetchedAt,Instant lastAttemptAt,boolean stale,
  List<String> staleReasons,String sourceFreshness) {}
 public record Realtime(Coverage coverageStatus,Refresh refreshStatus,ResourceValue availableBeds,
  List<ResourceValue> referenceResources,Freshness freshness,String error) {}
 public record CurrentHospitalObservation(Coverage coverageStatus,Refresh refreshStatus,RawItem item,
  Instant fetchedAt,Instant lastAttemptAt,String error) {}
 public record NearbyHospital(String hpid,String name,Map<String,String> emergencyClass,Point location,
  long distanceFromCenterMeters,Long distanceFromUserMeters,Realtime realtime) {}
 public record HospitalDetail(String hpid,String name,Map<String,String> emergencyClass,String address,Point location,
  ContactNumber mainPhone,ContactNumber secondaryPhone,Instant masterUpdatedAt,String catalogVersion,
  Instant catalogFetchedAt,boolean catalogStale,Realtime realtime,HospitalBasicInfo basicInfo,Instant generatedAt) {}
 public record Catalog(List<Hospital> hospitals,Instant fetchedAt,String version) {}
 public record SearchRequest(Point center,CenterSource centerSource,Point userLocation,Integer radiusMeters) {}
 public record SearchMeta(Point center,CenterSource centerSource,List<Integer> attemptedRadiiMeters,
  int effectiveRadiusMeters,boolean expanded,Instant generatedAt,String catalogVersion,
  Instant catalogFetchedAt,boolean catalogStale,String realtimeStatus,int totalCount,List<String> warnings) {}
 public record SearchResponse(SearchMeta meta,List<NearbyHospital> hospitals) {}
 public record Bounds(Point southWest,Point northEast) {}
 public record MapConfig(List<Integer> radiusStepsMeters,int defaultRadiusMeters,boolean automaticRefreshEnabled,
  Bounds coverageBounds,String configVersion) {}
 public record CapabilityObservation(String endpoint,String field,String rawValue,Acceptance status,
  Interpretation interpretationStatus,FetchStatus fetchStatus) {}
 public record HospitalMessage(String hpid,String endpoint,Map<String,List<String>> rawFields) {}
 public record RawItem(Map<String,List<String>> fields) {
  public RawItem { var copy=new LinkedHashMap<String,List<String>>(); fields.forEach((k,v)->copy.put(k,List.copyOf(v))); fields=Collections.unmodifiableMap(copy); }
  public String single(String key){var v=fields.get(key);return v!=null&&v.size()==1?v.getFirst():null;}
 }
 public record Page(int pageNo,int numOfRows,int totalCount,List<RawItem> items,String rawXml,Instant fetchedAt) {}
 public record Batch(List<RawItem> items,Instant fetchedAt,List<Long> responseIds) {}
 public record RegionObservation(Batch batch,Refresh refresh,Instant attemptedAt,String error) {}
}
