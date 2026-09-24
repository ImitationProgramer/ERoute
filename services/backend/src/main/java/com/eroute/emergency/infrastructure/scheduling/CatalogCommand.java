package com.eroute.emergency.infrastructure.scheduling;
import com.eroute.emergency.application.HospitalCatalogSyncService;
import org.springframework.boot.*;
import org.springframework.stereotype.Component;
@Component
public class CatalogCommand implements ApplicationRunner {
 private final HospitalCatalogSyncService sync;
 public CatalogCommand(HospitalCatalogSyncService sync){this.sync=sync;}
 public void run(ApplicationArguments args){if(args.containsOption("sync-catalog"))sync.synchronize();}
}
