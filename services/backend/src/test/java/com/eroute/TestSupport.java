package com.eroute;
import com.eroute.common.config.ERouteProperties;
import com.eroute.emergency.domain.model.Models.*;
import java.time.*;
import java.net.URI;
import java.util.*;
public class TestSupport {
 public static final Instant NOW=Instant.parse("2026-09-08T12:00:00Z");
 public static ERouteProperties properties(){return new ERouteProperties(List.of(10000,20000,50000),Duration.ofMinutes(5),Duration.ofDays(1),Duration.ofSeconds(2),URI.create("https://example.invalid"),"test","decoded","test",900,1000,4,100,Duration.ofSeconds(1),1048576,7);}
 public static RawItem row(String id,String beds){return new RawItem(Map.of("hpid",List.of(id),"hvec",List.of(beds),"hvs01",List.of("17"),"hvidate",List.of("20260908210000")));}
}
