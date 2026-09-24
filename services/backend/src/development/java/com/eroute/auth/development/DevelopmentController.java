package com.eroute.auth.development;
import com.eroute.auth.AuthService;
import java.util.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.*;
@RestController
@ConditionalOnProperty(name="eroute.auth.provider",havingValue="development")
public class DevelopmentController {
 private final AuthService auth;public DevelopmentController(AuthService auth){this.auth=auth;}
 public record Evidence(String credential){@Override public String toString(){return "Evidence[redacted]";}}
 @PostMapping("/api/v1/auth/development/transactions/{id}/verify") public Map<String,Object> verify(@PathVariable UUID id,@RequestHeader("X-Verification-Proof")String proof,@RequestBody Evidence evidence){return auth.verify(id,proof,evidence.credential());}
}
