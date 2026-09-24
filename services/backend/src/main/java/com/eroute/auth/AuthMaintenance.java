package com.eroute.auth;
import static com.eroute.auth.AuthData.*;
import java.time.*;
import java.util.*;
import org.springframework.boot.*;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Bounded retention and explicit key rotation; no medical plaintext in progress output. */
@Component @Order(100)
public class AuthMaintenance implements ApplicationRunner {
 private final JdbcTemplate db;private final SecretBox box;private final AuthSettings settings;private final Clock clock;
 public AuthMaintenance(JdbcTemplate db,SecretBox box,AuthSettings settings,Clock clock){this.db=db;this.box=box;this.settings=settings;this.clock=clock;}
 public void run(ApplicationArguments args){
  if(args.containsOption("auth-reencrypt")){if(!settings.enabled)throw new IllegalStateException("AUTH_KEYS_REQUIRED");box.validateRegistry();reencrypt();}
  if(args.containsOption("auth-retain"))retain();
 }
 @Scheduled(initialDelayString="PT30S",fixedDelayString="PT30S") public void retain(){
  if(!settings.enabled)return;Instant now=clock.instant();
  db.update("DELETE FROM verification_transaction WHERE expires_at<=? OR state='CANCELLED' OR (state='CONSUMED' AND completion_until<=?)",ts(now),ts(now));
  db.update("UPDATE session_token SET replay_cipher=NULL,replay_until=NULL WHERE replay_until<=?",ts(now));
  db.update("DELETE FROM session_token WHERE expires_at<=?",ts(now));
  db.update("DELETE FROM auth_session WHERE expires_at<=? AND NOT EXISTS(SELECT 1 FROM session_token t WHERE t.session_id=auth_session.id)",ts(now));
  db.update("DELETE FROM auth_rate_window WHERE window_at<?",ts(now.minusSeconds(120)));
  // Current grants remain evidence. Superseded or withdrawn records expire after 30 days.
  db.update("DELETE FROM consent_record c WHERE recorded_at<? AND (action='WITHDRAWN' OR EXISTS(SELECT 1 FROM consent_record newer WHERE newer.user_id=c.user_id AND newer.kind=c.kind AND newer.recorded_at>c.recorded_at))",ts(now.minus(Duration.ofDays(30))));
  // Never discard a restore exclusion before backup destruction has actually been confirmed.
  db.update("DELETE FROM health_deletion_ledger l WHERE retain_until<? AND NOT EXISTS(SELECT 1 FROM health_erasure e WHERE e.user_id=l.user_id AND e.erased_epoch>=l.consent_epoch AND e.backup_completed_at IS NULL)",ts(now));
 }
 public void reencrypt(){
  rotate("app_user","id","phone_cipher","account",r->"phone:"+r.get("id"));
  rotate("member_health_profile","user_id","body_cipher","health",r->"profile:"+r.get("user_id")+":"+r.get("consent_epoch"));
  rotate("member_medication","id","body_cipher","health",r->"medication:"+r.get("user_id")+":"+r.get("id")+":"+r.get("consent_epoch"));
  rotate("verification_transaction","id","phone_cipher","temporary",r->"transaction-phone:"+r.get("id"));
  rotate("verification_transaction","id","verified_cipher","temporary",r->"verification:"+r.get("id"));
  rotate("verification_transaction","id","completion_cipher","temporary",r->"completion:"+r.get("id"));
  rotate("session_token","digest","replay_cipher","temporary",r->"refresh:"+r.get("digest"));
 }
 private void rotate(String table,String id,String column,String purpose,java.util.function.Function<Map<String,Object>,String> context){
  String prefix="v1."+box.active(purpose)+".%";
  while(true){var rows=db.queryForList("SELECT * FROM "+table+" WHERE "+column+" IS NOT NULL AND "+column+" NOT LIKE ? LIMIT 100",prefix);if(rows.isEmpty())return;
   for(var r:rows){String old=string(r,column);String replacement=box.encrypt(purpose,context.apply(r),box.decrypt(purpose,context.apply(r),old));
    // A concurrent edit wins, and a deleted row is never recreated.
    db.update("UPDATE "+table+" SET "+column+"=? WHERE "+id+"=? AND "+column+"=?",replacement,r.get(id),old);
   }
  }
 }
}
