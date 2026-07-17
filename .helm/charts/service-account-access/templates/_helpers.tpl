{{- define "service-account-access.namespace" -}}
{{- required "namespace.name is required" .Values.namespace.name -}}
{{- end -}}

{{- define "service-account-access.serviceAccountNamespace" -}}
{{- default (include "service-account-access.namespace" .root) .serviceAccount.namespace -}}
{{- end -}}

{{- define "service-account-access.tokenSecretName" -}}
{{- if and .serviceAccount.longLivedToken .serviceAccount.longLivedToken.name -}}
{{- .serviceAccount.longLivedToken.name -}}
{{- else -}}
{{- printf "%s%s" .serviceAccount.name (default "-token" .root.Values.defaults.longLivedToken.nameSuffix) -}}
{{- end -}}
{{- end -}}
