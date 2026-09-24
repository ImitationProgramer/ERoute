package com.eroute.emergency.domain.port;
import com.eroute.emergency.domain.model.Models.HospitalBasicInfo;
import java.util.Optional;
/** Only published values are visible here. Sync writes staging through its transactional store. */
public interface HospitalBasicInfoRepository { Optional<HospitalBasicInfo> current(String hpid); }
