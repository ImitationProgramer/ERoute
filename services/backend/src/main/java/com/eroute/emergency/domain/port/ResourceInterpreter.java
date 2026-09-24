package com.eroute.emergency.domain.port;
import com.eroute.emergency.domain.model.Models.*;
import java.util.List;
public interface ResourceInterpreter {
 ResourceValue availableBeds(RawItem item);
 List<ResourceValue> referenceResources(RawItem item);
 SourceTime timestamp(String raw);
}
