kafka-streams-minimal/
├── docker-compose.yml
├── connect/
│   └── Dockerfile          ← cp-kafka-connect + ES sink connector plugin
└── streams-app/
    ├── Dockerfile           ← multi-stage Maven build → JRE runtime
    ├── pom.xml
    └── src/main/java/com/example/StreamsApp.java

## Pipeline

  Producer → [input] → Kafka Streams App → [output] → Kafka Connect → Elasticsearch

## Services

  zookeeper     cp-zookeeper:7.4.3       Kafka coordination
  kafka         cp-kafka:7.4.3           Single broker; topics created by kafka-init
  kafka-init    cp-kafka:7.4.3           Creates input/output topics; exits when done
  elasticsearch elasticsearch:7.17.16   Single node, security disabled
  connect       built from ./connect     Confluent Connect + ES sink connector
  connect-init  curlimages/curl          Registers ES sink connector; exits when done
  streams-app   built from ./streams-app Reads input, enriches with processed_at, writes to output

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
