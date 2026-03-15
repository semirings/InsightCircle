FROM amazoncorretto:17-al2023

WORKDIR /app

COPY d4m.acc.microservice/build/libs/d4m.acc.microservice-0.0.1.jar app.jar

EXPOSE 5202

CMD ["java", "-jar", "app.jar", "--server.port=5202"]
