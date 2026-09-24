package com.eroute;
import com.eroute.personalization.*;
import com.eroute.memberhealth.ConditionEntries;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.*;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class DiseaseCatalogTest {
 JsonNode seed(){return new DiseaseCatalog().response("test-mapping");}
 @Test void seedIdentityCategoriesAndConservativeAliases(){
  var c=new DiseaseCatalog();var j=seed();assertEquals(46,j.path("diseases").size());assertEquals(14,j.path("categories").size());
  var v=new FileReferenceRepository("reference/disease-departments/v0.5.json").read();
  for(var d:v.diseases()){assertTrue(c.known(d.id()));assertEquals(d.displayName(),c.name(d.id()));}
  for(var m:v.mappings())assertTrue(c.known(m.diseaseId()));
  assertEquals("D018",c.exact(" 고지혈증 "));assertEquals("D002",c.exact(" coPD "));assertEquals("D002",c.exact("만성 폐쇄성 폐질환"));assertNull(c.exact("혈압문제"));
 }
 @Test void futureDiseaseWithoutMappingAndCategoryWorks(){
  var j=(ObjectNode)seed();((ArrayNode)j.path("categories")).addObject().put("id","CAT_FUTURE").put("name","테스트 분류").put("sortOrder",999);
  var d=((ArrayNode)j.path("diseases")).addObject().put("id","D047").put("canonicalName","테스트질환").put("categoryId","CAT_FUTURE").put("active",true);d.putArray("aliases").add("TEST047");
  var c=new DiseaseCatalog(j);assertEquals(47,c.response("mapping").path("diseases").size());assertEquals("D047",c.exact("test047"));
  assertEquals(List.of("D047"),ConditionEntries.ids(ConditionEntries.validate(List.of(Map.of("type","STANDARD","diseaseId","D047")),c,List.of())));
  assertFalse(new DiseaseReference().known("D047"));
 }
 @Test void rejectsAliasCollisionInvalidCategoryAndDuplicateId(){
  var j=seed();((ArrayNode)j.path("diseases").get(1).path("aliases")).add("천 식");assertThrows(IllegalArgumentException.class,()->new DiseaseCatalog(j));
  var bad=seed();((ObjectNode)bad.path("diseases").get(0)).put("categoryId","missing");assertThrows(IllegalArgumentException.class,()->new DiseaseCatalog(bad));
  var dup=seed();((ArrayNode)dup.path("diseases")).add(dup.path("diseases").get(0));assertThrows(IllegalArgumentException.class,()->new DiseaseCatalog(dup));
 }
 @Test void migrationIsExactDeduplicatedAndNeverSplitsOrFuzzes(){
  var c=new DiseaseCatalog();assertEquals(List.of("D018"),ConditionEntries.ids(ConditionEntries.migrate(List.of("D018"),"고지혈증",c)));
  for(String text:List.of("심장이 좀 안좋음","고혈압, 천식","  혈압문제\n기관지가 약함  "))assertEquals(text,ConditionEntries.freeText(ConditionEntries.migrate(List.of(),text,c)));
  assertEquals(1,ConditionEntries.validate(List.of(Map.of("type","CUSTOM","customName"," A  B "),Map.of("type","CUSTOM","customName","a b")),c,List.of()).size());
  assertEquals("고지혈증",ConditionEntries.freeText(ConditionEntries.validate(List.of(Map.of("type","CUSTOM","customName","고지혈증")),c,List.of())));
 }
 @Test void inactiveCanBeRetainedButNotNewlySelected(){
  var j=seed();((ObjectNode)j.path("diseases").get(0)).put("active",false);((ArrayNode)j.path("quickPickDiseaseIds")).removeAll();var c=new DiseaseCatalog(j);
  var input=List.of(Map.of("type","STANDARD","diseaseId","D001"));assertThrows(RuntimeException.class,()->ConditionEntries.validate(input,c,List.of()));assertEquals(1,ConditionEntries.validate(input,c,List.of("D001")).size());
 }
}
