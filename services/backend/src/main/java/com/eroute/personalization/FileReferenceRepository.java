package com.eroute.personalization;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.core.io.ClassPathResource;

public final class FileReferenceRepository implements ReferenceRepository {
 private final String resource;
 public FileReferenceRepository(String resource){this.resource=resource;}
 public ReferenceData read(){try(var in=new ClassPathResource(resource).getInputStream()){
  var value=ReferenceJson.mapper().readValue(in,ReferenceData.class);ReferenceValidator.validate(value);return value;
 }catch(Exception e){throw new IllegalArgumentException("INVALID_DISEASE_REFERENCE");}}
}
