package com.eroute.personalization;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1/emergency-hospitals/departments")
public class HospitalDepartmentController {
 private final HospitalDepartmentQuery query;
 public HospitalDepartmentController(HospitalDepartmentQuery query){this.query=query;}
 @PostMapping("/query") public Map<String,Object> query(@RequestBody Map<String,Object> input){
  if(!input.keySet().equals(Set.of("hpids"))||!(input.get("hpids") instanceof List<?> ids)||ids.stream().anyMatch(id->!(id instanceof String)))throw new IllegalArgumentException("INVALID_HPID_BATCH");
  return query.query(ids.stream().map(String.class::cast).toList());
 }
}
