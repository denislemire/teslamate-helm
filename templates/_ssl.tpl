{{/*
Postgres client TLS. TeslaMate, Grafana, and TeslaMate API each speak a
different dialect of the same three modes:

  disable      no TLS
  require      encrypt, do not verify (CNPG with no CA in the client)
  verify-full  encrypt and verify; needs database.ssl.ca.existingSecret

TeslaMate (Elixir): DATABASE_SSL=false|noverify|true + DATABASE_SSL_CA_CERT_FILE
TeslaMate API (lib/pq): DATABASE_SSL is sslmode; true/noverify map to require
Grafana (teslamate/grafana): DATABASE_SSL_MODE interpolates into datasource.yml
sslmode only — the image has no sslRootCertFile knob, so verify-full still
sets Grafana to require.
*/}}

{{- define "teslamate.databaseSslMode" -}}
{{- $ssl := default dict .Values.database.ssl -}}
{{- default "disable" $ssl.mode | toString | trim -}}
{{- end }}

{{- define "teslamate.postgresCaSecret" -}}
{{- $ca := default dict (default dict .Values.database.ssl).ca -}}
{{- default "" $ca.existingSecret | toString | trim -}}
{{- end }}

{{- define "teslamate.postgresCaKey" -}}
{{- $ca := default dict (default dict .Values.database.ssl).ca -}}
{{- default "ca.crt" $ca.secretKey | toString | trim -}}
{{- end }}

{{- define "teslamate.postgresCaFile" -}}
{{- $ca := default dict (default dict .Values.database.ssl).ca -}}
{{- default "/etc/ssl/certs/postgres-ca.crt" $ca.mountPath | toString | trim -}}
{{- end }}

{{- define "teslamate.validateDatabaseSsl" -}}
{{- $mode := include "teslamate.databaseSslMode" . | trim -}}
{{- if not (has $mode (list "disable" "require" "verify-full")) -}}
{{- fail (printf "database.ssl.mode must be disable, require, or verify-full (got %q)" $mode) -}}
{{- end -}}
{{- if and (eq $mode "verify-full") (eq (include "teslamate.postgresCaSecret" . | trim) "") -}}
{{- fail "database.ssl.mode=verify-full requires database.ssl.ca.existingSecret (CloudNativePG: Secret <cluster>-ca, key ca.crt)" -}}
{{- end -}}
{{- end }}

{{- define "teslamate.teslamateDatabaseSsl" -}}
{{- include "teslamate.validateDatabaseSsl" . -}}
{{- $mode := include "teslamate.databaseSslMode" . | trim -}}
{{- if eq $mode "require" -}}
- name: DATABASE_SSL
  value: "noverify"
- name: DATABASE_SSL_SNI
  value: {{ include "teslamate.databaseHost" . | quote }}
{{- else if eq $mode "verify-full" -}}
- name: DATABASE_SSL
  value: "true"
- name: DATABASE_SSL_CA_CERT_FILE
  value: {{ include "teslamate.postgresCaFile" . | quote }}
{{- end -}}
{{- end }}

{{- define "teslamate.grafanaDatabaseSslMode" -}}
{{- $mode := include "teslamate.databaseSslMode" . | trim -}}
{{- if eq $mode "disable" -}}
disable
{{- else -}}
require
{{- end -}}
{{- end }}

{{- define "teslamate.apiDatabaseSsl" -}}
{{- include "teslamate.databaseSslMode" . | trim -}}
{{- end }}

{{- define "teslamate.postgresCaVolume" -}}
{{- if eq (include "teslamate.databaseSslMode" . | trim) "verify-full" }}
- name: postgres-ca
  secret:
    secretName: {{ include "teslamate.postgresCaSecret" . | quote }}
    items:
      - key: {{ include "teslamate.postgresCaKey" . | quote }}
        path: ca.crt
{{- end }}
{{- end }}

{{- define "teslamate.postgresCaVolumeMount" -}}
{{- if eq (include "teslamate.databaseSslMode" . | trim) "verify-full" }}
- name: postgres-ca
  mountPath: {{ include "teslamate.postgresCaFile" . | quote }}
  subPath: ca.crt
  readOnly: true
{{- end }}
{{- end }}
