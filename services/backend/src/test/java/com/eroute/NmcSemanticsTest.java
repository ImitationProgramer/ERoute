package com.eroute;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.infrastructure.nmc.*;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.util.*;
class NmcSemanticsTest {
 final NmcFieldNormalizer normalizer=new NmcFieldNormalizer(new JsonCodec());
 @Test void realZeroIsNotMissing(){var v=normalizer.availableBeds(TestSupport.row("TEST1","0"));assertEquals(0L,v.numericValue());assertEquals(Interpretation.KNOWN,v.interpretationStatus());}
 @Test void absenceNeverBecomesZero(){var v=normalizer.availableBeds(null);assertNull(v.numericValue());assertEquals(Interpretation.MISSING,v.interpretationStatus());}
 @Test void hvsKeepsItsOwnMeaningAndAlias(){var v=normalizer.referenceResources(TestSupport.row("TEST1","14")).getFirst();assertEquals("hvs01",v.sourceField());assertEquals("일반_기준",v.officialLabel());assertEquals(17L,v.numericValue());}
 @Test void basicHvNeverInterpretedAsLive(){var v=normalizer.value("getEgytBassInfoInqire","hvec",TestSupport.row("TEST1","14"));assertNull(v.numericValue());assertEquals(Interpretation.UNVERIFIED,v.interpretationStatus());}
 @Test void noHvsFallbackToBasicOrTotal(){var raw=new RawItem(Map.of("hperyn",List.of("17"),"hpbdn",List.of("100")));assertNull(normalizer.referenceResources(raw).getFirst().numericValue());}
 @Test void negativeAndMixedTypesPreserved(){var negative=normalizer.availableBeds(TestSupport.row("TEST1","-3"));assertEquals(-3L,negative.numericValue());assertEquals(Interpretation.UNVERIFIED,negative.interpretationStatus());var v=normalizer.value(NmcFieldNormalizer.BEDS,"hv42",new RawItem(Map.of("hv42",List.of("Y"))));assertEquals("Y",v.rawValue());assertEquals(Interpretation.UNVERIFIED,v.interpretationStatus());}
 @Test void n1IsNotFalse(){var v=normalizer.value(NmcFieldNormalizer.BEDS,"hvoxyayn",new RawItem(Map.of("hvoxyayn",List.of("N1"))));assertEquals(Interpretation.UNKNOWN_CODE,v.interpretationStatus());assertEquals("N1",v.rawValue());}
 @Test void duplicateAliasesAreAmbiguous(){var raw=new RawItem(Map.of("HVS01",List.of("17"),"hvs01",List.of("19")));assertEquals(Interpretation.UNVERIFIED,normalizer.referenceResources(raw).getFirst().interpretationStatus());}
 @Test void timestampsDoNotAcquireAnInventedZone(){var time=normalizer.timestamp("20260908210000");assertEquals("2026-09-08T21:00",time.parsedSourceTimestamp());assertNull(time.sourceTimezone());assertNull(time.sourceUpdatedAt());assertEquals("TIMEZONE_UNVERIFIED",time.sourceTimestampStatus());assertEquals("UNPARSEABLE",normalizer.timestamp("unknown").sourceTimestampStatus());}
 @Test void koreanTimestampExampleRemainsLocal(){assertEquals("2013-10-01T13:14:12",normalizer.timestamp("2013-10-01 오후1:14:12").parsedSourceTimestamp());}
 @Test void gatekeeperDoesNotProvideOtherCapabilities(){String endpoint="getSrsillDissAceptncPosblInfoInqire";assertEquals(Acceptance.AVAILABLE,normalizer.capability(endpoint,"MKioskTy28","Y ").status());assertEquals(Acceptance.NOT_PROVIDED,normalizer.capability(endpoint,"MKioskTy1","정보미제공").status());assertEquals(Acceptance.UNKNOWN,normalizer.capability("getEgytBassInfoInqire","MKioskTy1","Y").status());assertEquals(Acceptance.UNAVAILABLE,normalizer.capability(endpoint,"MKioskTy1","N").status());}
}
