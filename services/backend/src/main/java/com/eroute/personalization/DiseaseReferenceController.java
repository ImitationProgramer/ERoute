package com.eroute.personalization;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1/reference")
public class DiseaseReferenceController {
 private final DiseaseReference reference;
 public DiseaseReferenceController(DiseaseReference reference){this.reference=reference;}
 @GetMapping("/disease-departments") public DiseaseReference.ReferenceResponse get(){return reference.response();}
}
