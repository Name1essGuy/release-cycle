# Helm-чарт momo-store

## 📋 Описание

Helm-чарт для развёртывания приложения Momo Store в Kubernetes кластере Yandex Cloud.
Включает backend (API), frontend (Nginx + S3-статика) и ingress-nginx.

## 🏗️ Архитектура

[диаграмма: клиент → LB → ingress-nginx → frontend (nginx) → S3 / backend]

## 📁 Структура чарта

momo-store/
├── Chart.yaml
├── values.yaml
├── values-staging.yaml
├── values-prod.yaml
└── templates/
    ├── _helpers.tpl
    ├── ingress.yaml
    ├── frontend/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── nginx-configmap.yaml
    └── backend/
        ├── deployment.yaml
        └── service.yaml

## 🔧 Предварительные требования

| Инструмент | Версия |
|---|---|
| Helm | >= 3.12 |
| kubectl | >= 1.28 |
| Доступ к кластеру | kubeconfig |

## 🚀 Быстрый старт

[команды helm install/upgrade]

## 📚 Документация

- [Архитектура](./architecture.md)
- [Параметры values](./values-reference.md)
- [Деплой и обновление](./deployment.md)