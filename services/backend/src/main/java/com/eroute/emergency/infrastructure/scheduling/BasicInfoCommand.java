package com.eroute.emergency.infrastructure.scheduling;
import com.eroute.emergency.infrastructure.nmc.NmcBasicInfoDiscoveryProbe;
import org.springframework.boot.*;
import org.springframework.stereotype.Component;
@Component
public class BasicInfoCommand implements ApplicationRunner {
 private final NmcBasicInfoDiscoveryProbe probe;
 private final com.eroute.emergency.application.HospitalBasicInfoSyncService sync;
 public BasicInfoCommand(NmcBasicInfoDiscoveryProbe probe,com.eroute.emergency.application.HospitalBasicInfoSyncService sync){this.probe=probe;this.sync=sync;}
 public void run(ApplicationArguments args){
  if(args.containsOption("sync-basic")||args.containsOption("resume-basic")){
   java.util.UUID resume=args.containsOption("resume-basic")?java.util.UUID.fromString(args.getOptionValues("resume-basic").getFirst()):null;
   System.out.println("BASIC_SYNC COMPLETE run="+sync.synchronize(resume));
  }
  if(args.containsOption("discover-basic")||args.containsOption("resume-basic-discovery")){
   Long resume=args.containsOption("resume-basic-discovery")?Long.valueOf(args.getOptionValues("resume-basic-discovery").getFirst()):null;
   var result=probe.run(resume);System.out.println("BASIC_DISCOVERY id="+result.get("discoveryId")+" status="+result.get("status")+" mode="+result.get("mode"));
  }
 }
}
