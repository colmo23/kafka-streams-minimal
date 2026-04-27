FROM maven:3.9-eclipse-temurin-11 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
RUN mvn dependency:copy \
      -Dartifact=io.prometheus.jmx:jmx_prometheus_javaagent:0.20.0:jar \
      -DoutputDirectory=. -q && \
    mv jmx_prometheus_javaagent-0.20.0.jar jmx_prometheus_javaagent.jar
COPY src ./src
RUN mvn package -DskipTests -q

FROM eclipse-temurin:11-jre-jammy
WORKDIR /app
COPY --from=build /app/target/streams-app-1.0.jar app.jar
COPY --from=build /app/jmx_prometheus_javaagent.jar jmx_prometheus_javaagent.jar
COPY jmx-config.yml jmx-config.yml
EXPOSE 9404
ENTRYPOINT ["java", \
  "-javaagent:/app/jmx_prometheus_javaagent.jar=9404:/app/jmx-config.yml", \
  "-jar", "app.jar"]
