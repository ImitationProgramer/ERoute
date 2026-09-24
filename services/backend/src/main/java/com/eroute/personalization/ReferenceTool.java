package com.eroute.personalization;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** Offline, read-only validation/coverage. Never writes approvals, files, DBs or calls providers. */
public final class ReferenceTool {
 public static void main(String[] args) throws Exception {
  if(args.length<1||args.length>3)throw new IllegalArgumentException("reference.json [previous.json|-] [public-hospital-fixture.json]");
  var json=ReferenceJson.mapper();var data=json.readValue(Files.readAllBytes(Path.of(args[0])),ReferenceData.class);ReferenceValidator.validate(data);
  if(args.length>1&&!args[1].equals("-"))ReferenceValidator.transition(json.readValue(Files.readAllBytes(Path.of(args[1])),ReferenceData.class),data);
  var document=json.writeValueAsString(data.published());var report=new LinkedHashMap<String,Object>();
  report.put("referenceVersion",data.datasetVersion());report.put("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(document.getBytes(StandardCharsets.UTF_8))));
  report.put("activeDiseases",data.diseases().stream().filter(d->d.active()).count());report.put("departments",data.departments().size());
  var eligible=data.mappings().stream().filter(m->m.reviewStatus().equals("APPROVED")&&m.relationType().equals("DIRECT")&&data.diseases().stream().anyMatch(d->d.id().equals(m.diseaseId())&&d.active())&&data.departments().stream().anyMatch(d->d.id().equals(m.departmentId())&&d.active())).toList();
  report.put("approvedDirectMappings",eligible.size());report.put("approvedDiseases",eligible.stream().map(m->m.diseaseId()).distinct().count());
  report.put("approvedMappings",data.mappings().stream().filter(m->m.reviewStatus().equals("APPROVED")).count());
  report.put("publicMappings",data.published().mappings().size());
  long publicDrafts=data.published().mappings().stream().filter(m->!m.reviewStatus().equals("APPROVED")).count();
  if(publicDrafts!=0)throw new IllegalStateException("UNAPPROVED_PUBLIC_MAPPING");
  report.put("publicDraftMappings",publicDrafts);
  report.put("draftMappings",data.mappings().stream().filter(m->m.reviewStatus().equals("DRAFT")).count());
  if(args.length==3){
   var fixture=json.readTree(Files.readAllBytes(Path.of(args[2])));var counts=new LinkedHashMap<String,Integer>();var union=new HashSet<String>();
   var departmentNames=new HashMap<String,String>();data.departments().forEach(d->departmentNames.put(d.id(),ReferenceValidator.key(d.canonicalName())));
   var aliases=new HashMap<String,String>();data.departmentAliases().stream().filter(a->a.reviewStatus().equals("APPROVED")).forEach(a->aliases.put(ReferenceValidator.key(a.alias()),departmentNames.get(a.departmentId())));
   for(var d:data.diseases())if(d.active()){
    var required=new HashSet<String>();eligible.stream().filter(m->m.diseaseId().equals(d.id())).forEach(m->required.add(departmentNames.get(m.departmentId())));int count=0;
    for(var h:fixture.path("hospitals"))if(h.path("active").asBoolean()){
     boolean match=false;for(var t:h.path("departments"))if(t.path("interpretationStatus").asText().equals("KNOWN")){
      String name=ReferenceValidator.key(t.path("name").asText());if(required.contains(aliases.getOrDefault(name,name)))match=true;
     }if(match){count++;union.add(h.path("hpid").asText());}
    }counts.put(d.id(),count);
   }report.put("nameCoverageOnly",counts);report.put("matchableDiseases",counts.values().stream().filter(n->n>0).count());report.put("uniqueMatchingHospitals",union.size());
  }
  System.out.println(json.writerWithDefaultPrettyPrinter().writeValueAsString(report));
 }
}
