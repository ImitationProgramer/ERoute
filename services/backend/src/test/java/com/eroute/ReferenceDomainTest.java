package com.eroute;

import com.eroute.personalization.*;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.util.*;
import static com.eroute.personalization.ReferenceData.*;

class ReferenceDomainTest {
 final ObjectMapper json=new ObjectMapper();
 ReferenceData seed(){return new FileReferenceRepository("reference/disease-departments/v0.2.json").read();}
 ReferenceData synthetic(String status){
  var e=new Evidence("Synthetic test only","https://example.invalid/test","2026-09-17T00:00:00Z","TEST_DEPARTMENT","Not clinical evidence");
  var m=new Mapping("TEST_MAPPING","TEST_DISEASE","TEST_DEPARTMENT","DIRECT",status,List.of(e),status.equals("APPROVED")?new Approval("synthetic reviewer","2026-09-17T01:00:00Z",1):null,1,MappingScope.EXACT_CANONICAL);
  return new ReferenceData(2,"test-v1","test-catalog","test-vocabulary","TEST_PURPOSE","test-purpose","READY",false,
   List.of(new Disease("TEST_DISEASE","테스트 질환",List.of("synthetic"),"test",true,"ACTIVE",1)),
   List.of(new Department("TEST_DEPARTMENT","TEST_DEPARTMENT",true,1)),List.of(m),List.of(),List.of());
 }
 @Test void sixteenSeedsFiftyOneLiteralDepartmentsAndZeroApprovalsAreValid()throws Exception{
  var data=seed();ReferenceValidator.validate(data);assertEquals(16,data.diseases().size());assertEquals(51,data.departments().size());assertTrue(data.mappings().isEmpty());
  var publicData=json.readValue(new DiseaseReference().response().document(),ReferenceData.class);assertFalse(publicData.publicMapApproved());assertEquals(new FileReferenceRepository(DiseaseReference.RESOURCE).read().published(),publicData);
  var fixture=json.readTree(java.nio.file.Path.of("../../contracts/fixtures/department-coverage-2026-09-17.json").toFile());
  var names=new HashSet<String>();fixture.path("summary").path("normalizedFrequencies").fieldNames().forEachRemaining(names::add);
  assertEquals(names,new HashSet<>(data.departments().stream().map(Department::canonicalName).toList()));
 }
 @Test void publicationOnlyIncludesHumanApprovedRowsAndNeverPromotesDrafts(){
  var draft=synthetic("DRAFT");ReferenceValidator.validate(draft);assertTrue(draft.published().mappings().isEmpty());
  var approved=synthetic("APPROVED");ReferenceValidator.validate(approved);assertEquals(1,approved.published().mappings().size());
 }
 @Test void approvalMustBindVersionAndCompleteEvidence()throws Exception{
  var n=(ObjectNode)json.valueToTree(synthetic("APPROVED"));var m=(ObjectNode)n.path("mappings").get(0);
  m.put("version",2);assertThrows(IllegalArgumentException.class,()->DiseaseReference.validate(n));
  m.put("version",1);((ObjectNode)m.path("evidence").get(0)).putNull("sourceUrl");assertThrows(IllegalArgumentException.class,()->DiseaseReference.validate(n));
 }
 @Test void newDiseaseNeedsNoMappingAndRetirementPreservesIdentity()throws Exception{
  var n=(ObjectNode)json.valueToTree(seed());n.put("datasetVersion","next");n.put("catalogVersion","next-catalog");
  ((ArrayNode)n.path("diseases")).addObject().put("id","D017").put("displayName","기록용 테스트 항목").put("category","test").put("active",true).put("lifecycleStatus","ACTIVE").put("version",1).putArray("aliases");
  ReferenceValidator.transition(seed(),json.treeToValue(n,ReferenceData.class));
  ((ObjectNode)n.path("diseases").get(0)).put("active",false).put("lifecycleStatus","RETIRED").put("version",2);
  ReferenceValidator.transition(seed(),json.treeToValue(n,ReferenceData.class));
  ((ArrayNode)n.path("diseases")).remove(0);assertThrows(Exception.class,()->ReferenceValidator.transition(seed(),json.treeToValue(n,ReferenceData.class)));
 }
 @Test void relationChangesMustReturnToDraftAndCannotReuseId()throws Exception{
  var old=synthetic("APPROVED");var n=(ObjectNode)json.valueToTree(old);n.put("datasetVersion","test-v2");var m=(ObjectNode)n.path("mappings").get(0);
  m.put("relationType","CONTEXTUAL");assertThrows(IllegalArgumentException.class,()->ReferenceValidator.transition(old,json.treeToValue(n,ReferenceData.class)));
  m.put("version",2).put("reviewStatus","DRAFT").putNull("approval");ReferenceValidator.transition(old,json.treeToValue(n,ReferenceData.class));
  m.put("priority","PRIMARY");assertThrows(Exception.class,()->json.treeToValue(n,ReferenceData.class));
 }
 @Test void strictAdapterRejectsMissingFlagsAndApprovalCannotSkipDraft()throws Exception{
  var n=(ObjectNode)json.valueToTree(seed());n.remove("publicMapApproved");assertThrows(IllegalArgumentException.class,()->DiseaseReference.validate(n));
  var draft=synthetic("DRAFT");var approved=synthetic("APPROVED");var next=(ObjectNode)json.valueToTree(approved);next.put("datasetVersion","test-v2");
  ReferenceValidator.transition(draft,json.treeToValue(next,ReferenceData.class));
  var blank=(ObjectNode)json.valueToTree(draft);blank.putArray("mappings");
  assertThrows(IllegalArgumentException.class,()->ReferenceValidator.transition(json.treeToValue(blank,ReferenceData.class),json.treeToValue(next,ReferenceData.class)));
 }
 @Test void aliasEvidenceChangesRevokeApprovalAndIdentityCannotBeRedirected()throws Exception{
  var n=(ObjectNode)json.valueToTree(synthetic("DRAFT"));var alias=((ArrayNode)n.path("departmentAliases")).addObject();
  alias.put("alias","TEST_ALIAS").put("departmentId","TEST_DEPARTMENT").put("reviewStatus","DRAFT").put("version",1).putNull("approval");alias.set("evidence",n.path("mappings").get(0).path("evidence").get(0).deepCopy());
  var draft=json.treeToValue(n,ReferenceData.class);n.put("datasetVersion","alias-v2");n.put("vocabularyVersion","alias-v2");alias.put("reviewStatus","APPROVED");alias.set("approval",json.valueToTree(new Approval("synthetic reviewer","2026-09-17T01:00:00Z",1)));
  var approved=json.treeToValue(n,ReferenceData.class);ReferenceValidator.transition(draft,approved);
  n.put("datasetVersion","alias-v3");n.put("vocabularyVersion","alias-v3");((ObjectNode)alias.path("evidence")).put("notes","changed synthetic evidence");assertThrows(IllegalArgumentException.class,()->ReferenceValidator.transition(approved,json.treeToValue(n,ReferenceData.class)));
  alias.put("version",2).put("reviewStatus","DRAFT").putNull("approval");ReferenceValidator.transition(approved,json.treeToValue(n,ReferenceData.class));
 }

}
