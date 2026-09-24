package com.eroute.emergency.infrastructure.nmc;
import com.eroute.emergency.domain.model.BasicModels.*;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class NmcBasicInfoNormalizer {
 public static final String VERSION="basic-v1";
 private final Set<String> names=new HashSet<>(),notProvided=new HashSet<>(),specialTimes=new HashSet<>();
 public NmcBasicInfoNormalizer(JsonCodec json){
  try(var in=new org.springframework.core.io.ClassPathResource("nmc/codebooks/v13/codebook.json").getInputStream()){
   var policy=json.mapper().readTree(in).path("endpoints").path(NmcBasicInfoDiscoveryProbe.ENDPOINT).path("normalization");
   if(!VERSION.equals(policy.path("version").asText())||!",".equals(policy.path("departmentDelimiter").asText()))throw new IllegalStateException("Basic policy not verified");
   policy.path("departmentNames").forEach(n->names.add(n.asText()));policy.path("notProvidedValues").forEach(n->notProvided.add(n.asText()));policy.path("unverifiedTimeValues").forEach(n->specialTimes.add(n.asText()));
  }catch(Exception e){throw new IllegalStateException("Basic codebook unavailable",e);}
 }
 private Status initial(RawValue cell){
  if(cell.presence()==Presence.MULTIPLE||cell.presence()==Presence.STRUCTURED)return Status.UNVERIFIED;
  if(cell.value()==null||cell.value().isBlank())return Status.MISSING;
  if(notProvided.contains(cell.value()))return Status.NOT_PROVIDED;
  return Status.KNOWN;
 }
 private record TimeValue(String normalized,Status status){}
 private TimeValue time(RawValue cell){
  Status s=initial(cell);String v=cell.value();if(s!=Status.KNOWN)return new TimeValue(null,s);
  if(specialTimes.contains(v))return new TimeValue(null,Status.UNVERIFIED);
  if(!v.matches("[0-9]{4}"))return new TimeValue(null,Status.UNPARSEABLE);
  int hour=Integer.parseInt(v.substring(0,2)),minute=Integer.parseInt(v.substring(2));
  if(hour>23||minute>59)return new TimeValue(null,Status.UNPARSEABLE);
  return new TimeValue(v.substring(0,2)+":"+v.substring(2),Status.KNOWN);
 }
 public NormalizedBasic normalize(RawBasicItem item){
  RawValue raw=item.cell("dgidIdName");Status status=initial(raw);var departments=new ArrayList<Department>();
  if(status==Status.KNOWN){
   String[] tokens=raw.value().split(",",-1);boolean any=false;
   for(int i=0;i<tokens.length;i++){
    String name=tokens[i].strip();if(name.isEmpty())continue;any=true;boolean known=names.contains(name);
    departments.add(new Department(i,known?name:null,tokens[i],"NMC",known?Status.KNOWN:Status.UNVERIFIED));if(!known)status=Status.UNVERIFIED;
   }
   if(!any)status=Status.UNVERIFIED;
  }
  var hours=new ArrayList<OperatingHours>();
  for(var day:Day.values()){
   int n=day.ordinal()+1;var start=item.cell("dutyTime"+n+"s");var end=item.cell("dutyTime"+n+"c");var open=time(start);var close=time(end);Status row;
   if(open.status()==Status.KNOWN&&close.status()==Status.KNOWN)row=open.normalized().compareTo(close.normalized())<0?Status.KNOWN:Status.UNVERIFIED;
   else if(open.status()==Status.UNVERIFIED||close.status()==Status.UNVERIFIED)row=Status.UNVERIFIED;
   else if(open.status()==Status.UNPARSEABLE||close.status()==Status.UNPARSEABLE)row=Status.UNPARSEABLE;
   else if(open.status()==Status.KNOWN||close.status()==Status.KNOWN)row=Status.UNVERIFIED;
   else row=open.status()==Status.NOT_PROVIDED||close.status()==Status.NOT_PROVIDED?Status.NOT_PROVIDED:Status.MISSING;
   hours.add(new OperatingHours(day,open.normalized(),close.normalized(),start.value(),end.value(),start.presence(),end.presence(),open.status(),close.status(),row,"NMC"));
  }
  return new NormalizedBasic(raw.value(),status,List.copyOf(departments),List.copyOf(hours));
 }
}
