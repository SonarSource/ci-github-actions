{{tablerow "NAME" "ID" "SIZE (BYTES)" "BRANCH" "HEAD_SHA" "RUN_ID"}}
  {{- range .artifacts -}}
    {{- if eq .workflow_run.head_branch "$GITHUB_HEAD_REF" -}}
      {{- tablerow .name .id .size_in_bytes .workflow_run.head_branch .workflow_run.head_sha .workflow_run.id -}}
    {{- end -}}
  {{- end -}}
{{- tablerender -}}
