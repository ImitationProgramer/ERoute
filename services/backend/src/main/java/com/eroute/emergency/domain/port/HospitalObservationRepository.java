package com.eroute.emergency.domain.port;
import com.eroute.emergency.domain.model.Models.*;
import java.time.Instant;
import java.util.Optional;
public interface HospitalObservationRepository {
 Optional<Batch> lastComplete(String regionId);
 Instant lastAttemptAt(String regionId);
 CurrentHospitalObservation current(String hpid,String regionId);
}
