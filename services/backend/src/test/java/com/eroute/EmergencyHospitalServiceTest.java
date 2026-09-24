package com.eroute;
import com.eroute.emergency.application.EmergencyHospitalService;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.port.*;
import com.eroute.emergency.infrastructure.nmc.NmcFieldNormalizer;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
class EmergencyHospitalServiceTest {
 final ExecutorService executor=Executors.newVirtualThreadPerTaskExecutor();
 final HospitalRepository master=mock(HospitalRepository.class);
 final HospitalObservationRepository snapshots=mock(HospitalObservationRepository.class);
 final EmergencyHospitalProvider provider=mock(EmergencyHospitalProvider.class);
 final EmergencyHospitalService service=new EmergencyHospitalService(master,snapshots,provider,new NmcFieldNormalizer(new JsonCodec()),TestSupport.properties(),Clock.fixed(TestSupport.NOW,ZoneOffset.UTC),executor);
 @AfterEach void close(){executor.close();}
 Hospital hospital(String id,double lat,Region region){return new Hospital(id,"Test hospital",null,null,"Test address",new Point(lat,127),null,null,region);}
 @Test void searchesAcrossAdministrativeBoundariesAndKeepsMissingRows(){
  var a=new Region("R1","A","X");var b=new Region("R2","B","Y");
  when(master.catalog()).thenReturn(Optional.of(new Catalog(List.of(hospital("ONE",37,a),hospital("TWO",37.01,b)),TestSupport.NOW,"v1")));
  when(provider.fetchRealtimeBeds(any(),anyLong())).thenReturn(new RegionObservation(new Batch(List.of(),TestSupport.NOW,List.of()),Refresh.UPDATED,TestSupport.NOW,null));
  var r=service.search(new SearchRequest(new Point(37,127),CenterSource.MANUAL,null,null));assertEquals(2,r.hospitals().size());assertFalse(r.meta().expanded());assertNull(r.hospitals().getFirst().distanceFromUserMeters());assertTrue(r.hospitals().stream().allMatch(h->h.realtime().coverageStatus()==Coverage.LIVE_NOT_PROVIDED));verify(provider).fetchRealtimeBeds(eq(a),anyLong());verify(provider).fetchRealtimeBeds(eq(b),anyLong());
 }
 @Test void expandsOnlyForEmptyMasterCandidates(){when(master.catalog()).thenReturn(Optional.of(new Catalog(List.of(hospital("ONE",37.13,null)),TestSupport.NOW,"v1")));var r=service.search(new SearchRequest(new Point(37,127),CenterSource.GPS,new Point(37,127),null));assertEquals(List.of(10000,20000),r.meta().attemptedRadiiMeters());assertEquals(1,r.hospitals().size());}
 @Test void noMasterIsUnavailableNotEmpty(){when(master.catalog()).thenReturn(Optional.empty());assertThrows(com.eroute.common.error.ServiceProblem.class,()->service.search(new SearchRequest(new Point(37,127),CenterSource.GPS,null,null)));}
 @Test void failureReturnsPreviousValueWithErrorAndStale(){var old=new Batch(List.of(TestSupport.row("ONE","14")),TestSupport.NOW.minusSeconds(900),List.of());var r=service.present("ONE",new RegionObservation(old,Refresh.ERROR,TestSupport.NOW,"NMC_TRANSPORT_ERROR"));assertEquals(Coverage.LIVE_ERROR,r.coverageStatus());assertTrue(r.freshness().stale());assertEquals(14L,r.availableBeds().numericValue());assertEquals(old.fetchedAt(),r.freshness().fetchedAt());}
 @Test void budgetDeferralIsNotApiError(){var r=service.present("ONE",new RegionObservation(null,Refresh.BUDGET_DEFERRED,null,"CALL_BUDGET_LIMIT"));assertEquals(Coverage.LIVE_UNKNOWN,r.coverageStatus());assertTrue(r.freshness().stale());assertNull(r.availableBeds().numericValue());assertNull(r.freshness().lastAttemptAt());}
 @Test void confirmedAbsenceDoesNotResurrectHistoricalValue(){var r=service.present("ONE",new RegionObservation(new Batch(List.of(),TestSupport.NOW,List.of()),Refresh.ERROR,TestSupport.NOW,"NMC_TRANSPORT_ERROR"));assertNull(r.availableBeds().numericValue());}
 @Test void rejectsNonfiniteCoordinatesAndUnconfiguredRadius(){assertThrows(IllegalArgumentException.class,()->new Point(Double.NaN,127));assertThrows(IllegalArgumentException.class,()->service.search(new SearchRequest(new Point(37,127),CenterSource.MANUAL,null,15000)));}
 @Test void expiredSharedDeadlineStillUsesAnotherRegionsCompletedResult(){
  var slow=new Region("SLOW","A","X");var fast=new Region("FAST","B","Y");
  when(master.catalog()).thenReturn(Optional.of(new Catalog(List.of(hospital("ONE",37,slow),hospital("TWO",37.01,fast)),TestSupport.NOW,"v1")));
  when(provider.fetchRealtimeBeds(eq(slow),anyLong())).thenAnswer(inv->{Thread.sleep(5000);return new RegionObservation(null,Refresh.NOT_REQUESTED,null,null);});
  when(provider.fetchRealtimeBeds(eq(fast),anyLong())).thenReturn(new RegionObservation(new Batch(List.of(TestSupport.row("TWO","0")),TestSupport.NOW,List.of()),Refresh.UPDATED,TestSupport.NOW,null));
  var result=service.search(new SearchRequest(new Point(37,127),CenterSource.GPS,null,10000));
  assertEquals(Coverage.LIVE_UNKNOWN,result.hospitals().getFirst().realtime().coverageStatus());
  assertEquals(Coverage.LIVE_AVAILABLE,result.hospitals().getLast().realtime().coverageStatus());
  assertEquals(0L,result.hospitals().getLast().realtime().availableBeds().numericValue());
 }

