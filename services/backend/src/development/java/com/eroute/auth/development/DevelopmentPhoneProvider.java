package com.eroute.auth.development;
import com.eroute.auth.*;
import com.eroute.auth.AuthData.Verified;
import static com.eroute.auth.AuthData.*;
import java.util.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name="eroute.auth.provider",havingValue="development")
public class DevelopmentPhoneProvider implements PhoneIdentityVerificationProvider {
 private final JdbcTemplate db;private final AuthSettings settings;
 public DevelopmentPhoneProvider(JdbcTemplate db,AuthSettings settings){this.db=db;this.settings=settings;if(!Set.of("local","test").contains(settings.environment))throw new IllegalStateException("DEVELOPMENT_AUTH_FORBIDDEN");}
 public String name(){return "development";}
 public String start(UUID id,String phone){return "development:"+id;}
 public Verified verifyResult(UUID id,String ref,String phone,String evidence){
  if(evidence==null||!evidence.matches("[A-Za-z0-9_-]{43}"))throw problem("VERIFICATION_FAILED",403);
  var rows=db.queryForList("SELECT subject,birth_date FROM dev_identity_fixture WHERE phone=? AND credential_hash=?",phone,SecretBox.sha256(evidence));if(rows.size()!=1)throw problem("VERIFICATION_FAILED",403);var row=rows.getFirst();
  return new Verified(id,ref,"development:"+settings.environment,string(row,"subject"),phone,((java.sql.Date)row.get("birth_date")).toLocalDate(),"DEVELOPMENT",settings.environment);
 }
}
