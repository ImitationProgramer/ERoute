package com.eroute.memberhealth;

import static com.eroute.auth.AuthData.problem;
import com.eroute.personalization.DiseaseCatalog;
import java.text.Normalizer;
import java.util.*;

/** Conservative record migration; never infers a department or splits prose. */
public final class ConditionEntries {
 private ConditionEntries(){}
 public static String customKey(String s){return Normalizer.normalize(s,Normalizer.Form.NFC).strip().replaceAll("[\\s\\p{Z}]+"," ").toLowerCase(Locale.ROOT);}
 public static List<Map<String,Object>> validate(Object value,DiseaseCatalog catalog,List<?> retained){
  if(!(value instanceof List<?> rows)||rows.size()>100)throw problem("INVALID_HEALTH_INPUT",400);
  var result=new ArrayList<Map<String,Object>>();Set<String> seen=new HashSet<>();
  for(var valueRow:rows){
   if(!(valueRow instanceof Map<?,?> row))throw problem("INVALID_HEALTH_INPUT",400);
   if("STANDARD".equals(row.get("type"))){
    if(!Set.of("type","diseaseId","displayName").containsAll(row.keySet())||!(row.get("diseaseId") instanceof String id)||!catalog.known(id)||(!catalog.active(id)&&!retained.contains(id)))throw problem("INVALID_DISEASE_SELECTION",400);
    if(seen.add("S:"+id))result.add(Map.of("type","STANDARD","diseaseId",id,"displayName",catalog.name(id)));
   }else if("CUSTOM".equals(row.get("type"))){
    if(!Set.of("type","customName").containsAll(row.keySet())||!(row.get("customName") instanceof String raw)||raw.isBlank()||raw.length()>2000)throw problem("INVALID_HEALTH_INPUT",400);
    if(seen.add("C:"+customKey(raw)))result.add(Map.of("type","CUSTOM","customName",raw));
   }else throw problem("INVALID_HEALTH_INPUT",400);
  }
  if(freeText(result).length()>2000)throw problem("INVALID_HEALTH_INPUT",400);
  return List.copyOf(result);
 }
 public static List<String> ids(List<Map<String,Object>> entries){return entries.stream().filter(e->e.get("type").equals("STANDARD")).map(e->(String)e.get("diseaseId")).toList();}
 public static String freeText(List<Map<String,Object>> entries){return String.join("\n",entries.stream().filter(e->e.get("type").equals("CUSTOM")).map(e->(String)e.get("customName")).toList());}
 public static List<Map<String,Object>> migrate(List<?> ids,String raw,DiseaseCatalog catalog){
  var rows=new ArrayList<Map<String,Object>>();
  for(Object id:ids)rows.add(Map.of("type","STANDARD","diseaseId",id));
  if(!raw.isBlank()){String exact=catalog.exact(raw);rows.add(exact==null?Map.of("type","CUSTOM","customName",raw):Map.of("type","STANDARD","diseaseId",exact));}
  return validate(rows,catalog,ids);
 }
}
