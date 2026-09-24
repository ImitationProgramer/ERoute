package com.eroute.personalization;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.*;

/** Strict file adapter; the domain validator itself does not depend on JSON. */
public final class ReferenceJson {
 private ReferenceJson() {}
 public static ObjectMapper mapper(){return new ObjectMapper()
  .enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION)
  .enable(DeserializationFeature.FAIL_ON_MISSING_CREATOR_PROPERTIES)
  .enable(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES);}
}
