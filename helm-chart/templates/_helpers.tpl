{{/*
Resolve the image for a service.
Usage: {{ include "vanta.image" (list . "frontend" .Values.frontend.name) }}
If images.overrides.<key> exists, use its repository:tag; otherwise images.repository/<name>
at images.tag (default Chart.appVersion). Every image is built by this repo's CI.
*/}}
{{- define "vanta.image" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $name := index . 2 -}}
{{- $ov := index ($root.Values.images.overrides | default dict) $key -}}
{{- if $ov -}}
{{- printf "%s:%s" $ov.repository ($ov.tag | default "latest") -}}
{{- else -}}
{{- printf "%s/%s:%s" $root.Values.images.repository $name ($root.Values.images.tag | default $root.Chart.AppVersion) -}}
{{- end -}}
{{- end -}}
