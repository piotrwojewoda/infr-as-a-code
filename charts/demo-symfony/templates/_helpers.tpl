{{- define "demo-symfony.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "demo-symfony.fullname" -}}
{{- printf "%s" .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "demo-symfony.labels" -}}
app.kubernetes.io/name: {{ include "demo-symfony.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "demo-symfony.selectorLabels" -}}
app.kubernetes.io/name: {{ include "demo-symfony.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
