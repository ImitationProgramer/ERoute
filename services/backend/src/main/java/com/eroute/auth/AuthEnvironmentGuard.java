package com.eroute.auth;
import org.springframework.boot.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class AuthEnvironmentGuard implements ApplicationRunner {
 private final AuthSettings settings;private final JdbcTemplate db;private final ObjectProvider<PhoneIdentityVerificationProvider> providers;private final SecretBox box;
 public AuthEnvironmentGuard(AuthSettings settings,JdbcTemplate db,ObjectProvider<PhoneIdentityVerificationProvider> providers,SecretBox box){this.settings=settings;this.db=db;this.providers=providers;this.box=box;}
 public void run(ApplicationArguments args){
  if(settings.environment.equals("production")){
   try{Class.forName("com.eroute.auth.development.DevelopmentPhoneProvider");throw new IllegalStateException("DEVELOPMENT_CODE_IN_PRODUCTION");}catch(ClassNotFoundException expected){}
   if(Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM app_user WHERE source='DEVELOPMENT' OR environment<>'production')",Boolean.class)))throw new IllegalStateException("DEVELOPMENT_ACCOUNTS_IN_PRODUCTION");
  }
  if(!settings.enabled)return;
  var markers=db.queryForList("SELECT environment FROM auth_environment",String.class);
  if(markers.size()!=1||!markers.getFirst().equals(settings.environment))throw new IllegalStateException("AUTH_DATABASE_ENVIRONMENT_MISMATCH");
  if(!settings.provider.equals("password")&&providers.stream().filter(p->p.name().equals(settings.provider)).count()!=1)throw new IllegalStateException("AUTH_PROVIDER_UNAVAILABLE");
  box.validateRegistry();
  if(Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM app_user WHERE environment<>?)",Boolean.class,settings.environment)))throw new IllegalStateException("AUTH_ACCOUNT_ENVIRONMENT_MISMATCH");
 }
}
