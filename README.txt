kafka-streams-minimal/
├── docker-compose.yml
├── connect/
│   └── Dockerfile              ← cp-kafka-connect + ES sink connector plugin
├── streams-app/
│   ├── Dockerfile               ← multi-stage Maven build → JRE runtime + JMX agent
│   ├── jmx-config.yml           ← JMX→Prometheus metric rules for Kafka Streams
│   ├── pom.xml
│   └── src/main/java/com/example/StreamsApp.java
└── monitoring/
    ├── prometheus.yml           ← scrape config (kafka-exporter + streams-app)
    └── grafana/provisioning/
        ├── datasources/         ← Prometheus datasource (auto-provisioned)
        └── dashboards/          ← Kafka Pipeline + Kafka Streams App dashboards

## Pipeline

  Producer → [input] → Kafka Streams App → [output] → Kafka Connect → Elasticsearch

## Services

  zookeeper      cp-zookeeper:7.4.3        Kafka coordination
  kafka          cp-kafka:7.4.3            Single broker; topics created by kafka-init
  kafka-init     cp-kafka:7.4.3            Creates input/output topics; exits when done
  elasticsearch  elasticsearch:7.17.16    Single node, security disabled
  kibana         kibana:7.17.16           Web UI for ES indices; port 5601
  connect        built from ./connect      Confluent Connect + ES sink connector
  connect-init   curlimages/curl           Registers ES sink connector; exits when done
  streams-app    built from ./streams-app  Reads input, enriches with processed_at, writes to output
  kafka-exporter danielqsj/kafka-exporter  Exposes Kafka broker/consumer-lag metrics for Prometheus
  prometheus     prom/prometheus:v2.48.0   Scrapes kafka-exporter and streams-app; port 9090
  grafana        grafana/grafana:10.2.2    Dashboards; port 3000, no login required

## What the Streams app does

  - Filters null/blank messages
  - JSON object  → merges in "processed_at" field
  - Plain string → wraps as {"message": "...", "processed_at": "..."}
  - Writes to output, which Kafka Connect sinks to the ES output index

## Startup

  # First time — builds images (connect ~2 min, streams-app ~3 min)
  docker compose build && docker compose up -d

  # Subsequent starts
  docker compose up -d

## Shutdown

  docker compose down          # stop and remove containers (volumes kept)
  docker compose down -v       # also delete volumes (wipes all Kafka/ES data)

## Status

  # All services at a glance
  docker compose ps

  # ES sink connector state (RUNNING = healthy)
  curl -s http://localhost:8083/connectors/es-sink/status | python3 -m json.tool

  # Kafka topics
  docker compose exec kafka kafka-topics \
    --bootstrap-server localhost:9092 --list

## Logs

  docker compose logs -f                  # all services, follow
  docker compose logs -f kafka            # single service
  docker compose logs -f streams-app
  docker compose logs -f connect
  docker compose logs --tail 50 connect   # last 50 lines, no follow

## Kibana

  http://localhost:5601

  First-time setup (once per fresh volume):
    1. Open http://localhost:5601
    2. Go to Management → Stack Management → Index Patterns
    3. Create index pattern: output*  (time field: processed_at)
    4. Go to Discover to browse documents or Analytics → Dashboard to build charts

  The output index is created automatically when the first message flows through.
  Kibana is pinned to 7.17.16 to match Elasticsearch exactly — mixing major
  versions causes Kibana to refuse to connect.

## Monitoring

  Grafana    http://localhost:3000   Dashboards (no login)
  Prometheus http://localhost:9090   Raw metric queries

  Two dashboards are pre-loaded under the Kafka folder:

  Kafka Pipeline
    - Consumer group lag for minimal-streams-app (should stay near 0)
    - Input and output topic message rates (msg/s)
    - Broker count

  Kafka Streams App
    - Processing rate and records-processed rate per task
    - Commit latency (avg and max)
    - Poll rate
    - Alive / failed stream thread counts

  Metrics sources:
    kafka-exporter  :9308  Kafka broker and consumer-lag metrics (Kafka protocol)
    streams-app     :9404  Kafka Streams JMX metrics via jmx_prometheus_javaagent

  Useful Prometheus queries:
    kafka_consumergroup_lag{consumergroup="minimal-streams-app"}
    rate(kafka_topic_partition_current_offset{topic="input"}[1m])
    kafka_streams_stream_thread_metrics_process_rate
    kafka_streams_stream_metrics_alive_stream_threads

## Test the pipeline

  # 1. Open a producer
  docker compose exec kafka kafka-console-producer \
    --bootstrap-server localhost:9092 --topic input
  # type: hello world  <Enter>  Ctrl+C

  # 2. Check Elasticsearch (index appears after first message)
  curl http://localhost:9200/output/_search?pretty

  # 3. Consume output topic directly
  docker compose exec kafka kafka-console-consumer \
    --bootstrap-server localhost:9092 --topic output --from-beginning
