package com.eroute.personalization;

import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Component;

/** Development artifact only. Production retains DiseaseReference.RESOURCE. */
@Component
@Primary
@ConditionalOnExpression("'${eroute.auth.environment:disabled}' == 'local' or '${eroute.auth.environment:disabled}' == 'test'")
public final class DevelopmentDiseaseReference extends DiseaseReference {
 public static final String RESOURCE="reference/disease-departments/v0.5.json";
 public DevelopmentDiseaseReference(){super(RESOURCE);}
}
