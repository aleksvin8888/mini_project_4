
FROM python:3.9-slim

RUN apt-get update && apt-get install -y \
    libpq-dev gcc

COPY requirements.txt /app/requirements.txt
WORKDIR /app
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app

EXPOSE 8001

# Запуск сервісу
CMD ["python", "manage.py", "runserver", "0.0.0.0:8001"]