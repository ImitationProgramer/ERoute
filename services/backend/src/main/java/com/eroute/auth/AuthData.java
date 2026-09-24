package com.eroute.auth;

import java.time.*;
import java.util.*;
import com.eroute.common.error.ServiceProblem;

public final class AuthData {
 private AuthData(){}
 public record Principal(UUID userId,UUID sessionId,String role,String source,String environment) {}
 public record Verified(UUID transactionId,String providerReference,String scope,String subject,String phone,LocalDate birthDate,String source,String environment) {
  @Override public String toString(){return "Verified[redacted]";}
 }
 public record Tokens(String accessToken,String refreshToken,String logoutProof,Instant accessExpiresAt,Instant sessionExpiresAt) {
  @Override public String toString(){return "Tokens[redacted]";}
 }
 public static ServiceProblem problem(String code,int status){return new ServiceProblem(code,status);}
 public static String string(Map<String,Object> r,String k){var v=r.get(k);return v==null?null:v.toString();}
 public static UUID uuid(Map<String,Object> r,String k){return (UUID)r.get(k);}
 public static Instant instant(Map<String,Object> r,String k){var v=r.get(k);return v==null?null:((java.sql.Timestamp)v).toInstant();}
 public static java.sql.Timestamp ts(Instant i){return java.sql.Timestamp.from(i);}
 public static long number(Map<String,Object> r,String k){return ((Number)r.get(k)).longValue();}
}
