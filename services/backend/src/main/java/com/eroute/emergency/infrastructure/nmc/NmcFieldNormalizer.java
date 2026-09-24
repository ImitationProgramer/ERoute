package com.eroute.emergency.infrastructure.nmc;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.*;
import java.time.format.*;
import java.util.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
@Component
public class NmcFieldNormalizer implements com.eroute.emergency.domain.port.ResourceInterpreter {
 public ResourceValue availableBeds(RawItem item){return value(BEDS,"hvec",item);}
 public List<ResourceValue> referenceResources(RawItem item){return List.of(value(BEDS,"HVS01",item));}
 public static final String BEDS="getEmrrmRltmUsefulSckbdInfoInqire";
 public static final String LIST="getEgytListInfoInqire";
 private final JsonNode book;
 public NmcFieldNormalizer(JsonCodec json){
  try(var in=new ClassPathResource("nmc/codebooks/v13/codebook.json").getInputStream()){book=json.mapper().readTree(in);}
  catch(Exception e){throw new IllegalStateException("NMC codebook unavailable");}
 }
 private JsonNode definition(String endpoint,String field){
  for(var f:book.path("endpoints").path(endpoint).path("fields")){
   if(f.path("name").asText().equals(field))return f;
   for(var a:f.path("aliases"))if(a.asText().equals(field))return f;
  }return null;
 }
 public ResourceValue value(String endpoint,String canonical,RawItem item){
  JsonNode def=definition(endpoint,canonical);String actual=canonical,raw=null;int matches=0;
  if(item!=null){
   var names=new ArrayList<String>();names.add(canonical);
   if(def!=null){names.clear();names.add(def.path("name").asText());def.path("aliases").forEach(a->names.add(a.asText()));}
   for(String name:names){var values=item.fields().get(name);if(values!=null){matches+=values.size();actual=name;raw=values.isEmpty()?null:values.getFirst();}}
  }
  String label=def==null?canonical:def.path("officialLabel").asText();
  Interpretation state;Long number=null;
  if(matches==0)state=Interpretation.MISSING;
  else if(matches!=1)state=Interpretation.UNVERIFIED;
  else if(raw==null||raw.isBlank())state=Interpretation.MISSING;
  else if(raw.strip().equals("정보미제공"))state=Interpretation.NOT_PROVIDED;
  else if(raw.strip().equals("N1"))state=Interpretation.UNKNOWN_CODE;
  else if(def==null||!def.path("semanticStatus").asText().equals("VERIFIED"))state=Interpretation.UNVERIFIED;
  else if(def.path("kind").asText().equals("INTEGER")){
   try{if(!raw.strip().matches("-?[0-9]+"))throw new NumberFormatException();number=Long.parseLong(raw.strip());state=number<0?Interpretation.UNVERIFIED:Interpretation.KNOWN;}
   catch(NumberFormatException e){state=Interpretation.UNVERIFIED;}
  }else state=Interpretation.UNVERIFIED;
  return new ResourceValue(endpoint,actual,label,raw,number,state);
 }
 public SourceTime timestamp(String raw){
  if(raw==null||raw.isBlank())return new SourceTime(raw,null,null,"MISSING",null);
  for(String pattern:List.of("uuuuMMddHHmmss","uuuu-MM-dd HH:mm:ss","uuuu-MM-dd a h:mm:ss","uuuu-MM-dd ah:mm:ss")){
   try{var format=DateTimeFormatter.ofPattern(pattern,Locale.KOREAN).withResolverStyle(ResolverStyle.STRICT);
    return new SourceTime(raw,LocalDateTime.parse(raw.strip(),format).toString(),null,"TIMEZONE_UNVERIFIED",null);
   }catch(DateTimeException ignored){}
  }return new SourceTime(raw,null,null,"UNPARSEABLE",null);
 }
 public CapabilityObservation capability(String endpoint,String field,String raw){
  JsonNode def=definition(endpoint,field);String normalized=raw==null?null:raw.strip();
  if(normalized==null||normalized.isEmpty())return new CapabilityObservation(endpoint,field,raw,Acceptance.UNKNOWN,Interpretation.MISSING,FetchStatus.SUCCESS);
  if(def==null)return new CapabilityObservation(endpoint,field,raw,Acceptance.UNKNOWN,Interpretation.UNVERIFIED,FetchStatus.SUCCESS);
  String value=def.path("codes").path(normalized).asText("");
  if(value.isEmpty())return new CapabilityObservation(endpoint,field,raw,Acceptance.UNKNOWN,Interpretation.UNKNOWN_CODE,FetchStatus.SUCCESS);
  return new CapabilityObservation(endpoint,field,raw,Acceptance.valueOf(value),value.equals("NOT_PROVIDED")?Interpretation.NOT_PROVIDED:Interpretation.KNOWN,FetchStatus.SUCCESS);
 }
}
