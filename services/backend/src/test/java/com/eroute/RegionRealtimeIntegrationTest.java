package com.eroute;

import com.eroute.emergency.application.*;
import com.eroute.emergency.infrastructure.nmc.*;
import com.eroute.emergency.infrastructure.persistence.*;
import com.eroute.emergency.domain.model.Models.*;
import com.sun.net.httpserver.HttpServer;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.*;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(properties={"eroute.jobs-enabled=false","eroute.call-budget=100","eroute.requests-per-second=2","eroute.request-timeout=1s","eroute.key-alias=region-test","eroute.nmc-key=fixture-key","eroute.refresh-deadline=12s"})
class RegionRealtimeIntegrationTest {
 static HttpServer server;
 static volatile String scenario="NORMAL";
 static final List<Map<String,String>> requests=new CopyOnWriteArrayList<>();
 static {
  try {
   server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
   server.createContext("/",exchange->{
    var query=new HashMap<String,String>();
    for(String pair:exchange.getRequestURI().getRawQuery().split("&")){var p=pair.split("=",2);query.put(URLDecoder.decode(p[0],StandardCharsets.UTF_8),URLDecoder.decode(p[1],StandardCharsets.UTF_8));}
    boolean list=exchange.getRequestURI().getPath().endsWith(NmcFieldNormalizer.LIST);query.put("endpoint",list?"LIST":"BEDS");query.remove("ServiceKey");requests.add(query);
    int page=Integer.parseInt(query.get("pageNo")),size=100,status=200;List<String> ids;
    String region=query.get(list?"Q1":"STAGE2");
    if(list) ids=scenario.equals("MAPPING")?List.of():region.equals("City")?List.of("EAST","WEST"):List.of("COUNTY");
    else ids=region.equals("City East")?List.of("EAST"):region.equals("City West")?List.of("WEST"):List.of("COUNTY");
    int total=ids.size();
    if(!list&&region.equals("City West")) {
     if(scenario.equals("MISSING")){ids=List.of();total=0;}
     if(scenario.equals("FAIL"))status=503;
     if(scenario.equals("PAGINATION")){size=1;total=2;if(page==2)status=503;}
    }
    String items=ids.stream().map(h->"<item><hpid>"+h+"</hpid><hvec>0</hvec><hvidate>20260914090000</hvidate></item>").reduce("",String::concat);
    String xml="<response><header><resultCode>00</resultCode><resultMsg>NORMAL SERVICE.</resultMsg></header><body><items>"+items+"</items><pageNo>"+page+"</pageNo><numOfRows>"+size+"</numOfRows><totalCount>"+total+"</totalCount></body></response>";
    byte[] bytes=xml.getBytes(StandardCharsets.UTF_8);exchange.sendResponseHeaders(status,bytes.length);exchange.getResponseBody().write(bytes);exchange.close();
   });server.start();
  }catch(Exception e){throw new ExceptionInInitializerError(e);}
 }
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r){PostgresIntegrationTest.db(r);r.add("eroute.nmc-base-url",()->"http://127.0.0.1:"+server.getAddress().getPort());}
 @Autowired JdbcTemplate db;
 @Autowired NmcRegionResolver resolver;
 @Autowired NmcEmergencyApiProvider provider;
 @Autowired JdbcHospitalStore store;
 @Autowired EmergencyHospitalService service;
 @Autowired HospitalDetailService detail;
 final Region east=new Region("east","Province","City East"),west=new Region("west","Province","City West"),county=new Region("county","Province","County");
 @BeforeEach void seed(){
  assertTrue(db.queryForObject("SELECT current_database()",String.class).endsWith("_test")||db.queryForObject("SELECT current_database()",String.class).equals("test"));
  db.execute("TRUNCATE nmc_region_mapping,hospital,catalog_state,hospital_observation,hospital_realtime_snapshot,region_cache,nmc_call_attempt,nmc_budget_block,provider_response CASCADE");
  scenario="NORMAL";requests.clear();
  for(Region r:List.of(east,west,county,new Region("city","Province","City")))db.update("INSERT INTO nmc_region_mapping VALUES(?,?,?,?,?,false)",r.id(),r.stage1()+" "+r.stage2(),r.stage1(),r.stage2(),"fixture");
  for(String id:List.of("east","west"))db.update("INSERT INTO nmc_region_query_mapping VALUES(?,?,?,?)",id,NmcFieldNormalizer.LIST,"city","fixture");
  UUID version=UUID.randomUUID();db.update("INSERT INTO catalog_state VALUES(true,?,clock_timestamp())",version);
  for(var entry:Map.of("EAST",east,"WEST",west,"COUNTY",county).entrySet())db.update("INSERT INTO hospital(hpid,name,address,latitude,longitude,region_id,raw_json,catalog_version,updated_at) VALUES(?,?,?,37,127,?,'{}',?,clock_timestamp())",entry.getKey(),"Fixture "+entry.getKey(),entry.getValue().stage1()+" "+entry.getValue().stage2()+" Road",entry.getValue().id(),version);
 }
 Map<String,Realtime> search(){var result=service.search(new SearchRequest(new Point(37,127),CenterSource.GPS,new Point(37,127),10000));var rows=new HashMap<String,Realtime>();result.hospitals().forEach(h->rows.put(h.hpid(),h.realtime()));return rows;}
 @Test void simpleCountyAndCityDistrictsAtBoundaryUseEndpointSpecificFilters(){
  assertEquals("east",resolver.resolveId("Province City East Road"));assertEquals("county",resolver.resolveId("Province County Road"));assertNull(resolver.resolveId("Province CountyOther Road"));
  var result=search();assertEquals(3,result.size());result.values().forEach(r->assertEquals(Coverage.LIVE_AVAILABLE,r.coverageStatus()));
  assertEquals(1,requests.stream().filter(q->"City".equals(q.get("Q1"))).count());
  assertTrue(requests.stream().anyMatch(q->"City East".equals(q.get("STAGE2"))));assertTrue(requests.stream().anyMatch(q->"City West".equals(q.get("STAGE2"))));
  assertTrue(requests.stream().anyMatch(q->"County".equals(q.get("STAGE2"))));
  assertEquals(0L,detail.get("WEST").realtime().availableBeds().numericValue());
 }
 @Test void oneFailedRegionCannotContaminateOtherRegions(){scenario="FAIL";var result=search();assertEquals(Coverage.LIVE_ERROR,result.get("WEST").coverageStatus());assertEquals(Coverage.LIVE_AVAILABLE,result.get("EAST").coverageStatus());assertEquals(Coverage.LIVE_AVAILABLE,result.get("COUNTY").coverageStatus());assertEquals(Coverage.LIVE_ERROR,detail.get("WEST").realtime().coverageStatus());}
 @Test void completeResponseWithoutHpidIsNotProvided(){scenario="MISSING";var result=search();assertEquals(Coverage.LIVE_NOT_PROVIDED,result.get("WEST").coverageStatus());assertNull(result.get("WEST").error());assertEquals(Coverage.LIVE_NOT_PROVIDED,detail.get("WEST").realtime().coverageStatus());}
 @Test void partialPaginationNeverPublishesOrConfirmsAbsence(){scenario="PAGINATION";var result=search();assertEquals(Coverage.LIVE_ERROR,result.get("WEST").coverageStatus());assertTrue(store.lastComplete("west").isEmpty());assertEquals(0,db.queryForObject("SELECT count(*) FROM hospital_observation WHERE hpid='WEST'",Integer.class));assertEquals(Coverage.LIVE_AVAILABLE,result.get("COUNTY").coverageStatus());}
 @Test void budgetDeferralMakesNoExternalBedRequestAndIsUnknown(){db.update("UPDATE nmc_region_mapping SET verified=true");db.update("INSERT INTO nmc_budget_block VALUES('region-test',?,clock_timestamp()+interval '1 day')",NmcFieldNormalizer.BEDS);var result=search();assertTrue(requests.isEmpty());result.values().forEach(r->{assertEquals(Coverage.LIVE_UNKNOWN,r.coverageStatus());assertEquals(Refresh.BUDGET_DEFERRED,r.refreshStatus());assertNull(r.freshness().lastAttemptAt());});assertEquals(Refresh.BUDGET_DEFERRED,detail.get("WEST").realtime().refreshStatus());}
 @Test void priorSuccessfulSnapshotSurvivesCurrentFailure(){
  UUID owner=UUID.randomUUID();store.acquireLease("west",owner);var old=new Batch(List.of(TestSupport.row("WEST","14")),Instant.now().minusSeconds(900),List.of());store.complete("west",old,owner);store.releaseLease("west",owner);
  scenario="FAIL";var r=search().get("WEST");assertEquals(Coverage.LIVE_ERROR,r.coverageStatus());assertEquals(14L,r.availableBeds().numericValue());assertTrue(r.freshness().stale());assertEquals(old.fetchedAt(),r.freshness().fetchedAt());assertEquals(14L,detail.get("WEST").realtime().availableBeds().numericValue());
 }
 @Test void successfulEmptyValidationIsMappingErrorNotLiveError(){scenario="MAPPING";var result=search();assertTrue(requests.stream().noneMatch(q->q.get("endpoint").equals("BEDS")));result.values().forEach(r->{assertEquals(Coverage.LIVE_UNKNOWN,r.coverageStatus());assertEquals(Refresh.NOT_REQUESTED,r.refreshStatus());assertEquals("REGION_MAPPING_ERROR",r.error());assertNull(r.freshness().lastAttemptAt());});assertEquals(Coverage.LIVE_UNKNOWN,detail.get("WEST").realtime().coverageStatus());assertEquals("REGION_MAPPING_ERROR",detail.get("WEST").realtime().error());}
 @Test void simultaneousExpiredRegionsWaitForGuardAndCompleteInOneSearch(){
  db.update("UPDATE nmc_region_mapping SET verified=true");
  for(var entry:Map.of("EAST",east,"WEST",west,"COUNTY",county).entrySet()){
   UUID owner=UUID.randomUUID();store.acquireLease(entry.getValue().id(),owner);
   store.complete(entry.getValue().id(),new Batch(List.of(TestSupport.row(entry.getKey(),"14")),Instant.now().minusSeconds(900),List.of()),owner);store.releaseLease(entry.getValue().id(),owner);
  }
  long start=System.nanoTime();var result=search();long elapsed=System.nanoTime()-start;
  result.values().forEach(r->{assertEquals(Coverage.LIVE_AVAILABLE,r.coverageStatus());assertEquals(Refresh.UPDATED,r.refreshStatus());assertEquals(0L,r.availableBeds().numericValue());});
  assertEquals(3,requests.size());assertTrue(elapsed<java.time.Duration.ofSeconds(12).toNanos());
  assertTrue(db.queryForObject("SELECT EXTRACT(EPOCH FROM(max(requested_at)-min(requested_at))) FROM nmc_call_attempt",Double.class)>=1.0);
  assertTrue(db.queryForObject("SELECT max((SELECT count(*) FROM nmc_call_attempt b WHERE b.endpoint=a.endpoint AND b.requested_at>a.requested_at-interval '1 second' AND b.requested_at<=a.requested_at)) FROM nmc_call_attempt a",Integer.class)<=2);
  search();assertEquals(3,requests.size(),"Fresh completed regions must not be requested again");
 }
 @Test void exhaustedRollingBudgetDoesNotWaitAndRetainsPriorSnapshot(){
  db.update("UPDATE nmc_region_mapping SET verified=true");
  UUID owner=UUID.randomUUID();store.acquireLease("west",owner);store.complete("west",new Batch(List.of(TestSupport.row("WEST","14")),Instant.now().minusSeconds(900),List.of()),owner);store.releaseLease("west",owner);
  db.update("INSERT INTO nmc_call_attempt(key_alias,endpoint,scope,requested_at,outcome) SELECT 'region-test',?,'other',clock_timestamp()-interval '1 hour','SUCCESS' FROM generate_series(1,100)",NmcFieldNormalizer.BEDS);
  long start=System.nanoTime();var result=search();assertTrue(System.nanoTime()-start<java.time.Duration.ofSeconds(2).toNanos());
  assertTrue(requests.isEmpty());assertEquals(100,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class));
  result.values().forEach(r->{assertEquals(Refresh.BUDGET_DEFERRED,r.refreshStatus());assertEquals("CALL_BUDGET_LIMIT",r.error());});
  assertEquals(14L,result.get("WEST").availableBeds().numericValue());assertEquals(Coverage.LIVE_UNKNOWN,result.get("EAST").coverageStatus());
 }
 @Test void insufficientSearchTimeDefersRateSlotWithoutBackgroundResume()throws Exception{
  db.update("UPDATE nmc_region_mapping SET verified=true");
  db.update("INSERT INTO nmc_call_attempt(key_alias,endpoint,scope,outcome) SELECT 'region-test',?,'other','SUCCESS' FROM generate_series(1,2)",NmcFieldNormalizer.BEDS);
  var result=provider.fetchRealtimeBeds(west,System.nanoTime()+java.time.Duration.ofMillis(100).toNanos());
  assertEquals(Refresh.BUDGET_DEFERRED,result.refresh());assertEquals("CALL_RATE_LIMIT",result.error());assertNull(result.attemptedAt());
  Thread.sleep(1100);assertTrue(requests.isEmpty());assertEquals(2,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class));
  assertEquals(Refresh.BUDGET_DEFERRED,detail.get("WEST").realtime().refreshStatus());
  assertEquals(Refresh.UPDATED,provider.fetchRealtimeBeds(west).refresh());assertEquals(1,requests.size());
 }
 @Test void expiredDeadlineBeforeAdmissionNeverBecomesLiveError(){
  db.update("UPDATE nmc_region_mapping SET verified=true");
  var result=provider.fetchRealtimeBeds(west,System.nanoTime()-1);
  assertEquals(Refresh.NOT_REQUESTED,result.refresh());assertEquals("REQUEST_NOT_STARTED",result.error());assertTrue(requests.isEmpty());
  assertEquals(Coverage.LIVE_UNKNOWN,detail.get("WEST").realtime().coverageStatus());
 }
 @Test void dataMappingsCoverNationwideDistrictHierarchiesWithoutHospitalConstants()throws Exception{
  var mapper=new JsonCodec().mapper();try(var in=getClass().getResourceAsStream("/nmc/region-query-mappings.json")){
   var data=mapper.readTree(in);var prefixes=new HashMap<String,String>();for(var row:data.path("mappings"))prefixes.put(row.path("administrativePrefix").asText(),row.path("requestStage2").asText());
   for(String prefix:List.of("경기도 고양시 일산동구","경기도 고양시 일산서구","경기도 성남시 분당구","경기도 성남시 수정구","경기도 성남시 중원구","경기도 수원시 장안구","경기도 수원시 권선구","경기도 수원시 팔달구","경기도 수원시 영통구","경기도 용인시 처인구","경기도 용인시 기흥구","경기도 용인시 수지구","충청북도 청주시 상당구"))assertEquals(prefix.split(" ")[1],prefixes.get(prefix));
  }
 }
 @AfterAll static void stop(){server.stop(0);}
}
