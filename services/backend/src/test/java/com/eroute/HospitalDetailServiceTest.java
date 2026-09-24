package com.eroute;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.application.*;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.port.*;
import com.eroute.emergency.infrastructure.nmc.NmcFieldNormalizer;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class HospitalDetailServiceTest {
 final HospitalRepository hospitals=mock(HospitalRepository.class);
 final HospitalObservationRepository observations=mock(HospitalObservationRepository.class);
 final EmergencyHospitalProvider provider=mock(EmergencyHospitalProvider.class);
 final ExecutorService executor=Executors.newVirtualThreadPerTaskExecutor();
 final Clock clock=Clock.fixed(TestSupport.NOW,ZoneOffset.UTC);
 final EmergencyHospitalService realtime=new EmergencyHospitalService(hospitals,observations,provider,new NmcFieldNormalizer(new JsonCodec()),TestSupport.properties(),clock,executor);
 final HospitalDetailService service=new HospitalDetailService(hospitals,observations,realtime,TestSupport.properties(),clock,mock(HospitalBasicInfoRepository.class));
 @AfterEach void close(){executor.close();}
 @Test void combinesStoredMasterAndCurrentObservationWithoutCallingNmc(){
  var region=new Region("R1","S1","S2");
  var hospital=new Hospital("HPID-1","Hospital","A","응급의료기관","Address",new Point(37,127),"02-111-1111","02-222-2222",region);
  when(hospitals.findActiveByHpid("HPID-1")).thenReturn(Optional.of(new HospitalMaster(hospital,TestSupport.NOW.minusSeconds(60),TestSupport.NOW.minusSeconds(60),"catalog-v1")));
  when(observations.current("HPID-1","R1")).thenReturn(new CurrentHospitalObservation(Coverage.LIVE_AVAILABLE,Refresh.CACHE_HIT,TestSupport.row("HPID-1","14"),TestSupport.NOW,TestSupport.NOW,null));
  var detail=service.get("HPID-1");
  assertEquals("대표전화1",detail.mainPhone().officialLabel());assertEquals("dutyTel1",detail.mainPhone().sourceField());
  assertEquals("대표전화2",detail.secondaryPhone().officialLabel());assertEquals("dutyTel3",detail.secondaryPhone().sourceField());
  assertEquals(14L,detail.realtime().availableBeds().numericValue());assertEquals(17L,detail.realtime().referenceResources().getFirst().numericValue());
  assertEquals(FetchStatus.NOT_REQUESTED,detail.basicInfo().fetchStatus());assertNull(detail.basicInfo().clinicHours());
  verifyNoInteractions(provider);
 }
 @Test void confirmedNotProvidedDoesNotReadHistoricalSnapshot(){
  var region=new Region("R1","S1","S2");
  var hospital=new Hospital("HPID-1","Hospital",null,null,null,new Point(37,127),null,null,region);
  when(hospitals.findActiveByHpid("HPID-1")).thenReturn(Optional.of(new HospitalMaster(hospital,TestSupport.NOW,TestSupport.NOW,"v1")));
  when(observations.current("HPID-1","R1")).thenReturn(new CurrentHospitalObservation(Coverage.LIVE_NOT_PROVIDED,Refresh.CACHE_HIT,null,TestSupport.NOW,TestSupport.NOW,null));
  var detail=service.get("HPID-1");
  assertEquals(Coverage.LIVE_NOT_PROVIDED,detail.realtime().coverageStatus());assertNull(detail.realtime().availableBeds().numericValue());
 }
 @Test void missingActiveHospitalReturns404Problem(){
  when(hospitals.findActiveByHpid("MISSING")).thenReturn(Optional.empty());
  var problem=assertThrows(ServiceProblem.class,()->service.get("MISSING"));assertEquals(404,problem.status());assertEquals("HOSPITAL_NOT_FOUND",problem.code());
 }
}
