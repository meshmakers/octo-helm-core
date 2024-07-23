{{- define "octo-mesh.system-env" -}}
- name: OCTO_SYSTEM__DATABASEHOST
  value: {{ .Values.clusterDependencies.mongodbHost }}
- name: OCTO_SYSTEM__DATABASEUSERPASSWORD
  valueFrom:
    secretKeyRef:
        name: {{ printf "%s-backend" (include "octo-mesh.fullname" .) }}
        key: databaseUser
- name: OCTO_SYSTEM__ADMINUSERPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .) }}
      key: databaseAdmin          
{{- end }}

{{- define "octo-mesh.broker-env" -}}
- name: {{ printf "%s__BROKERHOST" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.rabbitMqHost }}
- name: {{ printf "%s__BROKERUSERNAME" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.rabbitMqUser }}
- name: {{ printf "%s__BROKERPASSWORD" (upper .name) }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: rabbitmq     
{{- end }}

{{- define "octo-mesh.streamdata-env" -}}
- name: {{ printf "%s__STREAMDATAHOST" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.crateHost }}
- name: {{ printf "%s__STREAMDATAUSER" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.crateUser }}
- name: {{ printf "%s__STREAMDATAPASSWORD" (upper .name) }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: crate     
{{- end }}


{{- define "octo-mesh.env" -}}
- name: ASPNETCORE_URLS
  value: "http://+:80"
{{- $name := "OCTO_ADAPTER" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" . "name" $name) }} 
{{ include "octo-mesh.streamdata-env" (dict "global" . "name" $name) }}
- name: OCTO_ADAPTER__TENANTID
  value: {{ .Values.tenantId }}
- name: OCTO_ADAPTER__COMMUNICATIONCONTROLLERSERVICESURI
  value: {{ .Values.communicationControllerServiceUri }}
- name: OCTO_ADAPTER__ADAPTERCKTYPEID
  value: "System.Communication/MeshAdapter"              
- name: OCTO_ADAPTER__ADAPTERRTID
  value: {{ .Values.adapterRtId }}
{{- end }}