package com.eroute;

import com.eroute.common.error.ApiErrorHandler;
import com.eroute.emergency.api.EmergencyHospitalController;
import com.eroute.emergency.application.*;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.port.*;
import com.eroute.emergency.infrastructure.nmc.NmcFieldNormalizer;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class HospitalDetailHttpTest {
 final HospitalRepository hospitals=mock(HospitalRepository.class);
 final HospitalObservationRepository observations=mock(HospitalObservationRepository.class);
 final EmergencyHospitalProvider nmc=mock(EmergencyHospitalProvider.class);
 final ExecutorService executor=Executors.newVirtualThreadPerTaskExecutor();
 final Clock clock=Clock.fixed(TestSupport.NOW,ZoneOffset.UTC);
 final EmergencyHospitalService realtime=new EmergencyHospitalService(hospitals,observations,nmc,
  new NmcFieldNormalizer(new JsonCodec()),TestSupport.properties(),clock,executor);
 final MockMvc http=MockMvcBuilders.standaloneSetup(new EmergencyHospitalController(realtime,
  new HospitalDetailService(hospitals,observations,realtime,TestSupport.properties(),clock,mock(HospitalBasicInfoRepository.class))))
  .setControllerAdvice(new ApiErrorHandler()).build();

 @AfterEach void close(){verifyNoInteractions(nmc);executor.close();}
 void master(String secondary){
  var h=new Hospital("HTTP-1","테스트 병원","A","분류","검증 주소",new Point(37,127),"02-111-1111",secondary,new Region("R","S1","S2"));
  when(hospitals.findActiveByHpid("HTTP-1")).thenReturn(Optional.of(new HospitalMaster(h,TestSupport.NOW,TestSupport.NOW,"v1")));
  when(observations.current("HTTP-1","R")).thenReturn(new CurrentHospitalObservation(Coverage.LIVE_AVAILABLE,
   Refresh.CACHE_HIT,TestSupport.row("HTTP-1","0"),TestSupport.NOW,TestSupport.NOW,null));
 }
 @Test void httpContractPreservesAddressContactsAndZero() throws Exception {
  master("02-222-2222");
  for(int i=0;i<3;i++)http.perform(get("/api/v1/emergency-hospitals/HTTP-1"))
   .andExpect(status().isOk()).andExpect(jsonPath("$.hpid").value("HTTP-1"))
   .andExpect(jsonPath("$.address").value("검증 주소"))
   .andExpect(jsonPath("$.emergencyClass.name").value("분류"))
   .andExpect(jsonPath("$.mainPhone.sourceField").value("dutyTel1"))
   .andExpect(jsonPath("$.mainPhone.rawValue").value("02-111-1111"))
   .andExpect(jsonPath("$.secondaryPhone.sourceField").value("dutyTel3"))
   .andExpect(jsonPath("$.secondaryPhone.rawValue").value("02-222-2222"))
   .andExpect(jsonPath("$.realtime.availableBeds.numericValue").value(0))
   .andExpect(jsonPath("$.basicInfo.fetchStatus").value("NOT_REQUESTED"))
   .andExpect(jsonPath("$.masterUpdatedAt").isString());
 }
 @Test void nullableSecondaryAndNotProvidedAreSuccessful() throws Exception {
  master(null);
  when(observations.current("HTTP-1","R")).thenReturn(new CurrentHospitalObservation(Coverage.LIVE_NOT_PROVIDED,
   Refresh.CACHE_HIT,null,TestSupport.NOW,TestSupport.NOW,null));
  http.perform(get("/api/v1/emergency-hospitals/HTTP-1")).andExpect(status().isOk())
   .andExpect(jsonPath("$.secondaryPhone").value(org.hamcrest.Matchers.nullValue()))
   .andExpect(jsonPath("$.realtime.coverageStatus").value("LIVE_NOT_PROVIDED"));
 }
 @Test void missingAndDatabaseFailureHaveDistinctHttpErrors() throws Exception {
  when(hospitals.findActiveByHpid("MISSING")).thenReturn(Optional.empty());
  http.perform(get("/api/v1/emergency-hospitals/MISSING")).andExpect(status().isNotFound())
   .andExpect(jsonPath("$.code").value("HOSPITAL_NOT_FOUND"));
  when(hospitals.findActiveByHpid("DB-FAIL")).thenThrow(new DataAccessResourceFailureException("test"));
  http.perform(get("/api/v1/emergency-hospitals/DB-FAIL")).andExpect(status().isServiceUnavailable())
   .andExpect(jsonPath("$.code").value("DATABASE_UNAVAILABLE"));
 }
 @Test void staleErrorRetainsSnapshotAndNeverInfersAcceptance() throws Exception {
  master(null);
  when(observations.current("HTTP-1","R")).thenReturn(new CurrentHospitalObservation(Coverage.LIVE_AVAILABLE,
   Refresh.ERROR,TestSupport.row("HTTP-1","0"),TestSupport.NOW.minusSeconds(600),TestSupport.NOW,"NMC_TIMEOUT"));
  http.perform(get("/api/v1/emergency-hospitals/HTTP-1")).andExpect(status().isOk())
   .andExpect(jsonPath("$.realtime.coverageStatus").value("LIVE_ERROR"))
   .andExpect(jsonPath("$.realtime.freshness.stale").value(true))
   .andExpect(jsonPath("$.realtime.availableBeds.numericValue").value(0))
   .andExpect(jsonPath("$.realtime.acceptance").doesNotExist());
 }
}
