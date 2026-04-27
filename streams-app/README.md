A minimal Maven build with three concerns:

**Coordinates** — `com.example:streams-app:1.0`, compiled to Java 11.

**Dependencies** — just two:
- `kafka-streams:3.4.0` — the Kafka Streams library. Version 3.4 matches Confluent Platform 7.4 (the version used by all the other containers).
- `slf4j-simple:2.0.9` — logging backend so Kafka's internal log output is visible. Without it you only get the "SLF4J: Defaulting to no-operation" warning and all logs are silently dropped.

**Build** — the `maven-shade-plugin` packages everything into a single fat JAR (`streams-app-1.0.jar`). Two transformers are configured:
- `ManifestResourceTransformer` — sets `com.example.StreamsApp` as the `Main-Class` so the JAR is executable with `java -jar`.
- `ServicesResourceTransformer` — merges `META-INF/services/` files from all JARs on the classpath. This is required for Kafka Streams: it uses Java's `ServiceLoader` SPI to discover internal classes (serializers, assignors, etc.), and without merging those files the fat JAR would only keep one JAR's copy and silently drop the rest.
