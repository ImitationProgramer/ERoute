package com.eroute;

import com.eroute.personalization.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.stream.Collectors;
import java.io.*;

class DiseaseEvidenceV04Test {
 private static final String BASE="reference/disease-departments/";
 @Test void immutableTransitionPreservesCatalogAndEveryBatchTwoMapping() throws Exception {
  var previous=new FileReferenceRepository(BASE+"v0.3.json").read();
  var current=new FileReferenceRepository(DiseaseReference.RESOURCE).read();
  ReferenceValidator.transition(previous,current);
  assertEquals("7cc3a615c8128b29703ad14ce8e6e2250bed4384e430648f32c8031270633fbd",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(Path.of("src/main/resources/"+BASE+"v0.3.json")))));
  assertEquals("eroute-disease-departments-v0.4",current.datasetVersion());
  assertEquals(previous.diseases(),current.diseases());assertEquals(previous.departments(),current.departments());
  assertEquals(previous.catalogVersion(),current.catalogVersion());assertEquals(previous.vocabularyVersion(),current.vocabularyVersion());
  assertEquals(previous.purposeVersion(),current.purposeVersion());assertEquals(previous.departmentAliases(),current.departmentAliases());
  assertEquals(previous.mappings(),current.mappings().subList(0,43));
  var added=current.mappings().subList(43,current.mappings().size());assertEquals(18,added.size());
  var names=current.departments().stream().collect(Collectors.toMap(d->d.id(),d->d.canonicalName()));
  String[] supplied="내과|내과|내과,가정의학과|내과|내과|내과|내과,가정의학과|내과|내과|신경과|신경과|피부과|피부과|내과|내과|내과".split("\\|");
  for(int i=0;i<supplied.length;i++){
   String id="D%03d".formatted(i+1);
   assertEquals(Set.of(supplied[i].split(",")),added.stream().filter(m->m.diseaseId().equals(id)).map(m->names.get(m.departmentId())).collect(Collectors.toSet()));
  }
  var legacy=ReferenceJson.mapper().readTree(Files.readAllBytes(Path.of("src/main/resources/"+BASE+"v0.1.json")));
  var legacyIds=new HashSet<String>();legacy.path("mappings").forEach(m->legacyIds.add(m.path("id").asText()));
  assertTrue(added.stream().noneMatch(m->legacyIds.contains(m.id())));
  assertEquals(61,current.mappings().size());
  assertTrue(current.mappings().stream().allMatch(m->m.reviewStatus().equals("DRAFT")&&m.relationType().equals("DIRECT")&&m.version()==1&&m.approval()==null&&m.evidence().isEmpty()));
 }
 @Test void worksheetCoversEveryRelationWithoutInventingEvidence() throws Exception {
  var json=ReferenceJson.mapper();var current=new FileReferenceRepository(DiseaseReference.RESOURCE).read();
  var worksheet=json.readTree(Files.readAllBytes(Path.of("../../docs/qa/disease-evidence-v04-2026-09-18/review-inputs.json")));
  assertEquals("NON_RUNTIME_REVIEW_WORKSHEET",worksheet.path("documentType").asText());
  assertEquals(current.datasetVersion(),worksheet.path("referenceVersion").asText());
  var rows=new HashMap<String,com.fasterxml.jackson.databind.JsonNode>();var classes=new HashMap<String,Integer>();
  for(var row:worksheet.path("mappings")){
   assertNull(rows.put(row.path("mappingId").asText(),row));
   classes.merge(row.path("reviewClass").asText(),1,Integer::sum);
   assertEquals("MISSING",row.path("evidenceStatus").asText());
   for(String field:List.of("sourceName","sourceUrl","checkedAt","rawDepartmentText","notes"))assertTrue(row.path("evidenceInput").path(field).isNull());
   for(String field:List.of("sourceRetrieved","directCanonicalOrBroadParentReviewed","clinicalScopeReviewed","evidenceComplete"))assertEquals(json.valueToTree(false),row.path("humanChecklist").path(field));
  }
  assertEquals(Map.of("BROAD_PARENT_REVIEW_REQUIRED",25,"EXACT_CANONICAL_REVIEW_REQUIRED",6,"REVIEW_REQUIRED",30),classes);
  assertEquals(current.mappings().size(),rows.size());
  for(var m:current.mappings()){
   var row=rows.get(m.id());assertNotNull(row);
   assertEquals(m.diseaseId(),row.path("diseaseId").asText());assertEquals(m.departmentId(),row.path("departmentId").asText());
   assertEquals(m.version(),row.path("mappingVersion").asInt());assertEquals(m.reviewStatus(),row.path("reviewStatus").asText());assertEquals(m.relationType(),row.path("relationType").asText());
   assertEquals(current.diseases().stream().filter(d->d.id().equals(m.diseaseId())).findFirst().orElseThrow().displayName(),row.path("diseaseDisplayName").asText());
   assertEquals(current.departments().stream().filter(d->d.id().equals(m.departmentId())).findFirst().orElseThrow().canonicalName(),row.path("departmentCanonicalName").asText());
  }
  var prior=json.readTree(Files.readAllBytes(Path.of("../../docs/qa/disease-catalog-batch2-2026-09-18/review-inputs.json")));
  for(var row:prior.path("mappings"))row.fields().forEachRemaining(e->assertEquals(e.getValue(),rows.get(row.path("mappingId").asText()).path(e.getKey())));
 }
 @Test void runtimeProjectionHasAllTagsButNoUnreviewedMapping() throws Exception {
  var reference=new DiseaseReference();var response=reference.response();
  var published=ReferenceJson.mapper().readValue(response.document(),ReferenceData.class);
  assertEquals("eroute-disease-departments-v0.4",reference.version());
  assertEquals(46,published.diseases().stream().filter(d->d.active()).count());assertEquals(51,published.departments().size());
  assertTrue(published.mappings().isEmpty());assertFalse(published.publicMapApproved());
  for(int i=1;i<=46;i++)assertTrue(reference.active("D%03d".formatted(i)));
 }
 @Test void coverageIsZeroWithDynamicDenominatorAndNoHospitalMatches() throws Exception {
  var original=System.out;var bytes=new ByteArrayOutputStream();
  try{System.setOut(new PrintStream(bytes));ReferenceTool.main(new String[]{"src/main/resources/"+BASE+"v0.4.json","src/main/resources/"+BASE+"v0.3.json","../../contracts/fixtures/department-coverage-2026-09-17.json"});}finally{System.setOut(original);}
  var report=ReferenceJson.mapper().readTree(bytes.toByteArray());
  assertEquals(46,report.path("activeDiseases").asInt());assertEquals(61,report.path("draftMappings").asInt());
  for(String key:List.of("approvedMappings","approvedDiseases","approvedDirectMappings","publicMappings","publicDraftMappings","uniqueMatchingHospitals"))assertEquals(0,report.path(key).asInt(-1));
  assertEquals(report.path("activeDiseases").asInt(),report.path("nameCoverageOnly").size());
 }
}
