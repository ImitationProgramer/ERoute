package com.eroute;
import com.eroute.auth.PasswordPolicy;
import com.eroute.common.error.ServiceProblem;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class PasswordPolicyTest {
 @Test void codepointLimitsAndNfcPreserveSpacesAndCase(){
  for(int length:new int[]{14,129})assertThrows(ServiceProblem.class,()->PasswordPolicy.normalize("a".repeat(length)));
  for(int length:new int[]{15,128})assertEquals(length,PasswordPolicy.normalize("😀".repeat(length)).codePointCount(0,length*2));
  String raw="  A 가 e\u0301 😀 가나다라마바 ";
  String normalized=PasswordPolicy.normalize(raw);
  assertEquals("  A 가 é 😀 가나다라마바 ",normalized);
  String hash=PasswordPolicy.hash(normalized);
  assertTrue(hash.startsWith("$argon2id$"));
  assertTrue(PasswordPolicy.matches(PasswordPolicy.normalize(raw),hash));
  assertFalse(PasswordPolicy.matches(normalized.strip(),hash));
  assertFalse(PasswordPolicy.matches(normalized.toLowerCase(java.util.Locale.ROOT),hash));
 }
 @Test void sharedUnicode17Conformance()throws Exception{
  var data=new com.fasterxml.jackson.databind.ObjectMapper().readTree(java.nio.file.Files.readString(java.nio.file.Path.of("../../contracts/fixtures/password-nfc-unicode17.json")));
  for(var row:data){String source=("x".repeat(14)+" ")+row.get(0).asText(),expected=("x".repeat(14)+" ")+row.get(1).asText();assertEquals(expected,PasswordPolicy.normalize(source));}
 }
 @Test void phoneFormattingAndWeakPasswords(){
  assertEquals("01012345678",PasswordPolicy.phone("010-1234 5678"));
  for(String bad:new String[]{"+821012345678","01112345678","0101234567","010１２３４５６７８"})assertThrows(ServiceProblem.class,()->PasswordPolicy.phone(bad));
  assertThrows(ServiceProblem.class,()->PasswordPolicy.strong("1".repeat(15)));
  assertThrows(ServiceProblem.class,()->PasswordPolicy.normalize("x".repeat(15)+"\ud800"));
 }
}
