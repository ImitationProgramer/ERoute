package com.eroute;
import com.eroute.auth.AuthSettings;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import static org.junit.jupiter.api.Assertions.*;
class AuthSettingsTest {
 @Test void developmentRequiresBothExplicitEnvironmentAndFlag(){
  for(String environment:new String[]{"disabled","production","staging"})assertThrows(IllegalStateException.class,()->new AuthSettings(new MockEnvironment().withProperty("eroute.auth.environment",environment).withProperty("eroute.auth.provider","development").withProperty("eroute.auth.allow-development","true")));
  assertThrows(IllegalStateException.class,()->new AuthSettings(new MockEnvironment().withProperty("eroute.auth.environment","local").withProperty("eroute.auth.provider","development")));
 }
 @Test void productionConflictAndUnapprovedPassNeverFallBack(){
  assertThrows(IllegalStateException.class,()->new AuthSettings(new MockEnvironment().withProperty("eroute.auth.environment","production").withProperty("eroute.auth.allow-development","true")));
  assertThrows(IllegalStateException.class,()->new AuthSettings(new MockEnvironment().withProperty("eroute.auth.environment","production").withProperty("eroute.auth.provider","pass")));
  assertFalse(new AuthSettings(new MockEnvironment()).enabled);
 }
 @Test void operatorDoesNotInheritMemberLongSession(){
  var config=new AuthSettings(new MockEnvironment());assertEquals(java.time.Duration.ofMinutes(15),config.idle("OPERATOR"));assertEquals(java.time.Duration.ofHours(8),config.absolute("OPERATOR"));assertEquals(java.time.Duration.ofDays(7),config.idle("MEMBER"));
 }
}
