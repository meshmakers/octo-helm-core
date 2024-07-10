{{- define "octo-mesh.system-env" -}}
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
- name: OCTO_EMAIL__HOST
  value: {{ .global.Values.notifications.smtp.host }}
- name: OCTO_EMAIL__PORT
  value: {{ .global.Values.notifications.smtp.port | quote }}
- name: OCTO_EMAIL__ENABLESSL
  value: {{ .global.Values.notifications.smtp.enableSsl | quote }}         
- name: OCTO_EMAIL__SENDEREMAIL
  value: {{ .global.Values.notifications.smtp.senderEmailAddress }}  
- name: OCTO_EMAIL__USERNAME
  value: {{ .global.Values.notifications.smtp.username }}  
- name: OCTO_EMAIL__PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
      key: email

{{- else if eq .name "communication" -}}
{{- $name := "OCTO_COMMUNICATIONCONTROLLER" }}
{{ include "octo-mesh.system-env" . }}
{{ include "octo-mesh.broker-env" (dict "global" .global "name" $name) }}  
- name: OCTO_COMMUNICATIONCONTROLLER__AUTHORITY
  value: {{ .global.Values.services.identity.publicUri }}
{{- else if eq .name "adminPanel" -}}
{{- $name := "OCTO_ADMINPANEL" }}
- name: OCTO_ADMINPANEL__CRATEDBADMINURL
  value: {{ .global.Values.externalUris.crateDb }}
- name: OCTO_ADMINPANEL__ASSETSERVICEURL
  value: {{ .global.Values.services.assetRepository.publicUri }}
- name: OCTO_ADMINPANEL__BOTSERVICEURL
  value: {{ .global.Values.services.bot.publicUri }}         
- name: OCTO_ADMINPANEL__AUTHORITYURL
  value: {{ .global.Values.services.identity.publicUri }}
- name: OCTO_ADMINPANEL__PUBLICURL
  value: {{ .global.Values.services.adminPanel.publicUri }}

{{- else if eq .name "meshAdapter" -}}
{{- $name := "OCTO_ADAPTER" }}
{{ include "octo-mesh.streamdata-env" (dict "global" .global "name" $name) }}
- name: OCTO_ADAPTER__TENANTID
  value: {{ .svc.tenantId }}
- name: OCTO_ADAPTER__COMMUNICATIONCONTROLLERSERVICESURI
  value: {{ .global.Values.services.communication.publicUri }}
- name: OCTO_ADAPTER__ADAPTERCKTYPEID
  value: "System.Communication/MeshAdapter"              
- name: OCTO_ADAPTER__ADAPTERRTID
  value: {{ .svc.adapterRtId }}
- name: OCTO_ADAPTER__STREAMDATACONNECTIONSTRING
  valueFrom:
    secretKeyRef:
        name: {{ printf "%s-backend" (include "octo-mesh.fullname" .global) }}
        key: crateDbConnectionString
{{- else }}
{{- fail (printf "Service %s is not configured for the octo-mesh helm chart." .name) -}}
{{- end }}
{{- end }}