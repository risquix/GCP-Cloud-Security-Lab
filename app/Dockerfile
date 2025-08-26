FROM python:3.11-slim

ARG RUN_AS_ROOT=false
RUN if [ "$RUN_AS_ROOT" = "false" ]; then \
      useradd -m -u 1000 -s /bin/bash appuser; \
    fi

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN echo "Wiz Technical Exercise - Container includes this file" > wizexercise.txt

RUN if [ "$RUN_AS_ROOT" = "false" ]; then \
      chown -R appuser:appuser /app; \
    fi

RUN if [ "$RUN_AS_ROOT" = "true" ]; then \
      echo "Running as root user"; \
    else \
      echo "Running as appuser"; \
    fi

USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
