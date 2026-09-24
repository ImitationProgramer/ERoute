package com.eroute;

import com.eroute.auth.AuthSettings;
import com.eroute.personalization.*;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.stream.Collectors;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class DiseaseEvidenceV05Test {
 private static final String BASE="reference/disease-departments/";
 private static final String QA="../../docs/qa/disease-evidence-v05-2026-09-19/source-matrix/";
 private static String sha(byte[] value) throws Exception {
  return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
 }
 @Test void sourceEvidenceAndScopeRoundTripWithoutIdentityOrApprovalChanges() throws Exception {
  var prior=new FileReferenceRepository(BASE+"v0.4.json").read();
  var next=new FileReferenceRepository(BASE+"v0.5.json").read();
  ReferenceValidator.transition(prior,next);
  assertEquals("32a5f98da61178b882a940ea061a55e981febb0900d995ec88356d31b8dadd84",sha(Files.readAllBytes(Path.of("src/main/resources/"+BASE+"v0.4.json"))));
  var matrixBytes=Files.readAllBytes(Path.of(QA+"eroute-disease-source-matrix-v05.json"));
  assertEquals("309eacdbb321c63883ee88ef589a35e78fdd80454c87ff3f66874ed41a874eee",sha(matrixBytes));
  var stamped=ReferenceJson.mapper().readTree(Files.readString(Path.of(QA+"eroute-disease-source-matrix-v05-reviewed.json")));
  String checked=stamped.path("humanCheckedAtUtc").asText();
  assertNotEquals(stamped.path("researchVerifiedAtUtc").asText(),checked);
  assertEquals("HUMAN_SOURCE_REVIEW",stamped.path("humanSignoffStatus").asText());
  assertEquals(prior.diseases(),next.diseases());assertEquals(46,next.diseases().size());
  assertEquals(prior.departments(),next.departments());assertEquals(51,next.departments().size());
  assertEquals(prior.catalogVersion(),next.catalogVersion());assertEquals(prior.vocabularyVersion(),next.vocabularyVersion());assertEquals(prior.purposeVersion(),next.purposeVersion());
  assertEquals(61,next.mappings().size());
  assertEquals(36,next.mappings().stream().filter(m->m.mappingScope()==ReferenceData.MappingScope.EXACT_CANONICAL).count());
  assertEquals(25,next.mappings().stream().filter(m->m.mappingScope()==ReferenceData.MappingScope.BROAD_PARENT).count());
  var supplied=new HashMap<String,com.fasterxml.jackson.databind.JsonNode>();
  for(var m:stamped.path("mappings")) supplied.put(m.path("mappingId").asText(),m);
  for(int i=0;i<61;i++){
   var old=prior.mappings().get(i);var m=next.mappings().get(i);var row=supplied.get(m.id());
   assertEquals(old.id(),m.id());assertEquals(old.diseaseId(),m.diseaseId());assertEquals(old.departmentId(),m.departmentId());assertEquals(old.version()+1,m.version());
   assertEquals("DRAFT",m.reviewStatus());assertNull(m.approval());
   assertEquals(m.mappingScope()==ReferenceData.MappingScope.BROAD_PARENT?2:1,m.evidence().size());
   for(int e=0;e<m.evidence().size();e++){
    var evidence=m.evidence().get(e);var input=row.path(e==0?"diseaseEvidence":"parentStructureEvidence");
    assertEquals(input.path("sourceUrl").asText(),evidence.sourceUrl());assertEquals(input.path("rawDepartmentText").asText(),evidence.rawDepartmentText());
    assertEquals(checked,evidence.checkedAt());assertTrue(evidence.notes().contains("HUMAN_SOURCE_REVIEW"));
   }
  }
  assertEquals(next,ReferenceJson.mapper().readValue(ReferenceJson.mapper().writeValueAsBytes(next),ReferenceData.class));
 }
 @Test void v05PublicHttpSerializationHasAllCatalogButNoEvidenceOrDraftLeak() throws Exception {
  var reference=new DiseaseReference(BASE+"v0.5.json");
  var mvc=MockMvcBuilders.standaloneSetup(new DiseaseReferenceController(reference)).build();
  var response=mvc.perform(get("/api/v1/reference/disease-departments")).andExpect(status().isOk()).andReturn().getResponse();
  var envelope=ReferenceJson.mapper().readTree(response.getContentAsString(StandardCharsets.UTF_8));
  String document=envelope.path("document").asText();
  assertEquals(sha(document.getBytes(StandardCharsets.UTF_8)),envelope.path("sha256").asText());
  var published=ReferenceJson.mapper().readValue(document,ReferenceData.class);
  assertEquals("eroute-disease-departments-v0.5",published.datasetVersion());
  assertEquals(46,published.diseases().size());assertEquals(51,published.departments().size());
  assertTrue(published.mappings().isEmpty());assertFalse(published.publicMapApproved());
  assertFalse(document.contains("HUMAN_SOURCE_REVIEW"));assertFalse(document.contains("amc.seoul.kr"));
  assertEquals(new DiseaseReference().response().sha256(),"9c63436bd3b07cbde6fb33068e981c4a9d5d7806c227f28ebc87000a7fab12e6");
 }
 @Test void candidatePreviewPreservesEveryReviewClassDespite36ExactScopes() throws Exception {
  Class<?> type;try{type=Class.forName("com.eroute.personalization.DiseaseReviewPreviewController");}catch(ClassNotFoundException e){return;}
  var settings=new AuthSettings(new MockEnvironment().withProperty("eroute.auth.environment","test"));
  var constructor=type.getConstructor(AuthSettings.class,DiseaseReference.class);
  var json=ReferenceJson.mapper();
  var old=json.valueToTree(type.getMethod("get").invoke(constructor.newInstance(settings,new DiseaseReference(BASE+"v0.4.json"))));
  var next=json.valueToTree(type.getMethod("get").invoke(constructor.newInstance(settings,new DiseaseReference(BASE+"v0.5.json"))));
  assertEquals("eroute-disease-departments-v0.5",next.path("referenceVersion").asText());
  var counts=new HashMap<String,Integer>();
  for(int i=0;i<61;i++){
   var a=old.path("mappings").get(i);var b=next.path("mappings").get(i);
   for(String key:List.of("id","diseaseId","departmentId","relationType","reviewStatus","reviewClass"))assertEquals(a.path(key),b.path(key));
   assertEquals(a.path("version").asInt()+1,b.path("version").asInt());
   assertTrue(b.hasNonNull("mappingScope"));assertFalse(b.has("evidence"));
   counts.merge(b.path("reviewClass").asText(),1,Integer::sum);
  }
  assertEquals(Map.of("EXACT_CANONICAL_REVIEW_REQUIRED",6,"REVIEW_REQUIRED",30,"BROAD_PARENT_REVIEW_REQUIRED",25),counts);
 }
}
