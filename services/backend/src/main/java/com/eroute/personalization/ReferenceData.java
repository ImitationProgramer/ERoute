package com.eroute.personalization;

import java.util.List;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.annotation.JsonDeserialize;

/** Storage-independent reference domain. Contains public terminology, never member data. */
public record ReferenceData(int schemaVersion, String datasetVersion, String catalogVersion,
 String vocabularyVersion, String purpose, String purposeVersion, String status,
 boolean publicMapApproved, List<Disease> diseases, List<Department> departments,
 List<Mapping> mappings, List<DepartmentAlias> departmentAliases, List<String> broadDepartmentNames) {
 public record Disease(String id, String displayName, List<String> aliases, String category,
  boolean active, String lifecycleStatus, int version) {}
 public record Department(String id, String canonicalName, boolean active, int version) {}
 public record Evidence(String sourceName, String sourceUrl, String checkedAt, String rawDepartmentText, String notes) {}
 public record Approval(String reviewer, String approvedAt, int version) {}
 public enum MappingScope { EXACT_CANONICAL, BROAD_PARENT }
 @JsonDeserialize(using=MappingDeserializer.class)
 public record Mapping(String id, String diseaseId, String departmentId, String relationType,
  String reviewStatus, List<Evidence> evidence, Approval approval, int version,
  @JsonInclude(JsonInclude.Include.NON_NULL) MappingScope mappingScope) {
  public Mapping(String id,String diseaseId,String departmentId,String relationType,String reviewStatus,
   List<Evidence> evidence,Approval approval,int version) {
   this(id,diseaseId,departmentId,relationType,reviewStatus,evidence,approval,version,null);
  }
 }
 public record DepartmentAlias(String alias, String departmentId, String reviewStatus,
  Evidence evidence, Approval approval, int version) {}
 public ReferenceData published() {
  return new ReferenceData(schemaVersion,datasetVersion,catalogVersion,vocabularyVersion,purpose,purposeVersion,
   status,publicMapApproved,diseases,departments,mappings.stream().filter(m->m.reviewStatus().equals("APPROVED")).toList(),
   departmentAliases.stream().filter(a->a.reviewStatus().equals("APPROVED")).toList(),broadDepartmentNames);
 }
}
