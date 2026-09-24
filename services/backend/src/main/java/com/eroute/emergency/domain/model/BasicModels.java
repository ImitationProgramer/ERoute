package com.eroute.emergency.domain.model;
import java.util.*;
public final class BasicModels {
 private BasicModels(){}
 public record BasicFetchedPage(Models.Page page,long responseId){}
 public enum Status { KNOWN, MISSING, NOT_PROVIDED, UNPARSEABLE, UNVERIFIED }
 public enum Day { MON,TUE,WED,THU,FRI,SAT,SUN,HOLIDAY }
 public enum Presence { MISSING, EMPTY, NIL, TEXT, STRUCTURED, MULTIPLE }
 public record RawValue(String value,Presence presence,Map<String,String> attributes) {}
 public record RawBasicItem(Map<String,List<RawValue>> fields) {
  public RawBasicItem {var copy=new LinkedHashMap<String,List<RawValue>>();fields.forEach((k,v)->copy.put(k,List.copyOf(v)));fields=Collections.unmodifiableMap(copy);}
  public RawValue cell(String field){var values=fields.get(field);if(values==null||values.isEmpty())return new RawValue(null,Presence.MISSING,Map.of());if(values.size()!=1)return new RawValue(null,Presence.MULTIPLE,Map.of());return values.getFirst();}
 }
 public record Department(int ordinal,String name,String rawValue,String source,Status interpretationStatus){}
 public record OperatingHours(Day day,String open,String close,String rawOpenValue,String rawCloseValue,
  Presence openPresence,Presence closePresence,Status openStatus,Status closeStatus,Status status,String source){}
 public record NormalizedBasic(String rawDepartmentText,Status departmentsStatus,List<Department> departments,List<OperatingHours> operatingHours){}
}
