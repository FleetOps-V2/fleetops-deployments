{{/*
FleetOps Common Helpers - Shared across all microservices
*/}}

{{/* Expand the name of the chart */}}
{{- define "fleetops-common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create chart name and version */}}
{{- define "fleetops-common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels (extra only - name and component should be defined in template) */}}
{{- define "fleetops-common.labels" -}}
helm.sh/chart: {{ include "fleetops-common.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.argocd.enabled }}
argocd.argoproj.io/instance: {{ .Release.Name }}
{{- end }}
{{- end }}

{{/* Selector labels - use when defining selectors only */}}
{{- define "fleetops-common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fleetops-common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Service account name */}}
{{- define "fleetops-common.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "fleetops-common.name" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Full image name */}}
{{- define "fleetops-common.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- end }}

{{/* Namespace helper */}}
{{- define "fleetops-common.namespace" -}}
{{ .Values.namespace.name | default .Release.Namespace }}
{{- end }}

{{/* ArgoCD sync wave annotation */}}
{{- define "fleetops-common.argocdAnnotations" -}}
{{- if .Values.argocd.enabled }}
argocd.argoproj.io/sync-wave: {{ .Values.argocd.syncWave | quote }}
{{- range $key, $value := .Values.argocd.annotations }}
argocd.argoproj.io/{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/* Spring Boot probes template */}}
{{- define "fleetops-common.springBootProbes" -}}
{{- if .Values.probes.startup.enabled }}
startupProbe:
  httpGet:
    path: {{ .Values.probes.startup.path }}
    port: {{ .Values.probes.startup.port }}
  initialDelaySeconds: {{ .Values.probes.startup.initialDelaySeconds }}
  periodSeconds: {{ .Values.probes.startup.periodSeconds }}
  failureThreshold: {{ .Values.probes.startup.failureThreshold }}
  timeoutSeconds: {{ .Values.probes.startup.timeoutSeconds }}
{{- end }}
{{- if .Values.probes.readiness.enabled }}
readinessProbe:
  httpGet:
    path: {{ .Values.probes.readiness.path }}
    port: {{ .Values.probes.readiness.port }}
  initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
  periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
  failureThreshold: {{ .Values.probes.readiness.failureThreshold }}
  timeoutSeconds: {{ .Values.probes.readiness.timeoutSeconds }}
{{- end }}
{{- if .Values.probes.liveness.enabled }}
livenessProbe:
  httpGet:
    path: {{ .Values.probes.liveness.path }}
    port: {{ .Values.probes.liveness.port }}
  initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
  periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
  failureThreshold: {{ .Values.probes.liveness.failureThreshold }}
  timeoutSeconds: {{ .Values.probes.liveness.timeoutSeconds }}
{{- end }}
{{- end }}

{{/* Nginx probes template */}}
{{- define "fleetops-common.nginxProbes" -}}
{{- if .Values.probes.readiness.enabled }}
readinessProbe:
  httpGet:
    path: {{ .Values.probes.readiness.path }}
    port: {{ .Values.probes.readiness.port }}
  initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
  periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
  failureThreshold: {{ .Values.probes.readiness.failureThreshold }}
  timeoutSeconds: {{ .Values.probes.readiness.timeoutSeconds }}
{{- end }}
{{- if .Values.probes.liveness.enabled }}
livenessProbe:
  httpGet:
    path: {{ .Values.probes.liveness.path }}
    port: {{ .Values.probes.liveness.port }}
  initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
  periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
  failureThreshold: {{ .Values.probes.liveness.failureThreshold }}
  timeoutSeconds: {{ .Values.probes.liveness.timeoutSeconds }}
{{- end }}
{{- end }}

{{/* HPA template */}}
{{- define "fleetops-common.hpa" -}}
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "fleetops-common.name" . }}-hpa
  namespace: {{ include "fleetops-common.namespace" . }}
  labels:
    {{- include "fleetops-common.labels" . | nindent 4 }}
  annotations:
    {{- include "fleetops-common.argocdAnnotations" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "fleetops-common.name" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
    {{- if .Values.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end }}
{{- end }}
