package com.eroute.auth;

import static com.eroute.auth.AuthData.problem;
import com.ibm.icu.text.Normalizer2;
import java.nio.charset.StandardCharsets;
import java.io.*;
import java.util.*;
import java.util.concurrent.Semaphore;
import java.util.function.Supplier;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;

public final class PasswordPolicy {
 public static final String VERSION="nfc-codepoints-v1", TERMS="signup-password-v1";
 private static final Argon2PasswordEncoder ENCODER=new Argon2PasswordEncoder(16,32,1,19456,2);
 private static final Semaphore HASH_SLOTS=new Semaphore(4);
 private static final Set<String> BLOCKED=load();
 private static final String DUMMY=ENCODER.encode(UUID.randomUUID().toString());
 private PasswordPolicy(){}
 private static Set<String> load(){
  try(var stream=PasswordPolicy.class.getResourceAsStream("/auth/blocked-passwords-v1.txt")){
   if(stream==null)throw new IllegalStateException("PASSWORD_BLOCKLIST_REQUIRED");
   return new HashSet<>(new BufferedReader(new InputStreamReader(stream,StandardCharsets.UTF_8)).lines().filter(s->!s.startsWith("#")).toList());
  }catch(IOException e){throw new IllegalStateException("PASSWORD_BLOCKLIST_UNAVAILABLE");}
 }
 public static String phone(String raw){
  if(raw==null||raw.length()>40)throw problem("INVALID_PHONE",400);
  String value=raw.replace(" ","").replace("-","");
  if(!value.matches("010[0-9]{8}"))throw problem("INVALID_PHONE",400);
  return value;
 }
 public static String normalize(String raw){
  if(raw==null||raw.length()>4096)throw problem("INVALID_PASSWORD",400);
  for(int i=0;i<raw.length();i++){
   char c=raw.charAt(i);
   if(Character.isHighSurrogate(c)){if(++i>=raw.length()||!Character.isLowSurrogate(raw.charAt(i)))throw problem("INVALID_PASSWORD",400);}
   else if(Character.isLowSurrogate(c))throw problem("INVALID_PASSWORD",400);
  }
  String value=Normalizer2.getNFCInstance().normalize(raw);
  int count=value.codePointCount(0,value.length());
  if(count<15||count>128)throw problem("INVALID_PASSWORD",400);
  return value;
 }
 public static void strong(String normalized){
  if(BLOCKED.contains(normalized)||normalized.codePoints().distinct().count()==1)throw problem("WEAK_PASSWORD",400);
 }
 private static <T>T bounded(Supplier<T> work){
  if(!HASH_SLOTS.tryAcquire())throw problem("AUTH_HASH_BUSY",429);
  try{return work.get();}finally{HASH_SLOTS.release();}
 }
 public static String hash(String normalized){return bounded(()->ENCODER.encode(normalized));}
 public static boolean matches(String normalized,String hash){return bounded(()->ENCODER.matches(normalized,hash==null?DUMMY:hash));}
}
