{{/*
Pod scheduling and pull secrets.
Pass dict: component (values map) and root (chart context).
*/}}
{{- define "teslamate.podPlacement" -}}
{{- $c := .component }}
{{- $pull := $c.imagePullSecrets }}
{{- if not $pull }}
{{- $pull = .root.Values.imagePullSecrets }}
{{- end }}
{{- with $pull }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $c.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $c.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $c.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "teslamate.podSecurityContext" -}}
{{- with .podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "teslamate.containerSecurityContext" -}}
{{- with .securityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "teslamate.podAnnotations" -}}
{{- with .podAnnotations }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
