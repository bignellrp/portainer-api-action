FROM python:3

WORKDIR /app

ARG BUILD_DATE=""
ARG GITHUB_SHA=""

COPY index.html /app/index.html
COPY styles.css /app/styles.css
COPY app.js /app/app.js

RUN printf '{"sha":"%s","built":"%s"}\n' "$GITHUB_SHA" "$BUILD_DATE" > /app/version.json

EXPOSE 8000

CMD ["python", "-m", "http.server", "8000", "--directory", "/app"]