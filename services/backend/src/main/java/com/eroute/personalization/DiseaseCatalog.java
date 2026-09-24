package com.eroute.personalization;

import com.fasterxml.jackson.databind.*;
import java.text.Normalizer;
import java.util.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/** Recordable identities, independent of clinical relationship publication. */
@Component
public class DiseaseCatalog {
 public static final String RESOURCE="reference/diseases/catalog.json";
 private final JsonNode data;
 private final Map<String,JsonNode> diseases=new LinkedHashMap<>();
 private final Map<String,String> names=new HashMap<>();
 public DiseaseCatalog(){this(read());}
 private static JsonNode read(){try(var in=new ClassPathResource(RESOURCE).getInputStream()){return new ObjectMapper().readTree(in);}catch(Exception e){throw new IllegalArgumentException("INVALID_DISEASE_CATALOG",e);}}
 public DiseaseCatalog(JsonNode source){
  data=source.deepCopy(); required(data,"catalogVersion");
  require(data.path("categories").isArray()&&data.path("diseases").isArray()&&data.path("quickPickDiseaseIds").isArray());
  Set<String> categories=new HashSet<>();
  for(var c:data.path("categories")){require(categories.add(required(c,"id")));required(c,"name");require(c.path("sortOrder").isIntegralNumber());}
  for(var d:data.path("diseases")){
   String id=required(d,"id");require(diseases.putIfAbsent(id,d)==null);require(categories.contains(required(d,"categoryId")));
   require(d.path("active").isBoolean()&&d.path("aliases").isArray());index(required(d,"canonicalName"),id);
   for(var alias:d.path("aliases")){require(alias.isTextual()&&!alias.asText().isBlank());index(alias.asText(),id);}
  }
  require(!diseases.isEmpty());Set<String> quick=new HashSet<>();
  for(var id:data.path("quickPickDiseaseIds"))require(id.isTextual()&&active(id.asText())&&quick.add(id.asText()));
 }
 private static void require(boolean value){if(!value)throw new IllegalArgumentException("INVALID_DISEASE_CATALOG");}
 private static String required(JsonNode n,String key){require(n.path(key).isTextual()&&!n.path(key).asText().isBlank());return n.path(key).asText();}
 public static String normalize(String value){return Normalizer.normalize(value,Normalizer.Form.NFC).replaceAll("[\\s\\p{Z}]+","").toLowerCase(Locale.ROOT);}
 private void index(String name,String id){String key=normalize(name);require(!key.isEmpty());String old=names.putIfAbsent(key,id);require(old==null||old.equals(id));}
 public String version(){return data.path("catalogVersion").asText();}
 public boolean known(String id){return diseases.containsKey(id);}
 public boolean active(String id){return known(id)&&diseases.get(id).path("active").asBoolean();}
 public String name(String id){return known(id)?diseases.get(id).path("canonicalName").asText():id;}
 public String exact(String raw){String id=names.get(normalize(raw));return id!=null&&active(id)?id:null;}
 public JsonNode response(String mappingVersion){var out=(com.fasterxml.jackson.databind.node.ObjectNode)data.deepCopy();out.put("mappingDatasetVersion",mappingVersion);return out;}
}
