package com.eroute.personalization;

import com.eroute.auth.AuthSettings;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.core.io.ClassPathResource;
import org.springframework.web.bind.annotation.*;

/** Compiled and packaged only by Maven development-auth. No member data dependency. */
@RestController
@ConditionalOnExpression("'${eroute.auth.environment:disabled}' == 'local' or '${eroute.auth.environment:disabled}' == 'test'")
public class DiseaseReviewPreviewController {
 public record Candidate(String id,String diseaseId,String departmentId,String relationType,String reviewStatus,String reviewClass,ReferenceData.MappingScope mappingScope,int version) {}
 public record Projection(String documentType,String referenceVersion,List<Candidate> mappings) {}
 private final Projection projection;
 public DiseaseReviewPreviewController(AuthSettings settings,DiseaseReference runtime) throws Exception {
  if(!Set.of("local","test").contains(settings.environment)) throw new IllegalStateException("PREVIEW_FORBIDDEN");
  var reference=new FileReferenceRepository(runtime.sourceResource()).read();
  JsonNode worksheet;
  String reviewResource="reference/review-classes-"+reference.datasetVersion().replace("eroute-disease-departments-","")+".json";
  try(var input=new ClassPathResource(reviewResource).getInputStream()){worksheet=ReferenceJson.mapper().readTree(input);}
  if(!reference.datasetVersion().equals(worksheet.path("referenceVersion").asText())) throw new IllegalStateException("PREVIEW_VERSION_MISMATCH");
  var classes=new HashMap<String,String>();
  for(var row:worksheet.path("mappings")) {
   String value=row.path("reviewClass").asText();
   if(!Set.of("BROAD_PARENT_REVIEW_REQUIRED","EXACT_CANONICAL_REVIEW_REQUIRED","REVIEW_REQUIRED").contains(value)||classes.put(row.path("mappingId").asText(),value)!=null) throw new IllegalStateException("INVALID_REVIEW_CLASS");
  }
  var candidates=new ArrayList<Candidate>();
  for(var m:reference.mappings()) if(m.reviewStatus().equals("DRAFT")&&m.relationType().equals("DIRECT")) {
   if(!classes.containsKey(m.id())) throw new IllegalStateException("MISSING_REVIEW_CLASS");
   candidates.add(new Candidate(m.id(),m.diseaseId(),m.departmentId(),m.relationType(),m.reviewStatus(),classes.get(m.id()),m.mappingScope(),m.version()));
  }
  projection=new Projection("DEVELOPMENT_REVIEW_PREVIEW",reference.datasetVersion(),List.copyOf(candidates));
 }
 @GetMapping("/api/v1/dev/reference/disease-departments-review-preview")
 public Projection get(){return projection;}
}
