package com.eroute;
import com.eroute.personalization.*;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static com.eroute.personalization.ReferenceData.*;

class MappingScopeTest {
 final com.fasterxml.jackson.databind.ObjectMapper json=ReferenceJson.mapper();
 ReferenceData synthetic(String status){return new ReferenceDomainTest().synthetic(status);}
 @Test void legacyScopeIsOptionalButOtherFieldsRemainRequired()throws Exception {
  var old=new FileReferenceRepository(DiseaseReference.RESOURCE).read();
  assertTrue(old.mappings().stream().allMatch(m->m.mappingScope()==null));
  var node=(ObjectNode)json.valueToTree(synthetic("DRAFT").mappings().getFirst());
  node.remove("mappingScope");
  assertNull(json.treeToValue(node,Mapping.class).mappingScope());
  assertFalse(json.valueToTree(json.treeToValue(node,Mapping.class)).has("mappingScope"));
  node.putNull("mappingScope");assertNull(json.treeToValue(node,Mapping.class).mappingScope());
  node.put("mappingScope","UNKNOWN");assertThrows(Exception.class,()->json.treeToValue(node,Mapping.class));
  node.put("mappingScope",4);assertThrows(Exception.class,()->json.treeToValue(node,Mapping.class));
  node.remove("mappingScope");node.remove("evidence");assertThrows(Exception.class,()->json.treeToValue(node,Mapping.class));
 }
 @Test void scopeChangeRequiresNewVersionAndDraft()throws Exception {
  var old=synthetic("APPROVED");var next=(ObjectNode)json.valueToTree(old);next.put("datasetVersion","next");
  var m=(ObjectNode)next.path("mappings").get(0);m.put("mappingScope","BROAD_PARENT");
  assertThrows(Exception.class,()->ReferenceValidator.transition(old,json.treeToValue(next,ReferenceData.class)));
  m.put("version",2).put("reviewStatus","DRAFT").putNull("approval");
  ReferenceValidator.transition(old,json.treeToValue(next,ReferenceData.class));
 }
 @Test void newDirectApprovalRequiresScopeButLegacyCanStillBeRead()throws Exception {
  var draft=(ObjectNode)json.valueToTree(synthetic("DRAFT"));((ObjectNode)draft.path("mappings").get(0)).remove("mappingScope");
  var approved=(ObjectNode)json.valueToTree(synthetic("APPROVED"));approved.put("datasetVersion","next");((ObjectNode)approved.path("mappings").get(0)).remove("mappingScope");
  ReferenceValidator.validate(json.treeToValue(approved,ReferenceData.class));
  assertThrows(Exception.class,()->ReferenceValidator.transition(json.treeToValue(draft,ReferenceData.class),json.treeToValue(approved,ReferenceData.class)));
  assertEquals(MappingScope.EXACT_CANONICAL,synthetic("APPROVED").published().mappings().getFirst().mappingScope());
 }
 @Test void currentPublicHashAndCountsRemainUnchanged() {
  var r=new DiseaseReference();assertEquals("9c63436bd3b07cbde6fb33068e981c4a9d5d7806c227f28ebc87000a7fab12e6",r.response().sha256());
  assertTrue(new FileReferenceRepository(DiseaseReference.RESOURCE).read().published().mappings().isEmpty());
 }
}
