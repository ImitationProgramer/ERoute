package com.eroute.common.error;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.*;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.dao.DataAccessException;
import java.util.UUID;
@RestControllerAdvice
public class ApiErrorHandler {
 @ExceptionHandler({IllegalArgumentException.class,HttpMessageNotReadableException.class,org.springframework.web.method.annotation.MethodArgumentTypeMismatchException.class,org.springframework.web.bind.MethodArgumentNotValidException.class})
 public ProblemDetail badRequest(Exception e){return problem(400,"INVALID_REQUEST","입력 내용을 확인해주세요.");}
 @ExceptionHandler(ServiceProblem.class)
 public ProblemDetail serviceProblem(ServiceProblem e){return problem(e.status(),e.code(),message(e.code()));}
 private String message(String code){return switch(code){
  case "AGE_RESTRICTED" -> "현재 회원가입은 만 14세 이상부터 가능합니다. 119 전화 연결과 병원 검색은 가입 없이 이용할 수 있습니다.";
  case "HEALTH_CONSENT_REQUIRED" -> "건강정보 처리 동의 상태를 확인해주세요.";
  case "ENCRYPTED_DATA_UNAVAILABLE" -> "저장된 정보를 안전하게 읽을 수 없습니다. 내용을 변경하지 않고 다시 시도해주세요.";
  case "DATA_VERSION_CONFLICT", "CONSENT_GENERATION_CHANGED" -> "정보가 변경되었습니다. 최신 상태를 확인해주세요.";
  case "AUTH_UNAVAILABLE" -> "현재 로그인을 이용할 수 없습니다. 병원 검색과 119 전화 연결은 이용할 수 있습니다.";
  case "HOSPITAL_NOT_FOUND" -> "병원 정보를 찾을 수 없습니다.";
  default -> "요청을 처리하지 못했습니다. 상태를 확인한 후 다시 시도해주세요.";
 };}
 @ExceptionHandler(DataAccessException.class)
 public ProblemDetail database(Exception e){return problem(503,"DATABASE_UNAVAILABLE","현재 병원 정보를 조회할 수 없습니다.");}
 @ExceptionHandler(Exception.class)
 public ProblemDetail unexpected(Exception e){return problem(500,"INTERNAL_ERROR","요청을 처리하지 못했습니다.");}
 private ProblemDetail problem(int status,String code,String detail){var p=ProblemDetail.forStatusAndDetail(HttpStatusCode.valueOf(status),detail);p.setTitle(code);p.setProperty("code",code);p.setProperty("traceId",UUID.randomUUID().toString());return p;}
}
