{{tablerow "ID" "KEY" "SIZE (BYTES)"}}
  {{- range . -}}
    {{- tablerow .id .key .sizeInBytes -}}
  {{- end -}}
{{- tablerender -}}
