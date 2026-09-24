package com.eroute.emergency.domain.policy;
import com.eroute.emergency.domain.model.Models.Point;
public final class GeoDistance {
 private GeoDistance(){}
 public static double meters(Point a,Point b){
  double lat=Math.toRadians(b.latitude()-a.latitude()),lon=Math.toRadians(b.longitude()-a.longitude());
  double x=Math.pow(Math.sin(lat/2),2)+Math.cos(Math.toRadians(a.latitude()))*Math.cos(Math.toRadians(b.latitude()))*Math.pow(Math.sin(lon/2),2);
  return 6371008.8*2*Math.asin(Math.sqrt(Math.min(1,Math.max(0,x))));
 }
}
