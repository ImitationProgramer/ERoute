package com.eroute.auth;

import java.io.IOException;
import java.time.*;
import java.util.*;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.context.annotation.*;
import org.springframework.http.HttpMethod;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AnonymousAuthenticationFilter;
import org.springframework.web.filter.OncePerRequestFilter;
import com.eroute.common.error.ServiceProblem;

@Configuration
public class AuthSecurity {
 @Bean org.springframework.security.core.userdetails.UserDetailsService noImplicitPasswordAccounts(){return name->{throw new org.springframework.security.core.userdetails.UsernameNotFoundException("IMPLICIT_PASSWORD_LOGIN_DISABLED");};}
 @Bean SecurityFilterChain security(HttpSecurity http,AuthService auth,AuthSettings settings,SecretBox box,JdbcTemplate db,Clock clock)throws Exception{
  http.sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable()).csrf(c->c.disable()).formLogin(c->c.disable()).httpBasic(c->c.disable()).logout(c->c.disable());
  http.authorizeHttpRequests(a->a
   .requestMatchers(HttpMethod.GET,"/api/v1/reference/disease-departments","/api/v1/reference/diseases","/api/v1/map-config","/api/v1/readyz","/api/v1/emergency-hospitals/{hpid}","/actuator/health").permitAll()
   .requestMatchers(HttpMethod.POST,"/api/v1/emergency-hospitals/search","/api/v1/emergency-hospitals/departments/query").permitAll()
   .requestMatchers(HttpMethod.POST,"/api/v1/auth/signup","/api/v1/auth/login","/api/v1/auth/transactions","/api/v1/auth/transactions/*/complete","/api/v1/auth/refresh","/api/v1/auth/logout").permitAll()
   .requestMatchers(HttpMethod.GET,"/api/v1/auth/transactions/*").permitAll()
   .requestMatchers(HttpMethod.DELETE,"/api/v1/auth/transactions/*").permitAll()
   .requestMatchers("/api/v1/auth/development/**").access((s,c)->new org.springframework.security.authorization.AuthorizationDecision(settings.provider.equals("development")&&Set.of("local","test").contains(settings.environment)))
   .requestMatchers("/api/v1/dev/reference/disease-departments-review-preview").access((s,c)->new org.springframework.security.authorization.AuthorizationDecision(Set.of("local","test").contains(settings.environment)&&settings.enabled&&s.get().getAuthorities().stream().anyMatch(g->g.getAuthority().equals("ROLE_MEMBER"))))
   .requestMatchers("/api/v1/ops/status").hasRole("OPERATOR")
   .requestMatchers("/api/v1/me/conditions","/api/v1/me/map-disease-selection","/api/v1/me/health-snapshot","/api/v1/me/emergency-profile","/api/v1/me/medications/**","/api/v1/me/health-consent/**").hasRole("MEMBER")
   .requestMatchers("/api/v1/auth/reauth","/api/v1/me","/api/v1/me/activity","/api/v1/me/phone-change","/api/v1/auth/logout-all").authenticated()
   .anyRequest().denyAll());
  http.exceptionHandling(e->e.authenticationEntryPoint((q,r,x)->error(r,401,"AUTH_REQUIRED")).accessDeniedHandler((q,r,x)->error(r,403,"ACCESS_DENIED")));
  http.addFilterBefore(new OncePerRequestFilter(){
   @Override protected void doFilterInternal(HttpServletRequest q,HttpServletResponse r,FilterChain chain)throws ServletException,IOException{
    String path=q.getRequestURI();boolean sensitive=path.startsWith("/api/v1/auth/")||path.startsWith("/api/v1/me")||path.startsWith("/api/v1/ops/")||path.startsWith("/api/v1/dev/");
    if(!sensitive){chain.doFilter(q,r);return;}
    r.setHeader("Cache-Control","no-store");r.setHeader("Pragma","no-cache");r.setHeader("Referrer-Policy","no-referrer");
    try{
     if(settings.enabled&&path.startsWith("/api/v1/auth/")&&!path.endsWith("/logout")){
      var window=clock.instant().truncatedTo(java.time.temporal.ChronoUnit.MINUTES);String bucket=box.mac("session","rate:"+q.getRemoteAddr());
      Integer attempts=db.queryForObject("INSERT INTO auth_rate_window VALUES(?,?,1) ON CONFLICT(bucket,window_at) DO UPDATE SET attempts=auth_rate_window.attempts+1 RETURNING attempts",Integer.class,bucket,AuthData.ts(window));
      if(attempts>60){r.setHeader("Retry-After","60");throw AuthData.problem("AUTH_RATE_LIMIT",429);}
     }
     String header=q.getHeader("Authorization");if(header!=null){if(!header.startsWith("Bearer "))throw AuthData.problem("AUTH_REQUIRED",401);var p=auth.authenticate(header.substring(7));var token=new UsernamePasswordAuthenticationToken(p,null,List.of(new SimpleGrantedAuthority("ROLE_"+p.role())));SecurityContextHolder.getContext().setAuthentication(token);}
     chain.doFilter(q,r);
    }catch(ServiceProblem e){error(r,e.status(),e.code());}finally{SecurityContextHolder.clearContext();}
   }
  },AnonymousAuthenticationFilter.class);
  return http.build();
 }
 private static void error(HttpServletResponse r,int status,String code)throws IOException{r.setStatus(status);r.setContentType("application/problem+json");r.getWriter().write("{\"status\":"+status+",\"code\":\""+code+"\",\"detail\":\"요청 권한을 확인해주세요.\"}");}
}