 @Test void elapsedCacheReadReevaluatesAgeWithoutChangingEitherClock(){
  var row=TestSupport.row("ONE","0");
  var observation=new CurrentHospitalObservation(Coverage.LIVE_AVAILABLE,Refresh.CACHE_HIT,row,TestSupport.NOW,TestSupport.NOW.minusSeconds(1),null);
  var initial=service.present(observation);
  assertFalse(initial.freshness().stale());assertEquals("UNKNOWN",initial.freshness().sourceFreshness());
  var later=new EmergencyHospitalService(master,snapshots,provider,new NmcFieldNormalizer(new JsonCodec()),TestSupport.properties(),Clock.fixed(TestSupport.NOW.plusSeconds(300),ZoneOffset.UTC),executor);
  var expired=later.present(observation);
  assertTrue(expired.freshness().stale());assertEquals(List.of("CACHE_EXPIRED"),expired.freshness().staleReasons());
  assertEquals(initial.freshness().fetchedAt(),expired.freshness().fetchedAt());
  assertEquals(initial.freshness().source(),expired.freshness().source());
  assertEquals(initial.freshness().lastAttemptAt(),expired.freshness().lastAttemptAt());verifyNoInteractions(provider);
 }
 @Test void recollectingIdenticalProviderTimestampDoesNotMakeItsSourceFresh(){
  var row=TestSupport.row("ONE","0");
  var previous=service.present("ONE",new RegionObservation(new Batch(List.of(row),TestSupport.NOW.minusSeconds(600),List.of()),Refresh.CACHE_HIT,TestSupport.NOW.minusSeconds(601),null));
  var collected=service.present("ONE",new RegionObservation(new Batch(List.of(row),TestSupport.NOW,List.of()),Refresh.UPDATED,TestSupport.NOW.minusSeconds(1),null));
  assertTrue(previous.freshness().stale());assertFalse(collected.freshness().stale());
  assertNotEquals(previous.freshness().fetchedAt(),collected.freshness().fetchedAt());
  assertEquals(previous.freshness().source(),collected.freshness().source());
  assertEquals("UNKNOWN",collected.freshness().sourceFreshness());assertNull(collected.freshness().source().sourceUpdatedAt());
  assertEquals(0L,collected.availableBeds().numericValue());
 }
 @Test void missingAndMalformedProviderClocksStayUnknownAfterSuccessfulCollection(){
  for(String raw:List.of("","invalid")){
   var row=new RawItem(Map.of("hpid",List.of("ONE"),"hvec",List.of("0"),"hvidate",List.of(raw)));
   var result=service.present("ONE",new RegionObservation(new Batch(List.of(row),TestSupport.NOW,List.of()),Refresh.UPDATED,TestSupport.NOW,null));
   assertEquals(Coverage.LIVE_AVAILABLE,result.coverageStatus());assertEquals("UNKNOWN",result.freshness().sourceFreshness());
   assertEquals(raw.isEmpty()?"MISSING":"UNPARSEABLE",result.freshness().source().sourceTimestampStatus());assertNull(result.freshness().source().sourceUpdatedAt());
  }
 }

}
