package com.eroute.personalization;

import com.eroute.common.error.ServiceProblem;
import com.fasterxml.jackson.databind.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.text.Normalizer;
import java.util.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/** Sole authoritative disease reference. Failure disables this capability only. */
@Component
public class DiseaseReference {
 public static final String RESOURCE="reference/disease-departments/v0.4.json";
 private JsonNode data;
 private ReferenceResponse response;
 private final String sourceResource;
 public record ReferenceResponse(String document,String sha256) {}
 public DiseaseReference() {
  this(RESOURCE);
 }
 public DiseaseReference(String resource) {
  sourceResource=resource;
  try {load(new ObjectMapper().writeValueAsBytes(new FileReferenceRepository(resource).read()));}
  catch(Exception ignored){data=null;response=null;}
 }
 public DiseaseReference(byte[] bytes) {sourceResource=null;load(bytes);}
 public String sourceResource(){return sourceResource;}
 private void load(byte[] bytes) {
  try {
   var mapper=new ObjectMapper();var node=mapper.readTree(bytes);validate(node);
   if(node.path("schemaVersion").asInt()==2){bytes=mapper.writeValueAsBytes(mapper.treeToValue(node,ReferenceData.class).published());node=mapper.readTree(bytes);}
   response=new ReferenceResponse(new String(bytes,StandardCharsets.UTF_8),HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)));
   data=node;
  }catch(Exception e){throw new IllegalArgumentException("INVALID_DISEASE_REFERENCE");}
 }
 public ReferenceResponse response(){available();return response;}
 public String version(){available();return data.path("datasetVersion").asText();}
 public String catalogVersion(){available();return data.path("catalogVersion").asText(version());}
 public String purpose(){available();return data.path("purpose").asText();}
 public String purposeVersion(){available();return data.path("purposeVersion").asText();}
 public boolean availableNow(){return data!=null;}
 private void available(){if(data==null)throw new ServiceProblem("DISEASE_REFERENCE_UNAVAILABLE");}
 public boolean known(String id){available();for(var d:data.path("diseases"))if(d.path("id").asText().equals(id))return true;return false;}
 public boolean active(String id){available();for(var d:data.path("diseases"))if(d.path("id").asText().equals(id))return d.path("active").asBoolean();return false;}
 public static String normalizedAlias(String value){return Normalizer.normalize(value.strip(),Normalizer.Form.NFC).toLowerCase(Locale.ROOT);}
 private static void require(boolean yes){if(!yes)throw new IllegalArgumentException();}
 private static String text(JsonNode n,String key){require(n.path(key).isTextual()&&!n.path(key).asText().isBlank());return n.path(key).asText();}
 private static Set<String> ids(JsonNode root,String key){require(root.path(key).isArray());Set<String> ids=new HashSet<>();for(var n:root.path(key))require(ids.add(text(n,"id")));return ids;}
 public static void validate(JsonNode n){
  if(n.path("schemaVersion").asInt()==2){try{ReferenceValidator.validate(ReferenceJson.mapper().treeToValue(n,ReferenceData.class));return;}catch(Exception e){throw new IllegalArgumentException("INVALID_DISEASE_REFERENCE");}}
  require(n.path("schemaVersion").asInt()==1);text(n,"datasetVersion");text(n,"purpose");text(n,"purposeVersion");
  // This implementation cannot publish a draft (or a future reference) to maps.
  require(n.path("status").asText().equals("DRAFT")&&n.path("publicMapApproved").isBoolean()&&!n.path("publicMapApproved").asBoolean());
  var diseases=ids(n,"diseases");var departments=ids(n,"departments");var mappings=ids(n,"mappings");
  require(!diseases.isEmpty()&&!departments.isEmpty()&&!mappings.isEmpty());
  Map<String,String> aliasOwners=new HashMap<>();Set<String> names=new HashSet<>();
  for(var d:n.path("diseases")){text(d,"rawName");require(d.path("active").isBoolean()&&d.path("version").asInt()>0);String name=normalizedAlias(text(d,"canonicalName"));require(aliasOwners.putIfAbsent(name,text(d,"id"))==null);}
  for(var d:n.path("departments"))require(names.add(text(d,"canonicalName")));
  require(n.path("aliases").isArray());Set<String> aliasRows=new HashSet<>();
  for(var a:n.path("aliases")){String id=text(a,"diseaseId"),alias=normalizedAlias(text(a,"alias"));require(diseases.contains(id)&&alias.equals(text(a,"normalizedAlias"))&&aliasRows.add(id+"|"+alias));var prior=aliasOwners.putIfAbsent(alias,id);require(prior==null||prior.equals(id));}
  Set<String> pairs=new HashSet<>();
  for(var m:n.path("mappings")){require(diseases.contains(text(m,"diseaseId"))&&departments.contains(text(m,"departmentId")));require(pairs.add(m.path("diseaseId").asText()+"|"+m.path("departmentId").asText()));text(m,"rawDepartmentName");require(Set.of("DIRECT","CONTEXTUAL","REVIEW_REQUIRED").contains(text(m,"relationType")));require(text(m,"reviewStatus").equals("DRAFT")&&m.path("version").asInt()>0);}
  require(n.path("evidence").isArray());Set<String> evidenced=new HashSet<>();
  for(var e:n.path("evidence")){String id=text(e,"mappingId");require(mappings.contains(id));evidenced.add(id);text(e,"sourceName");text(e,"rawDepartmentText");require(e.has("sourceUrl")&&e.has("checkedAt"));}
  require(evidenced.equals(mappings));
  require(n.path("departmentAliases").isArray());Set<String> deptAliases=new HashSet<>();
  for(var a:n.path("departmentAliases")){require(departments.contains(text(a,"departmentId")));require(text(a,"reviewStatus").equals("REVIEWED"));require(deptAliases.add(text(a,"alias")));text(a,"sourceName");text(a,"checkedAt");}
  text(n.path("uncertaintyPolicy"),"version");require(n.path("uncertaintyPolicy").path("broadDepartmentNames").isArray());
 }
}
