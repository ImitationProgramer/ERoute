package com.eroute;

import com.eroute.personalization.*;
import com.fasterxml.jackson.databind.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.stream.*;
import java.io.*;

class DiseaseBatch2Test {
 final String base="reference/disease-departments/";
 final ObjectMapper json=ReferenceJson.mapper();
 @Test void preservesImmutableSeedAndAddsExactlyUserSuppliedCandidates()throws Exception{
  var previous=new FileReferenceRepository(base+"v0.2.json").read();var current=new FileReferenceRepository(base+"v0.3.json").read();
  ReferenceValidator.transition(previous,current);
  assertEquals("edc21c2f9c7216a55eb8b59b3572572191237e231eb78362e4d8b40c7022176e",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(Path.of("src/main/resources/"+base+"v0.2.json")))));
  assertEquals(previous.diseases(),current.diseases().subList(0,previous.diseases().size()));assertEquals(previous.departments(),current.departments());
  var added=current.diseases().subList(previous.diseases().size(),current.diseases().size());
  assertEquals(IntStream.rangeClosed(17,46).mapToObj(i->"D%03d".formatted(i)).toList(),added.stream().map(d->d.id()).toList());
  assertTrue(added.stream().allMatch(d->d.active()&&d.lifecycleStatus().equals("ACTIVE")&&d.version()==1&&d.category().equals("기저질환")));
  String[] expected="내과,가정의학과|내과,가정의학과|내과|내과|내과|내과|내과|내과|내과|내과|내과,재활의학과|신경과|신경과,정신건강의학과|신경과,가정의학과|신경과,신경외과,재활의학과|정신건강의학과|정신건강의학과|정신건강의학과|비뇨의학과,가정의학과|비뇨의학과|이비인후과,내과|이비인후과|안과|안과|산부인과|산부인과|정형외과,가정의학과,내과|정형외과,신경외과,마취통증의학과|피부과|이비인후과".split("\\|");
  var names=current.departments().stream().collect(Collectors.toMap(d->d.id(),d->d.canonicalName()));
  for(int i=0;i<added.size();i++){String id=added.get(i).id();assertEquals(Set.of(expected[i].split(",")),current.mappings().stream().filter(m->m.diseaseId().equals(id)).map(m->names.get(m.departmentId())).collect(Collectors.toSet()));}
  assertEquals(43,current.mappings().size());assertTrue(current.mappings().stream().allMatch(m->m.reviewStatus().equals("DRAFT")&&m.relationType().equals("DIRECT")&&m.version()==1&&m.approval()==null&&m.evidence().isEmpty()));
 }
 @Test void publishedCatalogContainsNewTagsButNoDraftsOrInventedEvidence()throws Exception{
  var service=new DiseaseReference(Files.readAllBytes(Path.of("src/main/resources/"+base+"v0.3.json")));var r=service.response();var published=json.readValue(r.document(),ReferenceData.class);
  assertEquals(46,published.diseases().stream().filter(d->d.active()).count());assertTrue(published.mappings().isEmpty());assertFalse(published.publicMapApproved());
  assertEquals("eroute-disease-departments-v0.3",service.version());assertEquals("diseases-v2",service.catalogVersion());
  assertEquals(r.sha256(),HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(r.document().getBytes(java.nio.charset.StandardCharsets.UTF_8))));
  for(int i=17;i<=46;i++)assertTrue(service.active("D%03d".formatted(i)));
 }
 @Test void newAliasesAreExactlyTheProvidedTenAndUnique(){
  var current=new FileReferenceRepository(base+"v0.3.json").read();var aliases=new HashMap<String,String>();
  for(var d:current.diseases())for(String a:d.aliases())assertNull(aliases.put(ReferenceValidator.key(a).toLowerCase(Locale.ROOT),d.id()));
  var expected=Map.of("당뇨","D017","ipf","D023","루푸스","D025","sle","D025","ms","D028","알츠하이머","D029","전립선비대증","D035","bph","D035","pcos","D042","허리디스크","D044");
  assertEquals(expected,aliases.entrySet().stream().filter(e->Integer.parseInt(e.getValue().substring(1))>=17).collect(Collectors.toMap(Map.Entry::getKey,Map.Entry::getValue)));
 }
 @Test void coverageUsesDynamicActiveCatalogAndZeroIsSuccessful()throws Exception{
  var original=System.out;var bytes=new ByteArrayOutputStream();
  try{System.setOut(new PrintStream(bytes));ReferenceTool.main(new String[]{"src/main/resources/"+base+"v0.3.json","src/main/resources/"+base+"v0.2.json","../../contracts/fixtures/department-coverage-2026-09-17.json"});}finally{System.setOut(original);}
  var report=json.readTree(bytes.toByteArray());assertEquals(46,report.path("activeDiseases").asInt());assertEquals(43,report.path("draftMappings").asInt());
  for(String key:List.of("approvedMappings","approvedDiseases","approvedDirectMappings","publicMappings","publicDraftMappings","uniqueMatchingHospitals"))assertEquals(0,report.path(key).asInt(-1));
  assertEquals(report.path("activeDiseases").asInt(),report.path("nameCoverageOnly").size());
 }
}
