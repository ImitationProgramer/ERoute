package com.eroute.emergency.domain.port;
import com.eroute.emergency.domain.model.Models.*;
public interface EmergencyHospitalProvider {
 RegionObservation fetchRealtimeBeds(Region region);
 default RegionObservation fetchRealtimeBeds(Region region,long deadlineNanos){return fetchRealtimeBeds(region);}
}
