{{- /*
Return the application fullname:
1) fullnameOverride
2) nameOverride
3) default: "<release-name>-<app.name>"
*/ -}}
{{- define "springboot.fullname" -}}
{{- if .Values.app.fullnameOverride }}
{{- .Values.app.fullnameOverride }}
{{- else if .Values.app.nameOverride }}
{{- .Values.app.nameOverride }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Values.app.name }}
{{- end }}
{{- end }}

{{- /*
Standard labels for this app. Produces multiple lines; use with nindent.
*/ -}}
{{- define "springboot.labels" -}}
app.kubernetes.io/name: {{ .Values.app.name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: Helm
{{- end }}

{{- /*
Return the postgres fullname:
1) fullnameOverride
2) nameOverride
3) default: "postgres"
*/ -}}
{{- define "postgres.fullname" -}}
{{- if .Values.postgres.fullnameOverride -}}
{{- .Values.postgres.fullnameOverride -}}
{{- else -}}
{{- if .Values.postgres.nameOverride -}}
{{- .Values.postgres.nameOverride -}}
{{- else -}}
postgres
{{- end -}}
{{- end -}}
{{- end -}}

{{- /*
Standard labels for postgres. Produces multiple lines; use with nindent.
*/ -}}
{{- define "postgres.labels" -}}
app.kubernetes.io/name: postgres
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
