package com.eroute.emergency.infrastructure.persistence;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.springframework.stereotype.Component;
@Component
public class JsonCodec {
 private final ObjectMapper mapper=new ObjectMapper().registerModule(new JavaTimeModule()).disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
 public String write(Object o){try{return mapper.writeValueAsString(o);}catch(Exception e){throw new IllegalStateException("JSON serialization failed");}}
 public <T>T read(String s,Class<T> type){try{return mapper.readValue(s,type);}catch(Exception e){throw new IllegalStateException("Stored JSON invalid");}}
 public ObjectMapper mapper(){return mapper;}
}
