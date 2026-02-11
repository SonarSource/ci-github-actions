{{tablerow "NAME" "ID" "SIZE (BYTES)" "BRANCH" "HEAD_SHA" "RUN_ID"}}
  {{- range .artifacts -}}
    {{- tablerow .name .id .size_in_bytes .workflow_run.head_branch .workflow_run.head_sha .workflow_run.id -}}
  {{- end -}}
{{- tablerender -}}
