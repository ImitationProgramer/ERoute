package com.eroute.emergency.application;
import com.eroute.common.config.ERouteProperties;
import com.eroute.common.error.ServiceProblem;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.emergency.domain.port.*;
import java.time.Clock;
import java.util.*;
import org.springframework.stereotype.Service;
@Service
public class HospitalDetailService {
 private final HospitalRepository hospitals;private final HospitalObservationRepository observations;
 private final HospitalBasicInfoRepository basicInfos;
 private final EmergencyHospitalService realtime;private final ERouteProperties config;private final Clock clock;
 public HospitalDetailService(HospitalRepository hospitals,HospitalObservationRepository observations,EmergencyHospitalService realtime,ERouteProperties config,Clock clock,HospitalBasicInfoRepository basicInfos){
  this.basicInfos=basicInfos;this.hospitals=hospitals;this.observations=observations;this.realtime=realtime;this.config=config;this.clock=clock;
 }
 public HospitalDetail get(String rawHpid){
  if(rawHpid==null||rawHpid.isBlank()||rawHpid.length()>100)throw new IllegalArgumentException("Hospital ID required");
  String hpid=rawHpid.strip();
  HospitalMaster source=hospitals.findActiveByHpid(hpid).orElseThrow(()->new ServiceProblem("HOSPITAL_NOT_FOUND",404));
  Hospital hospital=source.hospital();
  CurrentHospitalObservation current=hospital.region()==null
   ?new CurrentHospitalObservation(Coverage.LIVE_UNKNOWN,Refresh.NOT_REQUESTED,null,null,null,"REGION_MAPPING_ERROR")
   :observations.current(hpid,hospital.region().id());
  var classification=new LinkedHashMap<String,String>();classification.put("code",hospital.classCode());classification.put("name",hospital.className());
  var basicInfo=basicInfos.current(hpid).orElseGet(()->new HospitalBasicInfo(FetchStatus.NOT_REQUESTED,null,null,null,null,null,null,null));
  return new HospitalDetail(hospital.hpid(),hospital.name(),classification,hospital.address(),hospital.location(),
   contact("dutyTel1","대표전화1",hospital.mainPhone()),contact("dutyTel3","대표전화2",hospital.secondaryPhone()),
   source.updatedAt(),source.catalogVersion(),source.catalogFetchedAt(),source.catalogFetchedAt().plus(config.masterTtl()).isBefore(clock.instant()),
   realtime.present(current),basicInfo,clock.instant());
 }
 private ContactNumber contact(String field,String label,String value){return value==null||value.isBlank()?null:new ContactNumber(field,label,value);}
}
