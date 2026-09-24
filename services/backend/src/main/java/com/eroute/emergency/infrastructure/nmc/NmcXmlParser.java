package com.eroute.emergency.infrastructure.nmc;
import com.eroute.emergency.domain.model.Models.*;
import com.eroute.common.error.ServiceProblem;
import javax.xml.parsers.*;
import org.w3c.dom.*;
import org.xml.sax.*;
import java.io.*;
import java.time.Instant;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class NmcXmlParser {
 public Page parse(String xml,Instant fetchedAt){
  try{
   var doc=document(xml);
   String code=only(doc,"resultCode");
   if(!"00".equals(code)){
    if(Set.of("22","23").contains(code==null?"":code))throw new ServiceProblem("NMC_QUOTA_EXCEEDED");
    throw new ServiceProblem("NMC_RESULT_ERROR");
   }
   int page=integer(doc,"pageNo"),size=integer(doc,"numOfRows"),total=integer(doc,"totalCount");
   if(page<1||size<1||total<0)throw new ServiceProblem("NMC_INVALID_PAGINATION");
   var rows=new ArrayList<RawItem>();var nodes=doc.getElementsByTagName("item");
   for(int i=0;i<nodes.getLength();i++){
    var fields=new LinkedHashMap<String,List<String>>();var children=nodes.item(i).getChildNodes();
    for(int j=0;j<children.getLength();j++){var n=children.item(j);if(n.getNodeType()==Node.ELEMENT_NODE)fields.computeIfAbsent(n.getNodeName(),k->new ArrayList<>()).add(n.getTextContent());}
    rows.add(new RawItem(fields));
   }
   return new Page(page,size,total,List.copyOf(rows),xml,fetchedAt);
  }catch(ServiceProblem e){throw e;}catch(Exception e){throw new ServiceProblem("NMC_INVALID_XML");}
 }
 private Document document(String xml)throws Exception {
   var factory=DocumentBuilderFactory.newInstance();factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl",true);
   factory.setFeature("http://xml.org/sax/features/external-general-entities",false);
   factory.setFeature("http://xml.org/sax/features/external-parameter-entities",false);
   factory.setNamespaceAware(true);factory.setXIncludeAware(false);factory.setExpandEntityReferences(false);
   var builder=factory.newDocumentBuilder();builder.setErrorHandler(new ErrorHandler(){
    public void warning(SAXParseException e)throws SAXException{throw e;}public void error(SAXParseException e)throws SAXException{throw e;}public void fatalError(SAXParseException e)throws SAXException{throw e;}});
   return builder.parse(new InputSource(new StringReader(xml)));
 }
 public java.util.List<com.eroute.emergency.domain.model.BasicModels.RawBasicItem> basicItems(String xml){
  try {
   var doc=document(xml);var rows=new java.util.ArrayList<com.eroute.emergency.domain.model.BasicModels.RawBasicItem>();var nodes=doc.getElementsByTagName("item");
   for(int i=0;i<nodes.getLength();i++){
    var fields=new LinkedHashMap<String,java.util.List<com.eroute.emergency.domain.model.BasicModels.RawValue>>();var children=nodes.item(i).getChildNodes();
    for(int j=0;j<children.getLength();j++)if(children.item(j) instanceof Element e){
     var attributes=new LinkedHashMap<String,String>();for(int a=0;a<e.getAttributes().getLength();a++){var attr=e.getAttributes().item(a);attributes.put(attr.getNodeName(),attr.getNodeValue());}
     boolean nil="true".equals(e.getAttributeNS("http://www.w3.org/2001/XMLSchema-instance","nil"))||"1".equals(e.getAttributeNS("http://www.w3.org/2001/XMLSchema-instance","nil"));
     boolean nested=false;for(int c=0;c<e.getChildNodes().getLength();c++)if(e.getChildNodes().item(c) instanceof Element)nested=true;
     String raw=nil?null:e.getTextContent();
     var presence=nested?com.eroute.emergency.domain.model.BasicModels.Presence.STRUCTURED:nil?com.eroute.emergency.domain.model.BasicModels.Presence.NIL:raw.isEmpty()?com.eroute.emergency.domain.model.BasicModels.Presence.EMPTY:com.eroute.emergency.domain.model.BasicModels.Presence.TEXT;
     fields.computeIfAbsent(e.getTagName(),k->new ArrayList<>()).add(new com.eroute.emergency.domain.model.BasicModels.RawValue(raw,presence,attributes));
    }
    rows.add(new com.eroute.emergency.domain.model.BasicModels.RawBasicItem(fields));
   }return List.copyOf(rows);
  }catch(Exception e){throw new ServiceProblem("NMC_INVALID_XML");}
 }
 private static String only(Document d,String key){var nodes=d.getElementsByTagName(key);return nodes.getLength()==1?nodes.item(0).getTextContent().strip():null;}
 private static int integer(Document d,String key){return Integer.parseInt(only(d,key));}
}
