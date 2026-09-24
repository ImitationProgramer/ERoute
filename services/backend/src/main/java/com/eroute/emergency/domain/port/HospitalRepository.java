package com.eroute.emergency.domain.port;
import com.eroute.emergency.domain.model.Models.Catalog;
import com.eroute.emergency.domain.model.Models.HospitalMaster;
import java.util.Optional;
public interface HospitalRepository {
 Optional<Catalog> catalog();
 Optional<HospitalMaster> findActiveByHpid(String hpid);
}
