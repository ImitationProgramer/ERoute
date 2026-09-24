package com.eroute;
import com.eroute.personalization.DiseaseReference;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class DiseaseReferenceTest {
 final ObjectMapper json=new ObjectMapper();
 JsonNode document() throws Exception{try(var in=getClass().getResourceAsStream("/reference/disease-departments/v0.1.json")){return json.readTree(in);}}
 @Test void suppliedDraftIsCompleteAndHasNoInventedEvidence() throws Exception {
  var d=document();assertEquals(16,d.path("diseases").size());assertEquals(31,d.path("aliases").size());assertEquals(17,d.path("departments").size());assertEquals(30,d.path("mappings").size());
  for(String type:new String[]{"DIRECT","CONTEXTUAL","REVIEW_REQUIRED"}) {int count=0;for(var m:d.path("mappings")){if(m.path("relationType").asText().equals(type))count++;assertEquals("DRAFT",m.path("reviewStatus").asText());}assertEquals(type.equals("DIRECT")?24:type.equals("CONTEXTUAL")?5:1,count);}
  for(var e:d.path("evidence")){assertTrue(e.path("sourceUrl").isNull());assertTrue(e.path("checkedAt").isNull());}
  assertFalse(d.path("publicMapApproved").asBoolean());assertEquals(0,d.path("departmentAliases").size());assertTrue(new DiseaseReference().active("D001"));assertFalse(new DiseaseReference().active("UNKNOWN"));
 }
 @Test void malformedReferencesAndAliasCollisionsFailClosed() throws Exception {
  var d=document();((ObjectNode)d).put("publicMapApproved",true);assertThrows(IllegalArgumentException.class,()->DiseaseReference.validate(d));
  var dangling=document();((ObjectNode)dangling.path("mappings").get(0)).put("departmentId","absent");assertThrows(IllegalArgumentException.class,()->DiseaseReference.validate(dangling));
  var collision=document();var a=((ArrayNode)collision.path("aliases")).addObject();a.put("diseaseId","D003").put("alias","asthma").put("normalizedAlias","asthma");assertThrows(IllegalArgumentException.class,()->DiseaseReference.validate(collision));
  var relation=document();((ObjectNode)relation.path("mappings").get(0)).put("relationType","contains");assertThrows(IllegalArgumentException.class,()->DiseaseReference.validate(relation));
  assertEquals("copd",DiseaseReference.normalizedAlias(" COPD "));
 }
}
