package com.example;

import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.errors.StreamsUncaughtExceptionHandler;
import org.apache.kafka.streams.kstream.KStream;

import java.time.Instant;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;

public class StreamsApp {

    public static void main(String[] args) throws InterruptedException {
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "minimal-streams-app");
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, env("BOOTSTRAP_SERVERS", "kafka:9092"));
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());

        String inputTopic = env("INPUT_TOPIC", "input");
        String outputTopic = env("OUTPUT_TOPIC", "output");

        StreamsBuilder builder = new StreamsBuilder();
        builder.<String, String>stream(inputTopic)
            .filter((key, value) -> value != null && !value.isBlank())
            .mapValues(StreamsApp::enrich)
            .to(outputTopic);

        CountDownLatch latch = new CountDownLatch(1);
        KafkaStreams streams = new KafkaStreams(builder.build(), props);

        streams.setUncaughtExceptionHandler(ex -> {
            System.err.println("Stream thread died: " + ex);
            latch.countDown();
            return StreamsUncaughtExceptionHandler.StreamThreadExceptionResponse.SHUTDOWN_CLIENT;
        });

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            streams.close();
            latch.countDown();
        }));

        streams.start();
        latch.await();
        System.exit(1);
    }

    private static String enrich(String value) {
        String trimmed = value.trim();
        if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
            return trimmed.substring(0, trimmed.length() - 1)
                + ",\"processed_at\":\"" + Instant.now() + "\"}";
        }
        return "{\"message\":\"" + trimmed.replace("\"", "\\\"")
            + "\",\"processed_at\":\"" + Instant.now() + "\"}";
    }

    private static String env(String key, String fallback) {
        String v = System.getenv(key);
        return v != null && !v.isBlank() ? v : fallback;
    }
}
