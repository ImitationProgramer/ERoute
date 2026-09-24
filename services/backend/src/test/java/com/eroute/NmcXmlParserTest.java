package com.eroute;
import com.eroute.emergency.infrastructure.nmc.NmcXmlParser;
import com.eroute.common.error.ServiceProblem;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class NmcXmlParserTest {
 final NmcXmlParser parser=new NmcXmlParser();
 String xml(String items){return "<response><header><resultCode>00</resultCode></header><body><items>"+items+"</items><pageNo>1</pageNo><numOfRows>10</numOfRows><totalCount>1</totalCount></body></response>";}
 @Test void preservesRawStringsAndUnknownFields(){String source=xml("<item><hpid>TEST1</hpid><hvec> 0 </hvec><futureField>N1</futureField></item>");var p=parser.parse(source,TestSupport.NOW);assertEquals(source,p.rawXml());assertEquals(" 0 ",p.items().getFirst().single("hvec"));assertEquals("N1",p.items().getFirst().single("futureField"));}
 @Test void xmlGatewayFailureIsNotEmptySuccess(){assertThrows(ServiceProblem.class,()->parser.parse("<OpenAPI_ServiceResponse><cmmMsgHeader><returnReasonCode>30</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>",TestSupport.NOW));}
 @Test void duplicateValuesRemainInRaw(){var p=parser.parse(xml("<item><hvec>1</hvec><hvec>2</hvec></item>"),TestSupport.NOW);assertEquals(2,p.items().getFirst().fields().get("hvec").size());assertNull(p.items().getFirst().single("hvec"));}
 @Test void rejectsExternalEntities(){assertThrows(ServiceProblem.class,()->parser.parse("<!DOCTYPE response [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]>"+xml("<item><hpid>&xxe;</hpid></item>"),TestSupport.NOW));}
 @Test void rejectsHtmlOrMissingPagination(){assertThrows(ServiceProblem.class,()->parser.parse("<html>error</html>",TestSupport.NOW));assertThrows(ServiceProblem.class,()->parser.parse("<response><resultCode>00</resultCode></response>",TestSupport.NOW));}
}
