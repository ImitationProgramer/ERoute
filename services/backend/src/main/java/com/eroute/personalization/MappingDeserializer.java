package com.eroute.personalization;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.util.List;
import static com.eroute.personalization.ReferenceData.*;

/** Only mappingScope is optional. Preserve strict legacy required-field decoding. */
public final class MappingDeserializer extends JsonDeserializer<Mapping> {
 public record Fields(String id,String diseaseId,String departmentId,String relationType,
  String reviewStatus,List<Evidence> evidence,Approval approval,int version) {}
 @Override public Mapping deserialize(JsonParser parser,DeserializationContext context) throws IOException {
  JsonNode value=parser.getCodec().readTree(parser);
  if(!(value instanceof ObjectNode node)) throw JsonMappingException.from(parser,"INVALID_MAPPING");
  JsonNode scope=node.remove("mappingScope");
  MappingScope parsed=null;
  if(scope!=null&&!scope.isNull()) {
   if(!scope.isTextual()) throw JsonMappingException.from(parser,"INVALID_MAPPING_SCOPE");
   try {parsed=MappingScope.valueOf(scope.textValue());}
   catch(IllegalArgumentException e){throw JsonMappingException.from(parser,"INVALID_MAPPING_SCOPE");}
  }
  Fields fields=parser.getCodec().treeToValue(node,Fields.class);
  return new Mapping(fields.id(),fields.diseaseId(),fields.departmentId(),fields.relationType(),
   fields.reviewStatus(),fields.evidence(),fields.approval(),fields.version(),parsed);
 }
}
