package com.eroute.emergency.infrastructure.nmc;
import com.eroute.common.config.ERouteProperties;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.infrastructure.persistence.JdbcHospitalStore;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class NmcApiClient {
 private static final org.slf4j.Logger log=org.slf4j.LoggerFactory.getLogger(NmcApiClient.class);
 public record FetchedPage(Page page,long responseId){}
 private final ERouteProperties config;private final NmcCallBudgetGuard guard;private final NmcXmlParser parser;
 private final JdbcHospitalStore store;private final Clock clock;private final HttpClient http;private final io.micrometer.core.instrument.MeterRegistry metrics;
 public NmcApiClient(ERouteProperties config,NmcCallBudgetGuard guard,NmcXmlParser parser,JdbcHospitalStore store,Clock clock,io.micrometer.core.instrument.MeterRegistry metrics){
  this.metrics=metrics;this.config=config;this.guard=guard;this.parser=parser;this.store=store;this.clock=clock;
  http=HttpClient.newBuilder().connectTimeout(config.requestTimeout()).followRedirects(HttpClient.Redirect.NEVER).build();
 }
 public FetchedPage fetch(String endpoint,String scope,Map<String,String> parameters){return fetch(endpoint,scope,parameters,2);}
 public FetchedPage fetch(String endpoint,String scope,Map<String,String> parameters,int maxAttempts){
  return fetch(endpoint,scope,parameters,maxAttempts,0);
 }
 /** A nonzero deadline enables rate-slot admission only within the active search. */
 public FetchedPage fetch(String endpoint,String scope,Map<String,String> parameters,int maxAttempts,long deadlineNanos){
  if(maxAttempts<1||maxAttempts>2)throw new IllegalArgumentException("Invalid attempt allowance");
  if(config.nmcKey()==null||config.nmcKey().isBlank())throw new ServiceProblem("NMC_KEY_MISSING");
  for(int attempt=0;attempt<maxAttempts;attempt++){
   long id=reserveWithinSearch(endpoint,scope,deadlineNanos);metrics.counter("nmc.requests","endpoint",endpoint).increment();
   if(endpoint.equals(NmcFieldNormalizer.BEDS))store.markAttempt(scope);
   var safe=new TreeMap<String,String>();
   for(String field:List.of("Q0","Q1","STAGE1","STAGE2","pageNo","numOfRows"))if(parameters.containsKey(field))safe.put(field,parameters.get(field));
   log.info("nmc_request endpoint={} scope={} parameters={}",endpoint,scope,safe);
   try{
    var params=new LinkedHashMap<>(parameters);params.put("ServiceKey",config.nmcKey());
    String query=params.entrySet().stream().map(e->encode(e.getKey())+"="+encode(e.getValue())).collect(java.util.stream.Collectors.joining("&"));
    URI uri=URI.create(config.nmcBaseUrl().toString().replaceAll("/$","")+"/"+endpoint+"?"+query);
    Duration timeout=config.requestTimeout();
    if(deadlineNanos!=0){long left=deadlineNanos-System.nanoTime();if(left<=0)throw new ServiceProblem("REQUEST_DEADLINE");timeout=Duration.ofNanos(Math.min(timeout.toNanos(),left));}
    var request=HttpRequest.newBuilder(uri).timeout(timeout).GET().build();
    // ofByteArray honors request timeout; reject overlarge payloads before XML parsing.
    var response=http.send(request,HttpResponse.BodyHandlers.ofByteArray());
    if(response.body().length>config.maxResponseBytes())throw new ServiceProblem("NMC_RESPONSE_TOO_LARGE");
    String raw=new String(response.body(),StandardCharsets.UTF_8);Instant fetchedAt=clock.instant();
    // Never persist an echoed service key, even in gateway error bodies.
    raw=raw.replace(config.nmcKey(),"[REDACTED]").replace(encode(config.nmcKey()),"[REDACTED]");
    long rawId=store.response(endpoint,scope,Integer.parseInt(parameters.get("pageNo")),raw,fetchedAt,"HTTP_"+response.statusCode());
    log.info("nmc_http endpoint={} scope={} responseId={} status={}",endpoint,scope,rawId,response.statusCode());
    if(response.statusCode()!=200)throw new ServiceProblem(response.statusCode()>=500?"NMC_TRANSIENT_HTTP":"NMC_HTTP_ERROR");
    Page page=parser.parse(raw,fetchedAt);log.info("nmc_page endpoint={} scope={} responseId={} page={} total={} rows={}",endpoint,scope,rawId,page.pageNo(),page.totalCount(),page.items().size());guard.outcome(id,"SUCCESS");return new FetchedPage(page,rawId);
   }catch(InterruptedException e){Thread.currentThread().interrupt();guard.outcome(id,"INTERRUPTED");throw new ServiceProblem("REQUEST_DEADLINE");}
   catch(Exception e){
    String code=e instanceof ServiceProblem p?p.code():"NMC_TRANSPORT_ERROR";log.warn("nmc_failure endpoint={} scope={} code={}",endpoint,scope,code);guard.outcome(id,code);metrics.counter("nmc.failures","endpoint",endpoint,"code",code).increment();
    if(code.equals("NMC_QUOTA_EXCEEDED"))guard.block(endpoint);
    if(attempt+1<maxAttempts&&Set.of("NMC_TRANSIENT_HTTP","NMC_TRANSPORT_ERROR").contains(code)){
     try{Thread.sleep(600);}catch(InterruptedException interrupted){Thread.currentThread().interrupt();throw new ServiceProblem("REQUEST_DEADLINE");}continue;
    }throw new ServiceProblem(code);
   }
  }throw new ServiceProblem("NMC_TRANSPORT_ERROR");
 }
 private long reserveWithinSearch(String endpoint,String scope,long deadlineNanos){
  while(true){
   if(Thread.currentThread().isInterrupted()||(deadlineNanos!=0&&System.nanoTime()>=deadlineNanos))throw new ServiceProblem("REQUEST_DEADLINE");
   try{return guard.reserve(endpoint,scope);}
   catch(ServiceProblem e){
    // Rolling quota failures never wait or retry. Every eventual HTTP attempt reserves again.
    if(!e.code().equals("CALL_RATE_LIMIT")||deadlineNanos==0)throw e;
    long waitMillis=guard.rateDelayMillis(endpoint)+10;
    // Leave enough time for one normal HTTP attempt, rather than start a request at expiry.
    if(deadlineNanos-System.nanoTime()<=Duration.ofMillis(waitMillis).toNanos()+config.requestTimeout().toNanos())throw e;
    log.info("nmc_rate_wait endpoint={} scope={} waitMillis={}",endpoint,scope,waitMillis);
    try{Thread.sleep(waitMillis);}catch(InterruptedException interrupted){Thread.currentThread().interrupt();throw new ServiceProblem("REQUEST_DEADLINE");}
   }
  }
 }
 private static String encode(String s){return URLEncoder.encode(s,StandardCharsets.UTF_8);}
}
