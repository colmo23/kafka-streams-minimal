FROM maven:3.9-eclipse-temurin-11 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q

FROM eclipse-temurin:11-jre-jammy
WORKDIR /app
COPY --from=build /app/target/streams-app-1.0.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
