FROM eclipse-temurin:17-jre

WORKDIR /app

COPY d4m.acc.microservice/build/libs/d4m.acc.microservice-0.0.1.jar /app/app.jar
COPY wait-for-it.sh /app/wait-for-it.sh

RUN sed -i 's/\r$//' /app/wait-for-it.sh
RUN chmod +x /app/wait-for-it.sh

EXPOSE 5202

ENTRYPOINT ["/app/wait-for-it.sh", "redis:6379", "--timeout=30", "--strict", "--", "java", "-jar", "/app/app.jar"]