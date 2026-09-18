{{- define "momo-store.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "momo-store.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "momo-store.labels" -}}
helm.sh/chart: {{ include "momo-store.name" . }}-{{ .Chart.Version | replace "+" "_" }}
{{ include "momo-store.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "momo-store.selectorLabels" -}}
app.kubernetes.io/name: {{ include "momo-store.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Возвращает IP DNS-резолвера для nginx.
Приоритет:
1. .Values.frontend.dnsResolver (если задан явно - например 169.254.25.10)
2. ClusterIP сервиса kube-dns (через lookup)
3. 169.254.25.10 (жёсткий fallback)
*/}}
{{- define "momo-store.dnsResolver" -}}
{{- if .Values.frontend.dnsResolver -}}
{{- .Values.frontend.dnsResolver -}}
{{- else -}}
{{- $svc := lookup "v1" "Service" "kube-system" "kube-dns" -}}
{{- if and $svc $svc.spec $svc.spec.clusterIP -}}
{{- $svc.spec.clusterIP -}}
{{- else -}}
169.254.25.10
{{- end -}}
{{- end -}}
{{- end }}