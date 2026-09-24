package com.eroute;
import com.eroute.common.config.*;
import com.eroute.emergency.domain.port.*;
import com.eroute.emergency.domain.model.Models.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.core.env.MapPropertySource;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class StoredHospitalQaTest {
 @Test void isolatedAdapterReadsOnlyStoredObservationsAndRejectsCollection()throws Exception {
  Class<?> type;try{type=Class.forName("com.eroute.qa.StoredHospitalQaConfiguration");}catch(ClassNotFoundException absent){return;}
  for(boolean jobs:List.of(false,true)) {
   try(var context=new AnnotationConfigApplicationContext()) {
    context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("qa",Map.of("eroute.auth.environment","test","eroute.qa.stored-only","true","eroute.jobs-enabled",jobs)));
    var properties=mock(ERouteProperties.class);when(properties.nmcKey()).thenReturn("");
    var observations=mock(HospitalObservationRepository.class);when(observations.lastComplete("qa")).thenReturn(Optional.empty());
    context.registerBean(ERouteProperties.class,()->properties);
    context.registerBean(BasicInfoProperties.class,()->new BasicInfoProperties(Duration.ofDays(7),false));
    context.registerBean(HospitalObservationRepository.class,()->observations);context.register(type);
    if(jobs){assertThrows(Exception.class,context::refresh);continue;}
    context.refresh();var result=context.getBean(EmergencyHospitalProvider.class).fetchRealtimeBeds(new Region("qa","test","test"));
    assertNull(result.batch());assertEquals(Refresh.NOT_REQUESTED,result.refresh());
    verify(observations).lastComplete("qa");verify(observations).lastAttemptAt("qa");verifyNoMoreInteractions(observations);
   }
  }
 }
}
