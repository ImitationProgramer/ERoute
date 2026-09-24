FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
COPY .mvn ./.mvn
COPY mvnw pom.xml ./
RUN ./mvnw -q dependency:go-offline
COPY src ./src
RUN ./mvnw -q -DskipTests package
FROM eclipse-temurin:21-jre
WORKDIR /app
RUN groupadd --system eroute && useradd --system --gid eroute eroute
COPY --from=build /app/target/emergency-api-0.1.0.jar app.jar
USER eroute
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
