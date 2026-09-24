package com.eroute.emergency.api;
import com.eroute.emergency.application.EmergencyHospitalService;
import com.eroute.emergency.application.HospitalDetailService;
import com.eroute.emergency.domain.model.Models.*;
import org.springframework.web.bind.annotation.*;
import jakarta.validation.Valid;
import com.eroute.emergency.api.dto.SearchRequestDto;
@RestController
@RequestMapping("/api/v1")
public class EmergencyHospitalController {
 private final EmergencyHospitalService service;private final HospitalDetailService detail;
 public EmergencyHospitalController(EmergencyHospitalService service,HospitalDetailService detail){this.service=service;this.detail=detail;}
 @GetMapping("/readyz") public org.springframework.http.ResponseEntity<java.util.Map<String,String>> ready(){boolean ready=service.mapConfig().coverageBounds()!=null;return org.springframework.http.ResponseEntity.status(ready?200:503).body(java.util.Map.of("status",ready?"READY":"CATALOG_NOT_READY"));}
 @GetMapping("/map-config") public MapConfig mapConfig(){return service.mapConfig();}
 @PostMapping("/emergency-hospitals/search") public SearchResponse search(@RequestBody @Valid SearchRequestDto request){return service.search(request.domain());}
 @GetMapping("/emergency-hospitals/{hpid}") public HospitalDetail detail(@PathVariable String hpid){return detail.get(hpid);}
}
