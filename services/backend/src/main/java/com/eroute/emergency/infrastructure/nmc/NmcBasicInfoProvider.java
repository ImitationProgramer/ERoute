package com.eroute.emergency.infrastructure.nmc;
import com.eroute.emergency.domain.port.HospitalBasicInfoProvider;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class NmcBasicInfoProvider implements HospitalBasicInfoProvider {
 private final NmcApiClient client;
 public NmcBasicInfoProvider(NmcApiClient client){this.client=client;}
 public com.eroute.emergency.domain.model.BasicModels.BasicFetchedPage fetchPage(String scope,String hpid,int page,int size){var params=new LinkedHashMap<String,String>();params.put("pageNo",""+page);params.put("numOfRows",""+size);if(hpid!=null)params.put("HPID",hpid);var response=client.fetch(NmcBasicInfoDiscoveryProbe.ENDPOINT,scope,params);return new com.eroute.emergency.domain.model.BasicModels.BasicFetchedPage(response.page(),response.responseId());}
}
