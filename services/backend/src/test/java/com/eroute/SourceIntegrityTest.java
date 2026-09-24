package com.eroute;
import com.eroute.emergency.infrastructure.persistence.JsonCodec;
import org.junit.jupiter.api.Test;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.HexFormat;
import static org.junit.jupiter.api.Assertions.*;
class SourceIntegrityTest {
 @Test void implementationRequiresPinnedOfficialPdfAndEmpiricalSource()throws Exception{
  var mapper=new JsonCodec().mapper();var book=mapper.readTree(getClass().getResourceAsStream("/nmc/codebooks/v13/codebook.json"));
  Path root=Path.of("../..").toAbsolutePath().normalize();
  Path pdf=Path.of(System.getenv().getOrDefault("NMC_V13_PDF",root.resolve(book.path("officialSource").path("path").asText()).toString()));
  assertTrue(Files.isReadable(pdf),"V13 PDF must be available in the implementation environment");
  assertEquals(book.path("officialSource").path("sha256").asText(),HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(pdf))));
  assertTrue(Files.isReadable(root.resolve(book.path("observationSource").path("path").asText())));
 }
}
