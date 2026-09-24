package com.eroute.emergency.infrastructure.nmc;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.Models.*;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class NmcPageCollector {
 private final NmcApiClient client;private final NmcCallBudgetGuard budget;
 public NmcPageCollector(NmcApiClient client,NmcCallBudgetGuard budget){this.client=client;this.budget=budget;}
 public Batch collect(String endpoint,String scope,Map<String,String> filters,int size){
  return collect(endpoint,scope,filters,size,0);
 }
 public Batch collect(String endpoint,String scope,Map<String,String> filters,int size,long deadlineNanos){
  var all=new ArrayList<RawItem>();var ids=new ArrayList<Long>();var hpids=new HashSet<String>();
  int total=-1,pages=1;java.time.Instant fetched=null;
  for(int number=1;number<=pages;number++){
   var parameters=new LinkedHashMap<>(filters);parameters.put("pageNo",Integer.toString(number));parameters.put("numOfRows",Integer.toString(size));
   var result=client.fetch(endpoint,scope,parameters,2,deadlineNanos);var page=result.page();
   if(number==1){total=page.totalCount();size=page.numOfRows();pages=Math.max(1,(int)Math.ceil(total/(double)size));
    if(budget.remaining(endpoint)<pages-1)throw new ServiceProblem("CALL_BUDGET_LIMIT");
   }
   if(page.pageNo()!=number||page.numOfRows()!=size||page.totalCount()!=total||page.items().size()!=Math.min(size,Math.max(0,total-(number-1)*size)))throw new ServiceProblem("NMC_INCOMPLETE_PAGINATION");
   for(var row:page.items()){String hpid=row.single("hpid");if(hpid==null||hpid.isBlank()||!hpids.add(hpid.strip()))throw new ServiceProblem("NMC_DUPLICATE_OR_MISSING_HPID");}
   all.addAll(page.items());ids.add(result.responseId());if(fetched==null)fetched=page.fetchedAt();
   if(number<pages)try{Thread.sleep(550);}catch(InterruptedException e){Thread.currentThread().interrupt();throw new ServiceProblem("REQUEST_DEADLINE");}
  }
  return new Batch(List.copyOf(all),fetched,List.copyOf(ids));
 }
}
