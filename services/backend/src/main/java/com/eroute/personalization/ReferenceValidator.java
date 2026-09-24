package com.eroute.personalization;

import java.net.URI;
import java.text.Normalizer;
import java.time.Instant;
import java.util.*;
import static com.eroute.personalization.ReferenceData.*;

/** Structural validation is not medical approval. Approval is entered by a human reviewer. */
public final class ReferenceValidator {
 private ReferenceValidator() {}
 public static String key(String s){return Normalizer.normalize(s.strip(),Normalizer.Form.NFC);}
 private static void require(boolean valid){if(!valid)throw new IllegalArgumentException("INVALID_DISEASE_REFERENCE");}
 private static void text(String s){require(s!=null&&!s.isBlank());}
 private static void approval(Approval a,int version){require(a!=null&&a.version()==version);text(a.reviewer());Instant.parse(a.approvedAt());}
 private static void evidence(Evidence e){require(e!=null);text(e.sourceName());text(e.rawDepartmentText());require(e.notes()!=null);Instant.parse(e.checkedAt());var url=URI.create(e.sourceUrl());require(Set.of("https","http").contains(url.getScheme())&&url.getHost()!=null);}
 public static void validate(ReferenceData r){
  require(r.schemaVersion()==2&&"READY".equals(r.status()));
  text(r.datasetVersion());text(r.catalogVersion());text(r.vocabularyVersion());text(r.purpose());text(r.purposeVersion());
  require(r.diseases()!=null&&!r.diseases().isEmpty()&&r.departments()!=null&&!r.departments().isEmpty());
  require(r.mappings()!=null&&r.departmentAliases()!=null&&r.broadDepartmentNames()!=null);
  var diseases=new HashSet<String>();var departments=new HashMap<String,Department>();var terms=new HashMap<String,String>();
  for(var d:r.diseases()){
   text(d.id());text(d.displayName());text(d.category());require(d.version()>0&&diseases.add(d.id()));
   require(Set.of("ACTIVE","INACTIVE","RETIRED").contains(d.lifecycleStatus())&&d.active()==d.lifecycleStatus().equals("ACTIVE"));
   require(d.aliases()!=null);var names=new ArrayList<>(d.aliases());names.add(d.displayName());var local=new HashSet<String>();
   for(String name:names){text(name);String k=key(name).toLowerCase(Locale.ROOT);require(local.add(k));String owner=terms.putIfAbsent(k,d.id());require(owner==null||owner.equals(d.id()));}
  }
  var canonical=new HashSet<String>();
  for(var d:r.departments()){text(d.id());text(d.canonicalName());require(d.version()>0&&departments.putIfAbsent(d.id(),d)==null&&canonical.add(key(d.canonicalName())));}
  var ids=new HashSet<String>();var pairs=new HashSet<String>();
  for(var m:r.mappings()){
   text(m.id());require(ids.add(m.id())&&diseases.contains(m.diseaseId())&&departments.containsKey(m.departmentId()));
   require(pairs.add(m.diseaseId()+"|"+m.departmentId())&&m.version()>0&&m.evidence()!=null);
   require(Set.of("DIRECT","CONTEXTUAL","REVIEW_REQUIRED").contains(m.relationType()));
   require(Set.of("DRAFT","APPROVED","REJECTED","RETIRED").contains(m.reviewStatus()));
   m.evidence().forEach(ReferenceValidator::evidence);
   if(m.reviewStatus().equals("APPROVED")){require(!m.evidence().isEmpty());approval(m.approval(),m.version());}
   else require(m.approval()==null);
  }
  var aliases=new HashSet<String>();
  for(var a:r.departmentAliases()){
   text(a.alias());require(departments.containsKey(a.departmentId())&&a.version()>0);
   require(!canonical.contains(key(a.alias()))&&aliases.add(key(a.alias())));
   require(Set.of("DRAFT","APPROVED","REJECTED","RETIRED").contains(a.reviewStatus()));
   if(a.reviewStatus().equals("APPROVED")){evidence(a.evidence());approval(a.approval(),a.version());}else require(a.approval()==null);
  }
  for(String broad:r.broadDepartmentNames())require(canonical.contains(key(broad)));
 }
 /** Compare immutable versions before publication; omission is not retirement. */
 public static void transition(ReferenceData previous,ReferenceData next){
  validate(previous);validate(next);require(!previous.datasetVersion().equals(next.datasetVersion()));
  for(var old:previous.diseases()){
   var d=next.diseases().stream().filter(x->x.id().equals(old.id())).findFirst().orElseThrow();
   require(d.equals(old)||d.version()>old.version());
   require(!old.lifecycleStatus().equals("RETIRED")||d.lifecycleStatus().equals("RETIRED"));
  }
  for(var old:previous.departments()){
   var d=next.departments().stream().filter(x->x.id().equals(old.id())).findFirst().orElseThrow();
   require(d.equals(old)||d.version()>old.version());
  }
  for(var old:previous.mappings()){
   var m=next.mappings().stream().filter(x->x.id().equals(old.id())).findFirst().orElseThrow();
   require(m.diseaseId().equals(old.diseaseId())&&m.departmentId().equals(old.departmentId()));
   boolean changed=!m.relationType().equals(old.relationType())||!m.evidence().equals(old.evidence())||m.mappingScope()!=old.mappingScope();
   if(changed)require(m.version()>old.version()&&m.reviewStatus().equals("DRAFT")&&m.approval()==null);
   else {
    require(m.version()>=old.version());
    if(m.version()>old.version())require(m.reviewStatus().equals("DRAFT"));
    if(old.reviewStatus().equals("APPROVED")&&m.reviewStatus().equals("APPROVED"))require(m.equals(old));
   }
   if(!old.reviewStatus().equals("APPROVED")&&m.reviewStatus().equals("APPROVED")) {
    require(old.reviewStatus().equals("DRAFT"));
    if(m.relationType().equals("DIRECT"))require(m.mappingScope()!=null);
   }
   require(!old.reviewStatus().equals("RETIRED")||m.reviewStatus().equals("RETIRED"));
  }
  for(var m:next.mappings())if(previous.mappings().stream().noneMatch(x->x.id().equals(m.id())))require(m.reviewStatus().equals("DRAFT"));
  for(var old:previous.departmentAliases()){
   var a=next.departmentAliases().stream().filter(x->key(x.alias()).equals(key(old.alias()))).findFirst().orElseThrow();
   require(a.departmentId().equals(old.departmentId()));
   if(!Objects.equals(a.evidence(),old.evidence())||!a.alias().equals(old.alias()))require(a.version()>old.version()&&a.reviewStatus().equals("DRAFT"));
   else {
    require(a.version()>=old.version());
    if(a.version()>old.version())require(a.reviewStatus().equals("DRAFT"));
    if(old.reviewStatus().equals("APPROVED")&&a.reviewStatus().equals("APPROVED"))require(a.equals(old));
   }
   if(!old.reviewStatus().equals("APPROVED")&&a.reviewStatus().equals("APPROVED"))require(old.reviewStatus().equals("DRAFT"));
   require(!old.reviewStatus().equals("RETIRED")||a.reviewStatus().equals("RETIRED"));
  }
  for(var a:next.departmentAliases())if(previous.departmentAliases().stream().noneMatch(x->key(x.alias()).equals(key(a.alias()))))require(a.reviewStatus().equals("DRAFT"));
  if(!previous.diseases().equals(next.diseases()))require(!previous.catalogVersion().equals(next.catalogVersion()));
  if(!previous.departments().equals(next.departments())||!previous.departmentAliases().equals(next.departmentAliases()))require(!previous.vocabularyVersion().equals(next.vocabularyVersion()));
 }
}
