package com.eroute.emergency.infrastructure.nmc;
import com.eroute.common.config.ERouteProperties;
import com.eroute.common.error.ServiceProblem;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
@Component
public class NmcCallBudgetGuard {
 private final JdbcTemplate db;private final ERouteProperties config;
 public NmcCallBudgetGuard(JdbcTemplate db,ERouteProperties config){this.db=db;this.config=config;}
 @Transactional
 public long reserve(String endpoint){return reserve(endpoint,null);}
 @Transactional
 public long reserve(String endpoint,String scope){
  // Same lock name and rolling-window ledger as scripts/discover_nmc.py.
  db.queryForList("SELECT pg_advisory_xact_lock(hashtext(?))",config.keyAlias()+":"+endpoint);
  if(Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM nmc_budget_block WHERE key_alias=? AND endpoint=? AND blocked_until>clock_timestamp())",Boolean.class,config.keyAlias(),endpoint)))throw new ServiceProblem("CALL_BUDGET_LIMIT");
  Long used=db.queryForObject("SELECT count(*) FROM nmc_call_attempt WHERE key_alias=? AND endpoint=? AND requested_at>clock_timestamp()-interval '24 hours'",Long.class,config.keyAlias(),endpoint);
  if(used>=config.callBudget())throw new ServiceProblem("CALL_BUDGET_LIMIT");
  Long recent=db.queryForObject("SELECT count(*) FROM nmc_call_attempt WHERE key_alias=? AND endpoint=? AND requested_at>clock_timestamp()-interval '1 second'",Long.class,config.keyAlias(),endpoint);
  if(recent>=config.requestsPerSecond())throw new ServiceProblem("CALL_RATE_LIMIT");
  return db.queryForObject("INSERT INTO nmc_call_attempt(key_alias,endpoint,scope) VALUES(?,?,?) RETURNING id",Long.class,config.keyAlias(),endpoint,scope);
 }
 /** Read outside the reserve transaction; never hold an advisory lock while waiting. */
 public long rateDelayMillis(String endpoint){
  Long delay=db.queryForObject("SELECT GREATEST(1,CEIL(EXTRACT(EPOCH FROM (MIN(requested_at)+interval '1 second'-clock_timestamp()))*1000))::bigint FROM nmc_call_attempt WHERE key_alias=? AND endpoint=? AND requested_at>clock_timestamp()-interval '1 second'",Long.class,config.keyAlias(),endpoint);
  return delay==null?1:delay;
 }
 public void outcome(long id,String outcome){db.update("UPDATE nmc_call_attempt SET outcome=? WHERE id=?",outcome,id);}
 public void block(String endpoint){db.update("INSERT INTO nmc_budget_block VALUES(?,?,clock_timestamp()+interval '24 hours') ON CONFLICT(key_alias,endpoint) DO UPDATE SET blocked_until=excluded.blocked_until",config.keyAlias(),endpoint);}
 public long remaining(String endpoint){return Math.max(0,config.callBudget()-db.queryForObject("SELECT count(*) FROM nmc_call_attempt WHERE key_alias=? AND endpoint=? AND requested_at>clock_timestamp()-interval '24 hours'",Long.class,config.keyAlias(),endpoint));}
}
