package com.eroute.auth;

import com.fasterxml.jackson.databind.*;
import com.eroute.common.error.ServiceProblem;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;

/** JCA authenticated encryption; key material is never stored in PostgreSQL. */
@Component
public class SecretBox {
 public static final List<String> PURPOSES=List.of("health","account","temporary","identity","session");
 private final JsonNode config; private final JdbcTemplate db; private final TransactionTemplate reserve;
 private final AuthSettings settings; private final SecureRandom random=new SecureRandom();
 private final ObjectMapper json=new ObjectMapper().findAndRegisterModules();
 public SecretBox(AuthSettings settings,JdbcTemplate db,PlatformTransactionManager tm){
  this.settings=settings;this.db=db;reserve=new TransactionTemplate(tm);reserve.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
  if(!settings.enabled){config=json.createObjectNode();return;}
  try {
   config=json.readTree(Files.readString(Path.of(settings.keyFile)));
   if(!settings.environment.equals(config.path("environment").asText()))throw new Exception();
   Set<String> materials=new HashSet<>();
   for(String purpose:PURPOSES){var ring=config.path(purpose);String active=ring.path("active").asText();
    if(!active.matches("[a-zA-Z0-9_-]{1,40}")||!ring.path("keys").has(active))throw new Exception();
    var names=ring.path("keys").fieldNames();int count=0;while(names.hasNext()){String id=names.next();byte[] key=decode(ring.path("keys").path(id).asText());if(!id.matches("[a-zA-Z0-9_-]{1,40}")||key.length!=32||!materials.add(Base64.getEncoder().encodeToString(key)))throw new Exception();count++;}if(count==0)throw new Exception();
   }
  } catch(Exception e){throw new IllegalStateException("INVALID_AUTH_KEY_FILE");}
 }
 public String active(String purpose){return config.path(purpose).path("active").asText();}
 public void validateRegistry(){
  if(!settings.enabled)return;
  for(String purpose:PURPOSES)for(String version:versions(purpose)){
   String fingerprint=sha256(encode(key(purpose,version)));
   db.update("INSERT INTO auth_key_registry VALUES(?,?,?,?) ON CONFLICT DO NOTHING",settings.environment,purpose,version,fingerprint);
   String stored=db.queryForObject("SELECT fingerprint FROM auth_key_registry WHERE environment=? AND purpose=? AND key_version=?",String.class,settings.environment,purpose,version);
   if(!fingerprint.equals(stored))throw new IllegalStateException("KEY_ID_MATERIAL_REPLACED");
  }
  for(var identity:db.queryForList("SELECT DISTINCT user_id,scope FROM verified_identity")){
   var existing=db.queryForList("SELECT key_version FROM verified_identity WHERE user_id=? AND scope=?",String.class,identity.get("user_id"),identity.get("scope"));
   if(Collections.disjoint(existing,versions("identity")))throw new IllegalStateException("UNMIGRATED_IDENTITY_KEY_REQUIRED");
  }
 }
 public List<String> versions(String purpose){List<String> ids=new ArrayList<>();config.path(purpose).path("keys").fieldNames().forEachRemaining(ids::add);return ids;}
 private byte[] key(String purpose,String version){try {String value=config.path(purpose).path("keys").path(version).asText();if(value.isEmpty())throw new Exception();return decode(value);}catch(Exception e){throw AuthData.problem("ENCRYPTED_DATA_UNAVAILABLE",503);}}
 public String token(){byte[] bytes=new byte[32];random.nextBytes(bytes);return encode(bytes);}
 public static String sha256(String value){try{return encode(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException("SHA256_UNAVAILABLE");}}
 public String mac(String purpose,String version,String value){try{Mac mac=Mac.getInstance("HmacSHA256");mac.init(new SecretKeySpec(key(purpose,version),"HmacSHA256"));return version+":"+encode(mac.doFinal((settings.environment+"\u0000"+purpose+"\u0000"+value).getBytes(StandardCharsets.UTF_8)));}catch(ServiceProblem e){throw e;}catch(Exception e){throw AuthData.problem("CRYPTO_UNAVAILABLE",503);}}
 public String mac(String purpose,String value){return mac(purpose,active(purpose),value);}
 public List<String> macs(String purpose,String value){return versions(purpose).stream().map(v->mac(purpose,v,value)).toList();}
 public String encrypt(String purpose,String context,String plaintext){
  String id=active(purpose), usageId=settings.environment+":"+purpose+":"+id;
  try {
   byte[] iv=new byte[12];
   boolean allocated=false;
   for(int attempt=0;attempt<4&&!allocated;attempt++){
    random.nextBytes(iv);String nonce=encode(iv);
    allocated=Boolean.TRUE.equals(reserve.execute(s->{
     db.update("INSERT INTO crypto_key_usage(key_id,encryptions) VALUES(?,0) ON CONFLICT DO NOTHING",usageId);
     if(db.update("UPDATE crypto_key_usage SET encryptions=encryptions+1 WHERE key_id=? AND encryptions<4294967296",usageId)!=1)throw AuthData.problem("CRYPTO_KEY_ROTATION_REQUIRED",503);
     return db.update("INSERT INTO crypto_nonce VALUES(?,?) ON CONFLICT DO NOTHING",usageId,nonce)==1;
    }));
   }
   if(!allocated)throw AuthData.problem("CRYPTO_NONCE_FAILURE",503);
   Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key(purpose,id),"AES"),new GCMParameterSpec(128,iv));
   cipher.updateAAD(aad(purpose,id,context));byte[] sealed=cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
   return String.join(".","v1",id,encode(iv),encode(Arrays.copyOf(sealed,sealed.length-16)),encode(Arrays.copyOfRange(sealed,sealed.length-16,sealed.length)));
  }catch(ServiceProblem e){throw e;}catch(Exception e){throw AuthData.problem("CRYPTO_UNAVAILABLE",503);}
 }
 public String decrypt(String purpose,String context,String envelope){
  try{String[] p=envelope.split("\\.",-1);if(p.length!=5||!p[0].equals("v1"))throw new Exception();byte[] iv=decode(p[2]),body=decode(p[3]),tag=decode(p[4]);if(iv.length!=12||tag.length!=16)throw new Exception();
   Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key(purpose,p[1]),"AES"),new GCMParameterSpec(128,iv));cipher.updateAAD(aad(purpose,p[1],context));byte[] sealed=Arrays.copyOf(body,body.length+tag.length);System.arraycopy(tag,0,sealed,body.length,tag.length);return new String(cipher.doFinal(sealed),StandardCharsets.UTF_8);
  }catch(Exception e){throw AuthData.problem("ENCRYPTED_DATA_UNAVAILABLE",503);}
 }
 private byte[] aad(String purpose,String id,String context){return ("ERoute|v1|"+settings.environment+"|"+purpose+"|"+id+"|"+context).getBytes(StandardCharsets.UTF_8);}
 public String json(Object value){try{return json.writeValueAsString(value);}catch(Exception e){throw AuthData.problem("SERIALIZATION_FAILED",503);}}
 public <T>T parse(String value,Class<T> type){try{return json.readValue(value,type);}catch(Exception e){throw AuthData.problem("ENCRYPTED_DATA_UNAVAILABLE",503);}}
 public static String encode(byte[] b){return Base64.getUrlEncoder().withoutPadding().encodeToString(b);}
 private static byte[] decode(String s){return Base64.getUrlDecoder().decode(s);}
}
