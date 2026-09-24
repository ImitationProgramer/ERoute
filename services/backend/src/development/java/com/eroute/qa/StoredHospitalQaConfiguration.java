package com.eroute.qa;
import com.eroute.emergency.domain.port.*;
import com.eroute.emergency.domain.model.Models.*;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.*;

/** Isolated QA only. Never invokes a provider or refresh/ledger write. */
@Configuration(proxyBeanMethods=false)
@ConditionalOnProperty(name="eroute.qa.stored-only",havingValue="true")
@ConditionalOnExpression("'${eroute.auth.environment:disabled}' == 'local' or '${eroute.auth.environment:disabled}' == 'test'")
public class StoredHospitalQaConfiguration {
 public StoredHospitalQaConfiguration(com.eroute.common.config.ERouteProperties config,
   com.eroute.common.config.BasicInfoProperties basic,
   @org.springframework.beans.factory.annotation.Value("${eroute.jobs-enabled:true}") boolean jobs) {
  if(jobs||basic.schedulerEnabled()||!config.nmcKey().isBlank())
   throw new IllegalStateException("STORED_QA_REQUIRES_COLLECTION_DISABLED");
 }
 @Bean org.springframework.boot.web.servlet.FilterRegistrationBean<jakarta.servlet.Filter> storedQaHeader() {
  var registration=new org.springframework.boot.web.servlet.FilterRegistrationBean<jakarta.servlet.Filter>();
  registration.setFilter((request,response,chain)->{
   ((jakarta.servlet.http.HttpServletResponse)response).setHeader("X-ERoute-Stored-QA","true");
   chain.doFilter(request,response);
  });
  return registration;
 }
 @Bean @Primary EmergencyHospitalProvider storedHospitalQaProvider(HospitalObservationRepository observations) {
  return region -> new RegionObservation(observations.lastComplete(region.id()).orElse(null),
    Refresh.NOT_REQUESTED,observations.lastAttemptAt(region.id()),null);
 }
}
