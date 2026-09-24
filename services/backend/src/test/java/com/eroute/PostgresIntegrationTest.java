package com.eroute;
import com.eroute.emergency.infrastructure.nmc.*;
import com.eroute.emergency.infrastructure.persistence.*;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.common.error.ServiceProblem;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
@SpringBootTest(properties={"eroute.call-budget=5","eroute.requests-per-second=100","eroute.key-alias=integration","eroute.nmc-key=not-a-real-key"})
class PostgresIntegrationTest {
 static PostgreSQLContainer<?> container;
 @DynamicPropertySource static void db(DynamicPropertyRegistry registry){
  String external=System.getenv("EROUTE_TEST_JDBC_URL");
  if(external==null){container=new PostgreSQLContainer<>("postgres:16-alpine");container.start();registry.add("spring.datasource.url",container::getJdbcUrl);registry.add("spring.datasource.username",container::getUsername);registry.add("spring.datasource.password",container::getPassword);}
  else{registry.add("spring.datasource.url",()->external);registry.add("spring.datasource.username",()->System.getenv().getOrDefault("EROUTE_TEST_DB_USER","eroute"));registry.add("spring.datasource.password",()->System.getenv().getOrDefault("EROUTE_TEST_DB_PASSWORD",""));}
 }
 @Autowired JdbcTemplate db;
 @Autowired NmcCallBudgetGuard guard;
 @Autowired JdbcHospitalStore store;
 @Autowired com.eroute.emergency.application.HospitalDetailService detail;
 @BeforeEach void reset(){String database=db.queryForObject("SELECT current_database()",String.class);assertTrue(database.equals("test")||database.endsWith("_test"),"Refuse destructive tests outside a test database");db.execute("TRUNCATE hospital_observation,hospital_resource_value,hospital_realtime_snapshot,hospital,catalog_state,region_cache,nmc_call_attempt,nmc_budget_block CASCADE");}
 @Test void concurrentReservationsNeverExceedBudget()throws Exception{
  try(var executor=Executors.newVirtualThreadPerTaskExecutor()){
   var calls=new ArrayList<Future<Boolean>>();for(int i=0;i<25;i++)calls.add(executor.submit(()->{try{guard.reserve("TEST_ENDPOINT");return true;}catch(ServiceProblem e){return false;}}));
   int successes=0;for(var f:calls)if(f.get())successes++;assertEquals(5,successes);
  }
  assertEquals(5,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class));assertThrows(ServiceProblem.class,()->guard.reserve("TEST_ENDPOINT"));assertDoesNotThrow(()->guard.reserve("OTHER_ENDPOINT"));
 }
 @Test void windowSurvivesMidnightAndFailuresCount(){
  for(int i=0;i<5;i++){long id=guard.reserve("TEST_ENDPOINT");guard.outcome(id,"TIMEOUT");}
  assertEquals(0,guard.remaining("TEST_ENDPOINT"));
  db.update("UPDATE nmc_call_attempt SET requested_at=clock_timestamp()-interval '25 hours'");assertDoesNotThrow(()->guard.reserve("TEST_ENDPOINT"));
 }
 @Test void oneLeaseAndLastNormalBatchSurviveNewStoreInstance(){
  UUID a=UUID.randomUUID(),b=UUID.randomUUID();assertTrue(store.acquireLease("REGION",a));assertFalse(store.acquireLease("REGION",b));
  var batch=new Batch(List.of(TestSupport.row("TEST1","14")),TestSupport.NOW,List.of());store.complete("REGION",batch,a);store.releaseLease("REGION",a);
  var freshStore=new JdbcHospitalStore(db,new JsonCodec(),new NmcFieldNormalizer(new JsonCodec()));assertEquals("14",freshStore.lastComplete("REGION").orElseThrow().items().getFirst().single("hvec"));
  assertTrue(store.acquireLease("REGION",b));store.markError("REGION","NMC_INVALID_XML");assertEquals(batch,store.lastComplete("REGION").orElseThrow());
 }
 @Test void confirmedAbsenceReplacesCurrentBatchButRetainsRawHistory(){
  var owner=UUID.randomUUID();store.acquireLease("REGION",owner);store.complete("REGION",new Batch(List.of(TestSupport.row("TEST1","14")),TestSupport.NOW,List.of()),owner);store.complete("REGION",new Batch(List.of(),TestSupport.NOW.plusSeconds(300),List.of()),owner);
  assertTrue(store.lastComplete("REGION").orElseThrow().items().isEmpty());assertEquals(1,db.queryForObject("SELECT count(*) FROM hospital_realtime_snapshot",Integer.class));
 }
 @Test void detailReadsOnlyCurrentObservationPointer(){
  UUID catalog=UUID.randomUUID();
  db.update("INSERT INTO nmc_region_mapping VALUES('REGION','Prefix','Stage1','Stage2','v1',true) ON CONFLICT(id) DO NOTHING");
  db.update("INSERT INTO hospital(hpid,name,address,latitude,longitude,main_phone,secondary_phone,region_id,raw_json,catalog_version,updated_at) VALUES('TEST1','Hospital','Address',37,127,'02-1','02-2','REGION','{}',?,?)",catalog,java.sql.Timestamp.from(TestSupport.NOW));
  db.update("INSERT INTO catalog_state VALUES(true,?,?)",catalog,java.sql.Timestamp.from(TestSupport.NOW));
  UUID owner=UUID.randomUUID();assertTrue(store.acquireLease("REGION",owner));
  store.complete("REGION",new Batch(List.of(TestSupport.row("TEST1","14")),TestSupport.NOW,List.of()),owner);
  assertEquals("14",store.current("TEST1","REGION").item().single("hvec"));assertEquals("02-2",store.findActiveByHpid("TEST1").orElseThrow().hospital().secondaryPhone());
  int callsBefore=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class);
  for(int i=0;i<5;i++){
   var response=detail.get("TEST1");assertEquals("Address",response.address());assertEquals("02-1",response.mainPhone().rawValue());
   assertEquals("dutyTel3",response.secondaryPhone().sourceField());assertEquals(14L,response.realtime().availableBeds().numericValue());
  }
  assertEquals(callsBefore,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class));
  store.complete("REGION",new Batch(List.of(),TestSupport.NOW.plusSeconds(300),List.of()),owner);
  var current=store.current("TEST1","REGION");assertEquals(Coverage.LIVE_NOT_PROVIDED,current.coverageStatus());assertNull(current.item());
 }
}
