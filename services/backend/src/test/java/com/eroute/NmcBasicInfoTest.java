package com.eroute;
import com.eroute.emergency.domain.model.BasicModels.*;
import com.eroute.emergency.infrastructure.nmc.*;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class NmcBasicInfoTest {
 final NmcXmlParser xml=new NmcXmlParser();final NmcBasicInfoNormalizer parser=new NmcBasicInfoNormalizer(new JsonCodec());
 NormalizedBasic parse(String fields){return parser.normalize(xml.basicItems("<response><item>"+fields+"</item></response>").getFirst());}
 @Test void departmentsPreserveOrderDuplicatesAndUnknowns(){var d=parse("<dgidIdName> 내과,외과,내과,,설명 병원 </dgidIdName>");assertEquals(Status.UNVERIFIED,d.departmentsStatus());assertEquals(4,d.departments().size());assertEquals(" 내과,외과,내과,,설명 병원 ",d.rawDepartmentText());assertNull(d.departments().getLast().name());assertEquals(Status.UNVERIFIED,parse("<dgidIdName>내과 외과</dgidIdName>").departmentsStatus());assertEquals(Status.UNVERIFIED,parse("<dgidIdName>내과;외과</dgidIdName>").departmentsStatus());assertEquals(Status.MISSING,parse("<dgidIdName/>").departmentsStatus());}
 @Test void strictHoursNeverInventOvernightOrSpecialMeaning(){
  var h=parse("<dutyTime1s>0900</dutyTime1s><dutyTime1c>1730</dutyTime1c>").operatingHours();assertEquals(8,h.size());assertEquals("09:00",h.getFirst().open());assertEquals("17:30",h.getFirst().close());assertEquals(Status.KNOWN,h.getFirst().status());assertEquals(Status.MISSING,h.getLast().status());
  for(String[] pair:List.of(new String[]{"0000","2359"},new String[]{"0900","2400"},new String[]{"1800","0900"},new String[]{"0900","0900"},new String[]{"0900",""},new String[]{"","1730"})){assertEquals(Status.UNVERIFIED,parse("<dutyTime1s>"+pair[0]+"</dutyTime1s><dutyTime1c>"+pair[1]+"</dutyTime1c>").operatingHours().getFirst().status());}
  for(String v:List.of("null","bad","900"," 0900","0960","2500"))assertEquals(Status.UNPARSEABLE,parse("<dutyTime1s>"+v+"</dutyTime1s>").operatingHours().getFirst().status());
 }
 @Test void missingEmptyNilRepeatedAndNestedRemainDistinct(){
  var r=xml.basicItems("<item xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><a/><b xsi:nil=\"true\"/><c>null</c><d>1</d><d>2</d><e><n>3</n></e></item>").getFirst();assertEquals(Presence.MISSING,r.cell("z").presence());assertEquals(Presence.EMPTY,r.cell("a").presence());assertEquals(Presence.NIL,r.cell("b").presence());assertNull(r.cell("b").value());assertEquals("null",r.cell("c").value());assertEquals(Presence.MULTIPLE,r.cell("d").presence());assertEquals(2,r.fields().get("d").size());assertEquals(Presence.STRUCTURED,r.cell("e").presence());
  assertEquals(Status.UNVERIFIED,parse("<dutyTime1s>0900</dutyTime1s><dutyTime1s>1000</dutyTime1s>").operatingHours().getFirst().status());
 }
 @Test void authenticatedFixtureIsNotGuessedFromFieldPrefixes()throws Exception{
  try(var in=getClass().getResourceAsStream("/nmc/basic/nationwide.xml")){String raw=new String(in.readAllBytes(),java.nio.charset.StandardCharsets.UTF_8);var page=xml.parse(raw,Instant.EPOCH);assertEquals(529,page.totalCount());for(var item:xml.basicItems(raw)){var n=parser.normalize(item);assertEquals(8,n.operatingHours().size());assertNotEquals(Status.UNVERIFIED,n.departmentsStatus());}}
 }
 @Test void discoveryRejectsWrongHospitalAndIncompletePages(){var p=new com.eroute.emergency.domain.model.Models.Page(1,10,1,List.of(TestSupport.row("A","1")),"",Instant.EPOCH);assertThrows(RuntimeException.class,()->NmcBasicInfoDiscoveryProbe.verifySingle(p,"B"));assertThrows(RuntimeException.class,()->NmcBasicInfoDiscoveryProbe.validatePage(p,2,10,1));}
}
