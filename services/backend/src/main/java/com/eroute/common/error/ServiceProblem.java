package com.eroute.common.error;
public class ServiceProblem extends RuntimeException {
 private final String code;private final int status;
 public ServiceProblem(String code){this(code,503);}
 public ServiceProblem(String code,int status){super(code);this.code=code;this.status=status;}
 public String code(){return code;}
 public int status(){return status;}
}
