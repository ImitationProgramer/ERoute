package db.migration;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.flywaydb.core.api.migration.BaseJavaMigration;
import org.flywaydb.core.api.migration.Context;

/** Versioned endpoint aliases, independent from the official address hierarchy. */
public class V5__endpoint_region_mapping extends BaseJavaMigration {
 @Override public void migrate(Context context) throws Exception {
  var c=context.getConnection();
  try(var s=c.createStatement()) {
   s.execute("CREATE TABLE nmc_region_query_mapping (region_id text NOT NULL REFERENCES nmc_region_mapping(id),endpoint text NOT NULL,request_region_id text NOT NULL REFERENCES nmc_region_mapping(id),source_version text NOT NULL,PRIMARY KEY(region_id,endpoint))");
  }
  try(var input=getClass().getClassLoader().getResourceAsStream("nmc/region-query-mappings.json")) {
   var data=new ObjectMapper().readTree(input);
   try(var insert=c.prepareStatement("INSERT INTO nmc_region_query_mapping SELECT ?,?,?,? WHERE EXISTS(SELECT 1 FROM nmc_region_mapping WHERE id=?) AND EXISTS(SELECT 1 FROM nmc_region_mapping WHERE id=?)")) {
    for(var mapping:data.path("mappings")) {
     String id=mapping.path("regionId").asText(),target=mapping.path("requestRegionId").asText();
     insert.setString(1,id);insert.setString(2,data.path("endpoint").asText());insert.setString(3,target);insert.setString(4,data.path("version").asText());insert.setString(5,id);insert.setString(6,target);insert.addBatch();
    }
    insert.executeBatch();
   }
  }
  // Changing validation scope requires fresh coverage evidence; never manufacture success.
  try(var s=c.createStatement()) {s.executeUpdate("UPDATE nmc_region_mapping SET verified=false WHERE id IN (SELECT region_id FROM nmc_region_query_mapping)");}
 }
}
