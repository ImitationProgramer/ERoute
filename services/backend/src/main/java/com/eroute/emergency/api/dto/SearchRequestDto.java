package com.eroute.emergency.api.dto;
import com.eroute.emergency.domain.model.Models.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
public record SearchRequestDto(@NotNull @Valid Coordinate center,@NotNull CenterSource centerSource,@Valid Coordinate userLocation,Integer radiusMeters) {
 public record Coordinate(@NotNull Double latitude,@NotNull Double longitude){public Point point(){return new Point(latitude,longitude);}}
 public SearchRequest domain(){return new SearchRequest(center.point(),centerSource,userLocation==null?null:userLocation.point(),radiusMeters);}
}
