package com.eroute.personalization;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.web.bind.annotation.*;
@RestController
public class DiseaseCatalogController {
 private final DiseaseCatalog catalog;private final DiseaseReference reference;
 public DiseaseCatalogController(DiseaseCatalog catalog,DiseaseReference reference){this.catalog=catalog;this.reference=reference;}
 @GetMapping("/api/v1/reference/diseases") public java.util.Map<String,Object> get(){return new com.fasterxml.jackson.databind.ObjectMapper().convertValue(catalog.response(reference.availableNow()?reference.version():null),new com.fasterxml.jackson.core.type.TypeReference<java.util.Map<String,Object>>(){}); }
}
