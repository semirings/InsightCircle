# ============================
# Dockerfile for insight_store
# ============================

# Lightweight Java runtime
FROM eclipse-temurin:17-jre

# Working directory
WORKDIR /app

# Copy Spring Boot jar
COPY d4m.acc.microservice/build/libs/d4m.acc.microservice-0.0.1.jar /app/app.jar

# Install wget and download wait-for-it
RUN apt-get update \
    && apt-get install -y wget \
    && wget -O /app/wait-for-it.sh https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh \
    && chmod +x /app/wait-for-it.sh \
    && apt-get remove -y wget \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Expose Spring Boot port
EXPOSE 5202

# Wait for Redis before starting the service
ENTRYPOINT ["/app/wait-for-it.sh", "redis:6379", "--timeout=30", "--strict", "--", "java", "-jar", "/app/app.jar"]cd