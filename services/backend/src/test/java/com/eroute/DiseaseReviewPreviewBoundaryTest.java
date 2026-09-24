package com.eroute;
import com.eroute.auth.AuthSettings;
import com.eroute.personalization.*;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.core.env.MapPropertySource;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
class DiseaseReviewPreviewBoundaryTest {
 @Test void productionEnvironmentHasNoBeanEvenInDevelopmentArtifact() throws Exception {
  Class<?> type;try{type=Class.forName("com.eroute.personalization.DiseaseReviewPreviewController");}catch(ClassNotFoundException e){return;}
  for(String environment:List.of("production","disabled","local","test")){
   try(var context=new AnnotationConfigApplicationContext()){
    context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("test",Map.of("eroute.auth.environment",environment)));
    context.register(AuthSettings.class,DiseaseReference.class,type);
    try{context.register(Class.forName("com.eroute.personalization.DevelopmentDiseaseReference"));}catch(ClassNotFoundException ignored){}
    context.refresh();
    assertEquals(Set.of("local","test").contains(environment),!context.getBeansOfType(type).isEmpty());
    if(Set.of("local","test").contains(environment)){
     var projection=ReferenceJson.mapper().valueToTree(type.getMethod("get").invoke(context.getBean(type)));
     var worksheet=ReferenceJson.mapper().readTree(java.nio.file.Files.readString(java.nio.file.Path.of("../../docs/qa/disease-evidence-v04-2026-09-18/review-inputs.json")));
     for(var m:projection.path("mappings")){
      var row=java.util.stream.StreamSupport.stream(worksheet.path("mappings").spliterator(),false).filter(r->r.path("mappingId").equals(m.path("id"))).findFirst().orElseThrow();
      assertEquals(row.path("reviewClass"),m.path("reviewClass"));
     }
    }
   }
  }
 }
}
