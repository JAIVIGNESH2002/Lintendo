FROM debian:13-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates postgresql-client python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/payments-api
COPY status-server.py /opt/payments-api/app.py

ENV API_PORT=8080
ENV DB_HOST=postgres
ENV DB_NAME=payments
ENV DB_USER=blackmesa
ENV DB_PASSWORD=blackmesa

CMD ["python3", "/opt/payments-api/app.py", "serve"]

