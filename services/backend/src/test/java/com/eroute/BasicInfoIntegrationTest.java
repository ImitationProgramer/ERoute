package com.eroute;
import com.eroute.emergency.application.HospitalBasicInfoSyncService;
import com.eroute.emergency.domain.port.HospitalBasicInfoProvider;
import com.eroute.emergency.infrastructure.nmc.*;
import com.eroute.emergency.infrastructure.persistence.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
@SpringBootTest(properties={"eroute.call-budget=2","eroute.requests-per-second=100","eroute.key-alias=basic-test","eroute.nmc-key=fake","eroute.jobs-enabled=false"})
class BasicInfoIntegrationTest {
 static PostgreSQLContainer<?> container;
 @DynamicPropertySource static void db(DynamicPropertyRegistry r){String external=System.getenv("EROUTE_TEST_JDBC_URL");if(external==null){container=new PostgreSQLContainer<>("postgres:16-alpine");container.start();r.add("spring.datasource.url",container::getJdbcUrl);r.add("spring.datasource.username",container::getUsername);r.add("spring.datasource.password",container::getPassword);}else{r.add("spring.datasource.url",()->external);r.add("spring.datasource.username",()->System.getenv().getOrDefault("EROUTE_TEST_DB_USER","eroute"));r.add("spring.datasource.password",()->System.getenv().getOrDefault("EROUTE_TEST_DB_PASSWORD",""));}}
 @Autowired com.eroute.emergency.application.HospitalCatalogSyncService catalog;@Autowired com.eroute.emergency.application.HospitalDetailService detail;@Autowired JdbcTemplate db;@Autowired HospitalBasicInfoSyncService sync;@Autowired JdbcHospitalBasicInfoStore basic;@Autowired JdbcHospitalStore store;@Autowired NmcCallBudgetGuard guard;@Autowired NmcBasicInfoDiscoveryProbe probe;@Autowired NmcXmlParser parser;
 @Autowired com.eroute.personalization.HospitalDepartmentQuery departmentQuery;
 @MockitoBean HospitalBasicInfoProvider provider;
 @BeforeEach void resetDb(){assertTrue(db.queryForObject("SELECT current_database()",String.class).endsWith("_test")||db.queryForObject("SELECT current_database()",String.class).equals("test"));db.execute("TRUNCATE hospital_basic_info_state,hospital_basic_info_dataset_member,hospital_department,hospital_operating_hours,hospital_basic_info_snapshot,provider_sync_work,provider_sync_run,discovery_result,hospital,catalog_state,nmc_call_attempt,nmc_budget_block CASCADE");reset(provider);UUID catalog=UUID.randomUUID();db.update("INSERT INTO catalog_state VALUES(true,?,clock_timestamp())",catalog);db.update("INSERT INTO discovery_result(passed,mode,page_size,report,pdf_sha256,endpoint) VALUES(true,'PER_HPID',10,'{\"probeVersion\":\"basic-probe-v1\"}',?,?)",probe.sourceHash(),NmcBasicInfoDiscoveryProbe.ENDPOINT);}
 void hospital(String h){db.update("INSERT INTO hospital(hpid,name,latitude,longitude,raw_json,catalog_version,updated_at) VALUES(?,?,37,127,'{}',(SELECT version FROM catalog_state),clock_timestamp())",h,"Hospital "+h);}
 com.eroute.emergency.domain.model.BasicModels.BasicFetchedPage response(String scope,String h,boolean absent){long attempt=guard.reserve(NmcBasicInfoDiscoveryProbe.ENDPOINT,scope);String xml="<response><header><resultCode>00</resultCode></header><body><items>"+(absent?"":"<item><hpid>"+h+"</hpid><dgidIdName>내과,외과,내과</dgidIdName><dutyTime1s>0900</dutyTime1s><dutyTime1c>1730</dutyTime1c></item>")+"</items><pageNo>1</pageNo><numOfRows>10</numOfRows><totalCount>"+(absent?0:1)+"</totalCount></body></response>";Instant now=Instant.now();long id=store.response(NmcBasicInfoDiscoveryProbe.ENDPOINT,scope,1,xml,now,"SUCCESS");guard.outcome(attempt,"SUCCESS");return new com.eroute.emergency.domain.model.BasicModels.BasicFetchedPage(parser.parse(xml,now),id);}
 void success(){doAnswer(a->response(a.getArgument(0),a.getArgument(1),false)).when(provider).fetchPage(anyString(),anyString(),anyInt(),anyInt());}
 UUID unfinished(){return db.queryForObject("SELECT id FROM provider_sync_run WHERE status<>'COMPLETE'",UUID.class);}
 @Test void budgetContinuationIsAtomicAndDetailNeverCallsProvider(){hospital("H1");hospital("H2");hospital("H3");success();assertThrows(RuntimeException.class,()->sync.synchronize(null));UUID run=unfinished();assertEquals("BUDGET_DEFERRED",db.queryForObject("SELECT status FROM provider_sync_run WHERE id=?",String.class,run));assertEquals(0,db.queryForObject("SELECT count(*) FROM hospital_basic_info_state",Integer.class));assertEquals("NOT_COLLECTED",basic.current("H1").orElseThrow().dataStatus());assertEquals(2,db.queryForObject("SELECT count(*) FROM hospital_basic_info_snapshot",Integer.class));db.update("UPDATE nmc_call_attempt SET requested_at=clock_timestamp()-interval '25 hours'");sync.synchronize(run);assertEquals(3,db.queryForObject("SELECT count(*) FROM hospital_basic_info_dataset_member",Integer.class));var info=basic.current("H1").orElseThrow();assertEquals(2,info.departments().size());assertEquals(3,db.queryForObject("SELECT count(*) FROM hospital_department WHERE snapshot_id=(SELECT id FROM hospital_basic_info_snapshot WHERE hpid='H1')",Integer.class));assertEquals("09:00",info.operatingHours().getFirst().open());int count=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class);clearInvocations(provider);for(int i=0;i<10;i++){assertEquals(2,detail.get("H1").basicInfo().departments().size());}verifyNoInteractions(provider);assertEquals(count,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class));}
 @Test void failedRefreshAndConfirmedAbsencePreservePreviousSnapshot(){hospital("H1");success();sync.synchronize(null);var before=basic.current("H1").orElseThrow();doThrow(new com.eroute.common.error.ServiceProblem("NMC_RESULT_ERROR")).when(provider).fetchPage(anyString(),anyString(),anyInt(),anyInt());assertThrows(RuntimeException.class,()->sync.synchronize(null));var failed=basic.current("H1").orElseThrow();assertEquals(before.fetchedAt(),failed.fetchedAt());assertTrue(failed.stale());assertEquals("ERROR",failed.fetchStatus().name());UUID run=unfinished();doAnswer(a->response(a.getArgument(0),a.getArgument(1),true)).when(provider).fetchPage(anyString(),anyString(),anyInt(),anyInt());sync.synchronize(run);var absent=basic.current("H1").orElseThrow();assertEquals(before.fetchedAt(),absent.fetchedAt());assertTrue(absent.staleReasons().contains("SOURCE_RECORD_NOT_PROVIDED"));assertEquals(2,absent.departments().size());}
 @Test void wrongHpidAndFirstCollectionAbsenceAreDifferent(){hospital("H1");doAnswer(a->response(a.getArgument(0),"OTHER",false)).when(provider).fetchPage(anyString(),anyString(),anyInt(),anyInt());assertThrows(RuntimeException.class,()->sync.synchronize(null));assertEquals(0,db.queryForObject("SELECT count(*) FROM hospital_basic_info_state",Integer.class));UUID run=unfinished();doAnswer(a->response(a.getArgument(0),a.getArgument(1),true)).when(provider).fetchPage(anyString(),anyString(),anyInt(),anyInt());sync.synchronize(run);var info=basic.current("H1").orElseThrow();assertEquals("NOT_PROVIDED",info.dataStatus());assertNull(info.fetchedAt());assertEquals(8,info.operatingHours().size());}
 void bulkProvider(boolean duplicate){
  doAnswer(a->{String scope=a.getArgument(0);int page=a.getArgument(2);long call=guard.reserve(NmcBasicInfoDiscoveryProbe.ENDPOINT,scope);int total=3;String h="H"+(duplicate&&page==2?1:page);String raw="<response><resultCode>00</resultCode><pageNo>"+page+"</pageNo><numOfRows>1</numOfRows><totalCount>"+total+"</totalCount><items><item><hpid>"+h+"</hpid></item></items></response>";Instant now=Instant.now();long id=store.response(NmcBasicInfoDiscoveryProbe.ENDPOINT,scope,page,raw,now,"SUCCESS");guard.outcome(call,"SUCCESS");return new com.eroute.emergency.domain.model.BasicModels.BasicFetchedPage(parser.parse(raw,now),id);}).when(provider).fetchPage(anyString(),isNull(),anyInt(),anyInt());
 }
 @Test void bulkPagesResumeWithRevalidationAndNoPartialPublish(){
  for(String h:List.of("H1","H2","H3"))hospital(h);db.update("UPDATE discovery_result SET mode='NATIONWIDE',page_size=1");bulkProvider(false);
  assertThrows(RuntimeException.class,()->sync.synchronize(null));UUID run=unfinished();assertEquals(0,db.queryForObject("SELECT count(*) FROM hospital_basic_info_state",Integer.class));
  db.update("UPDATE nmc_call_attempt SET requested_at=clock_timestamp()-interval '25 hours'");sync.synchronize(run);
  assertEquals(3,db.queryForObject("SELECT count(*) FROM hospital_basic_info_dataset_member",Integer.class));
  verify(provider).fetchPage(contains("REVALIDATE"),isNull(),eq(1),eq(1));
 }
 @Test void duplicateBulkHpidRetiresTheGenerationWithoutPublishing(){
  for(String h:List.of("H1","H2","H3"))hospital(h);db.update("UPDATE discovery_result SET mode='NATIONWIDE',page_size=1");bulkProvider(true);
  assertThrows(RuntimeException.class,()->sync.synchronize(null));assertEquals("SUPERSEDED",db.queryForObject("SELECT status FROM provider_sync_run",String.class));assertEquals(0,db.queryForObject("SELECT count(*) FROM hospital_basic_info_state",Integer.class));assertEquals(1,db.queryForObject("SELECT count(*) FROM hospital_basic_info_snapshot",Integer.class));
 }

 @Test void basicDiscoveryNeverGrantsCatalogPermission(){
  hospital("H1");var error=assertThrows(com.eroute.common.error.ServiceProblem.class,()->catalog.synchronize());assertEquals("DISCOVERY_GATE_NOT_PASSED",error.code());verifyNoInteractions(provider);assertEquals(1,db.queryForObject("SELECT count(*) FROM hospital",Integer.class));
 }

 @Test void departmentBatchReadsPublishedRawTokensAndHandlesMissingInactiveAndStale(){
  hospital("H1");hospital("H2");success();sync.synchronize(null);db.update("UPDATE hospital SET active=false WHERE hpid='H2'");hospital("H3");
  int calls=db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class);clearInvocations(provider);
  var result=departmentQuery.query(List.of("H1","H2","H3","MISSING"));var rows=(java.util.List<java.util.Map<String,Object>>)result.get("hospitals");
  assertEquals("PROVIDED",rows.get(0).get("recordStatus"));assertEquals(3,((List<?>)rows.get(0).get("departments")).size());assertEquals("INACTIVE",rows.get(1).get("recordStatus"));assertEquals("NOT_COLLECTED",rows.get(2).get("recordStatus"));assertEquals("NOT_FOUND",rows.get(3).get("recordStatus"));
  db.update("UPDATE hospital_basic_info_snapshot SET fetched_at=clock_timestamp()-interval '8 days'");var old=(java.util.List<java.util.Map<String,Object>>)departmentQuery.query(List.of("H1")).get("hospitals");assertEquals(true,old.getFirst().get("stale"));assertTrue(((List<?>)old.getFirst().get("staleReasons")).contains("TTL_EXPIRED"));verifyNoInteractions(provider);assertEquals(calls,db.queryForObject("SELECT count(*) FROM nmc_call_attempt",Integer.class));
 }

}
