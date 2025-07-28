{{- define "octo-mesh.system-env" -}}
- name: OCTO_SYSTEM__SYSTEMDATABASENAME
  value: {{ .global.Values.serviceDefaults.systemDatabaseName }}
- name: OCTO_SYSTEM__DATABASEHOST
  value: {{ .global.Values.clusterDependencies.mongodbHost }}
- name: OCTO_SYSTEM__DATABASEUSERPASSWORD
  valueFrom:
    secretKeyRef:
        name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
        key: databaseUser
- name: OCTO_SYSTEM__ADMINUSERPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: databaseAdmin          
{{- end }}

{{- define "octo-mesh.broker-env" -}}
- name: {{ printf "%s__BROKERHOST" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.rabbitMqHost }}
- name: {{ printf "%s__BROKERUSER" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.rabbitMqUser }}
- name: {{ printf "%s__BROKERPASSWORD" (upper .name) }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: rabbitmq     
{{- end }}

{{- define "octo-mesh.streamdata-env" -}}
- name: {{ printf "%s__STREAMDATAHOST" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.streamDataHost }}
- name: {{ printf "%s__STREAMDATAUSER" (upper .name) }}
  value: {{ .global.Values.clusterDependencies.streamDataUser }}
- name: {{ printf "%s__STREAMDATAPASSWORD" (upper .name) }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: streamDataPassword     
{{- end }}


{{- define "octo-mesh.env" -}}
- name: ASPNETCORE_URLS
  value: "http://+:80"
{{- if eq .name "identity" -}}
{{- $name := "OCTO_IDENTITY" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}
- name: OCTO_IDENTITY__KeyFilePath
  value: "/etc/octo-identity/IdentityServer4Auth.pfx"
- name: OCTO_IDENTITY__KEYFILEPASSWORD
  valueFrom:
    secretKeyRef:
        name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
        key: identityKeyFile
- name: OCTO_IDENTITY__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_IDENTITY__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
- name: OCTO_IDENTITY__IdentityServerLicenseKey
  value: {{ .global.Values.services.identity.identityServerLicenseKey }}
- name: OCTO_IDENTITY__AutoMapperLicenseKey
  value: {{ .global.Values.services.identity.autoMapperLicenseKey }}
{{- else if eq .name "assetRepository" -}}
{{- $name := "OCTO_ASSETREPOSITORY" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}
{{ include "octo-mesh.streamdata-env" (dict "global" .global "name" $name) }}
- name: OCTO_ASSETREPOSITORY__AUTHORITY
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_ASSETREPOSITORY__PUBLICURL
  value: {{ .global.Values.services.assetRepository.publicUri }}
- name: OCTO_ASSETREPOSITORY__PUBLICADMINPANELURL
  value: {{ .global.Values.services.adminPanel.publicUri }}
- name: OCTO_ASSETREPOSITORY__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}

{{- else if eq .name "bot" -}}
{{- $name := "OCTO_BOT" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}  
- name: OCTO_BOT__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_BOT__PUBLICURL
  value: {{ .global.Values.services.bot.publicUri }}
- name: OCTO_BOT__PUBLICADMINPANELURL
  value: {{ .global.Values.services.adminPanel.publicUri }}
- name: OCTO_BOT__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}

{{- else if eq .name "communication" -}}
{{- $name := "OCTO_COMMUNICATIONCONTROLLER" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}  
- name: OCTO_COMMUNICATIONCONTROLLER__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_COMMUNICATIONCONTROLLER__PUBLICURL
  value: {{ .global.Values.services.communication.publicUri }}
- name: OCTO_COMMUNICATIONCONTROLLER__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
{{- else if eq .name "adminPanel" -}}
{{- $name := "OCTO_ADMINPANEL" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}  
- name: OCTO_ADMINPANEL__CRATEDBADMINURL
  value: {{ .global.Values.externalUris.crateDb }}
- name: OCTO_ADMINPANEL__GRAFANAURL
  value: {{ .global.Values.externalUris.grafana }}
- name: OCTO_ADMINPANEL__MESHADAPTERURL
  value: {{ .global.Values.externalUris.meshAdapter }}  
- name: OCTO_ADMINPANEL__ASSETSERVICEURL
  value: {{ .global.Values.services.assetRepository.publicUri }}
- name: OCTO_ADMINPANEL__BOTSERVICEURL
  value: {{ .global.Values.services.bot.publicUri }}
- name: OCTO_ADMINPANEL__COMMUNICATIONSERVICEURL
  value: {{ .global.Values.services.communication.publicUri }}      
- name: OCTO_ADMINPANEL__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_ADMINPANEL__PUBLICURL
  value: {{ .global.Values.services.adminPanel.publicUri }}
- name: OCTO_ADMINPANEL__INSTANCEPREFIX
  value: {{ .global.Values.serviceDefaults.instancePrefix }}
{{- else if eq .name "studio" -}}
{{- $name := "OCTO_REFINERY_STUDIO" }}
- name: ADMIN_PANEL_URI
  value: {{ .global.Values.services.adminPanel.publicUri }}
- name: APP_URI
  value: {{ .global.Values.services.studio.publicUri }}
{{- else }}
{{- fail (printf "Service %s is not configured for the octo-mesh helm chart." .name) -}}
{{- end }}
{{- end }}