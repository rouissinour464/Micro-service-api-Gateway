# ===== BUILD STAGE =====
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /app
COPY pom.xml .
COPY src ./src

RUN mvn clean package -DskipTests


# ===== RUNTIME =====
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

RUN addgroup -S pfe && adduser -S pfe -G pfe

COPY --from=builder /app/target/*.jar app.jar
RUN chown pfe:pfe app.jar

USER pfe

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]