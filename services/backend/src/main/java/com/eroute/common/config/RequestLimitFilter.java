package com.eroute.common.config;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
@Component
public class RequestLimitFilter extends OncePerRequestFilter {
 private record Window(long minute,int count){}
 private final ConcurrentHashMap<String,Window> windows=new ConcurrentHashMap<>();
 @Override protected void doFilterInternal(HttpServletRequest req,HttpServletResponse res,FilterChain chain)throws ServletException,IOException{
  if(!req.getRequestURI().startsWith("/api/v1/")){chain.doFilter(req,res);return;}
  if(req.getContentLengthLong()>(req.getRequestURI().startsWith("/api/v1/me/")?65536:16384)){res.sendError(413);return;}
  if(req.getRequestURI().startsWith("/api/v1/auth/")||req.getRequestURI().startsWith("/api/v1/me")||req.getRequestURI().startsWith("/api/v1/ops/")){chain.doFilter(req,res);return;}
  long minute=System.currentTimeMillis()/60000;
  if(windows.size()>10000)windows.entrySet().removeIf(e->e.getValue().minute()<minute);
  Window w=windows.compute(req.getRemoteAddr(),(k,v)->v==null||v.minute()!=minute?new Window(minute,1):new Window(minute,v.count()+1));
  if(w.count()>60){res.setStatus(429);res.setHeader("Retry-After","60");res.setContentType("application/problem+json");res.getWriter().write("{\"status\":429,\"code\":\"REQUEST_RATE_LIMIT\",\"title\":\"REQUEST_RATE_LIMIT\"}");return;}
  chain.doFilter(req,res);
 }
}
