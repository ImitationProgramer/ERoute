package com.eroute.emergency.infrastructure.nmc;

import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.Models.Region;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import java.util.*;

@Component
public class NmcRegionResolver {
 private final JdbcTemplate db;
 private final java.util.concurrent.ConcurrentMap<String,Object> validationLocks=new java.util.concurrent.ConcurrentHashMap<>();
 public NmcRegionResolver(JdbcTemplate db){this.db=db;}
 public String resolveId(String address){
  if(address==null)return null;
  return db.query("SELECT id FROM nmc_region_mapping WHERE ?=address_prefix OR starts_with(?,address_prefix||' ') ORDER BY length(address_prefix) DESC LIMIT 1",(rs,n)->rs.getString(1),address,address).stream().findFirst().orElse(null);
 }
 public Region requestRegion(Region region,String endpoint){
  return db.query("""
   SELECT target.id,target.stage1,target.stage2 FROM nmc_region_mapping admin
   LEFT JOIN nmc_region_query_mapping m ON m.region_id=admin.id AND m.endpoint=?
   JOIN nmc_region_mapping target ON target.id=COALESCE(m.request_region_id,admin.id)
   WHERE admin.id=?
   """,(rs,n)->new Region(rs.getString(1),rs.getString(2),rs.getString(3)),endpoint,region.id()).stream().findFirst().orElseThrow(()->new ServiceProblem("REGION_MAPPING_ERROR"));
 }
 public boolean verified(Region region){return Boolean.TRUE.equals(db.queryForObject("SELECT verified FROM nmc_region_mapping WHERE id=?",Boolean.class,region.id()));}
 public Set<String> expectedHpids(Region request){return new HashSet<>(db.queryForList("""
  SELECT h.hpid FROM hospital h
  LEFT JOIN nmc_region_query_mapping m ON m.region_id=h.region_id AND m.endpoint=?
  WHERE h.active AND COALESCE(m.request_region_id,h.region_id)=?
  """,String.class,NmcFieldNormalizer.LIST,request.id()));}
 public void markVerified(Region request){db.update("""
  UPDATE nmc_region_mapping r SET verified=true
  WHERE COALESCE((SELECT m.request_region_id FROM nmc_region_query_mapping m WHERE m.region_id=r.id AND m.endpoint=?),r.id)=?
  """,NmcFieldNormalizer.LIST,request.id());}
 /** Coalesce sibling-district validation within a server; each HTTP attempt still uses the DB guard. */
 public void verify(Region administrative,NmcPageCollector collector){
  verify(administrative,collector,0);
 }
 public void verify(Region administrative,NmcPageCollector collector,long deadlineNanos){
  var request=requestRegion(administrative,NmcFieldNormalizer.LIST);
  synchronized(validationLocks.computeIfAbsent(request.id(),id->new Object())) {
  if(Thread.currentThread().isInterrupted())throw new ServiceProblem("REQUEST_DEADLINE");
  if(verified(administrative))return;
  if(request.stage1().isBlank())throw new ServiceProblem("REGION_MAPPING_ERROR");
  var batch=collector.collect(NmcFieldNormalizer.LIST,"REGION_CHECK:"+request.id(),Map.of("Q0",request.stage1(),"Q1",request.stage2()),100,deadlineNanos);
  var received=new HashSet<String>();batch.items().forEach(i->received.add(i.single("hpid").strip()));
  var expected=expectedHpids(request);
  if(expected.isEmpty()||!received.containsAll(expected))throw new ServiceProblem("REGION_MAPPING_ERROR");
  markVerified(request);
  }
 }
}
