package com.eroute.emergency.domain.port;
import com.eroute.emergency.domain.model.BasicModels.BasicFetchedPage;
public interface HospitalBasicInfoProvider { BasicFetchedPage fetchPage(String scope,String hpid,int page,int size); }
