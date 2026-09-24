package com.eroute.auth;

import static com.eroute.auth.AuthData.*;
import java.util.*;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class AuthController {
 private final AuthService auth; private final PasswordAuthService passwords;
 public AuthController(AuthService auth,PasswordAuthService passwords){this.auth=auth;this.passwords=passwords;}
 public record PasswordRequest(String phone,String password,String termsVersion,boolean termsAccepted,boolean age14OrOlder){@Override public String toString(){return "PasswordRequest[redacted]";}}
 private PasswordRequest passwordRequest(Map<String,Object> r,boolean signup){
  com.eroute.memberhealth.HealthService.only(r,signup?Set.of("phone","password","termsVersion","termsAccepted","age14OrOlder"):Set.of("phone","password"));
  if(!(r.get("phone") instanceof String)||!(r.get("password") instanceof String))throw problem("INVALID_AUTH_REQUEST",400);
  return new PasswordRequest((String)r.get("phone"),(String)r.get("password"),r.get("termsVersion") instanceof String v?v:null,Boolean.TRUE.equals(r.get("termsAccepted")),Boolean.TRUE.equals(r.get("age14OrOlder")));
 }
 @PostMapping("/auth/signup") public Tokens signup(@RequestBody Map<String,Object> input){var r=passwordRequest(input,true);return passwords.signup(r.phone(),r.password(),r.termsVersion(),r.termsAccepted(),r.age14OrOlder());}
 @PostMapping("/auth/login") public Tokens login(@RequestBody Map<String,Object> input){var r=passwordRequest(input,false);return passwords.login(r.phone(),r.password());}
 @PostMapping("/auth/reauth") public Map<String,Object> reauth(@RequestBody Map<String,Object> r,Authentication a){com.eroute.memberhealth.HealthService.only(r,Set.of("password"));if(!(r.get("password") instanceof String password))throw problem("INVALID_AUTH_REQUEST",400);return passwords.reauth(principal(a),password);}
 public record Start(String phone,String challenge,String purpose){}
 public record Complete(String termsVersion,boolean confirmPhoneChange){}
 public record Refresh(String refreshToken){@Override public String toString(){return "Refresh[redacted]";}}
 public record Logout(String logoutProof){@Override public String toString(){return "Logout[redacted]";}}
 public static Principal principal(Authentication a){if(a==null||!(a.getPrincipal() instanceof Principal p))throw problem("AUTH_REQUIRED",401);return p;}
 private static Principal optional(Authentication a){return a!=null&&a.getPrincipal() instanceof Principal p?p:null;}
 @PostMapping("/auth/transactions") public Map<String,Object> start(@RequestBody Start r,Authentication a){return auth.start(r.phone(),r.challenge(),r.purpose()==null?"LOGIN":r.purpose(),optional(a));}
 @GetMapping("/auth/transactions/{id}") public Map<String,Object> status(@PathVariable UUID id,@RequestHeader("X-Verification-Proof")String proof){return auth.status(id,proof);}
 @DeleteMapping("/auth/transactions/{id}") public void cancel(@PathVariable UUID id,@RequestHeader("X-Verification-Proof")String proof){auth.cancel(id,proof);}
 @PostMapping("/auth/transactions/{id}/complete") public Tokens complete(@PathVariable UUID id,@RequestHeader("X-Verification-Proof")String proof,@RequestHeader("Idempotency-Key")String key,@RequestBody Complete r,Authentication a){return auth.complete(id,proof,key,r.termsVersion(),r.confirmPhoneChange(),optional(a));}
 @PostMapping("/auth/refresh") public Tokens refresh(@RequestBody Refresh r,@RequestHeader("Idempotency-Key")String key){return auth.refresh(r.refreshToken(),key);}
 @PostMapping("/auth/logout") public void logout(@RequestBody Logout r){auth.logout(r.logoutProof());}
 @PostMapping("/auth/logout-all") public void all(Authentication a){auth.logoutAll(principal(a));}
 @GetMapping("/me") public Map<String,Object> me(Authentication a){return auth.me(principal(a));}
 @PostMapping("/me/activity") public void activity(Authentication a){auth.activity(principal(a));}
 @PostMapping("/me/phone-change") public Tokens phone(@RequestBody PhoneChange r,@RequestHeader("X-Verification-Proof")String proof,@RequestHeader("Idempotency-Key")String key,Authentication a){return auth.changePhone(r.transactionId(),proof,key,principal(a));}
 public record PhoneChange(UUID transactionId){}
 @GetMapping("/ops/status") public Map<String,String> ops(){return Map.of("status","AVAILABLE");}
}
