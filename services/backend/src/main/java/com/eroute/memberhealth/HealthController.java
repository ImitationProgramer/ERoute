package com.eroute.memberhealth;
import com.eroute.auth.AuthController;
import com.eroute.auth.AuthService;
import java.util.*;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/me")
public class HealthController {
 private final HealthService health;private final AuthService auth;
 public HealthController(HealthService health,AuthService auth){this.health=health;this.auth=auth;}
 @GetMapping("/conditions") public Map<String,Object> conditions(Authentication a){return health.conditions(AuthController.principal(a));}
 @PutMapping("/conditions") public Map<String,Object> saveConditions(Authentication a,@RequestBody Map<String,Object> r){var p=AuthController.principal(a);var result=health.saveConditions(p,r);auth.activity(p);return result;}
 @GetMapping("/map-disease-selection") public Map<String,Object> mapSelection(Authentication a){return health.mapSelection(AuthController.principal(a));}
 @PutMapping("/map-disease-selection") public Map<String,Object> saveMapSelection(Authentication a,@RequestBody Map<String,Object> r){var p=AuthController.principal(a);var result=health.saveMapSelection(p,r,false);auth.activity(p);return result;}
 @DeleteMapping("/map-disease-selection") public Map<String,Object> clearMapSelection(Authentication a,@RequestBody Map<String,Object> r){return health.saveMapSelection(AuthController.principal(a),r,true);}
 @GetMapping("/health-consent") public Map<String,Object> consent(Authentication a){return health.consentState(AuthController.principal(a));}
 @PostMapping("/health-consent") public Map<String,Object> grant(Authentication a,@RequestBody Grant r){var p=AuthController.principal(a);var result=health.grant(p,r.documentVersion(),r.epoch());auth.activity(p);return result;}
 public record Grant(String documentVersion,long epoch){}
 @GetMapping("/health-snapshot") public Map<String,Object> snapshot(Authentication a){var p=AuthController.principal(a);var result=health.snapshot(p);auth.activity(p);return result;}
 @GetMapping("/emergency-profile") public Map<String,Object> profile(Authentication a){var p=AuthController.principal(a);var result=health.profile(p);auth.activity(p);return result;}
 @PutMapping("/emergency-profile") public Map<String,Object> save(Authentication a,@RequestBody Map<String,Object> r){var p=AuthController.principal(a);var result=health.saveProfile(p,r,false);auth.activity(p);return result;}
 @DeleteMapping("/emergency-profile") public Map<String,Object> clear(Authentication a,@RequestBody Map<String,Object> r){return health.saveProfile(AuthController.principal(a),r,true);}
 @GetMapping("/medications") public List<Map<String,Object>> medications(Authentication a){var p=AuthController.principal(a);var result=health.medications(p);auth.activity(p);return result;}
 @GetMapping("/medications/{id}") public Map<String,Object> medication(Authentication a,@PathVariable UUID id){return health.medication(AuthController.principal(a),id);}
 @PostMapping("/medications") public Map<String,Object> add(Authentication a,@RequestBody Map<String,Object> r){var p=AuthController.principal(a);var result=health.saveMedication(p,null,r);auth.activity(p);return result;}
 @PutMapping("/medications/{id}") public Map<String,Object> edit(Authentication a,@PathVariable UUID id,@RequestBody Map<String,Object> r){var p=AuthController.principal(a);var result=health.saveMedication(p,id,r);auth.activity(p);return result;}
 @DeleteMapping("/medications/{id}") public void delete(Authentication a,@PathVariable UUID id,@RequestParam(required=false) Long consentEpoch,@RequestParam(required=false) Long version,@RequestParam(required=false) Long baseVersion){var input=new HashMap<String,Object>();input.put("consentEpoch",consentEpoch);input.put("version",version);input.put("baseVersion",baseVersion);health.deleteMedication(AuthController.principal(a),id,input);}
 public record Withdraw(long epoch){}
 @PostMapping("/health-consent/withdrawals") public Map<String,Object> withdraw(Authentication a,@RequestBody Withdraw r,@RequestHeader("Idempotency-Key")String key){return health.withdraw(AuthController.principal(a),r.epoch(),key);}
 @GetMapping("/health-consent/withdrawals") public List<Map<String,Object>> jobs(Authentication a){return health.erasures(AuthController.principal(a));}
 @GetMapping("/health-consent/withdrawals/{id}") public Map<String,Object> job(Authentication a,@PathVariable UUID id){return health.erasure(AuthController.principal(a),id);}
 @PostMapping("/health-consent/withdrawals/{id}/retry") public Map<String,Object> retry(Authentication a,@PathVariable UUID id){return health.retry(AuthController.principal(a),id);}
}
